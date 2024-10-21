#!/bin/bash

# Run this to install dependencies, docker packages and configure the `ochat`` user 

# Constants
DOCKER_ROOT_URL="https://download.docker.com/linux"
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
DOCKER_GROUP_NAME="docker"
OS_PACKAGES="vim git unzip ca-certificates gnupg certbot python3-pip python3-boto3 python3-pymongo python3-ldap3"
NEWUSER="ochat"
SHELL_BIN="/bin/bash"

install_os_packages() {
  echo "Update the package database and install packages: "
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update -y    
    # Initial installation attempt (can also use --no-install-recommends here)
    OS_PACKAGES+=" netcat-openbsd"
    sudo apt install -y ${OS_PACKAGES} || {
      # Retry missing packages individually if the initial attempt fails
      for package in ${OS_PACKAGES}; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
          echo "Retrying installation of missing package: $package"
          sudo apt install -y --no-install-recommends "$package" || echo "Failed to install $package"
        fi
      done
    }
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf check-update --refresh
    if [[ -f /etc/system-release ]] && grep -q Amazon /etc/system-release; then
      echo "Amazon Linux detected, no epel-release available"
    else
      sudo dnf install -y epel-release
    fi
    OS_PACKAGES+=" nmap-ncat"
    sudo dnf install -y --skip-broken ${OS_PACKAGES}
  fi
}

# Function to install Docker
install_docker() {

  if [[ -f /usr/bin/docker ]]; then
    echo "Docker is already installed, please remove docker from this machine before this script can install docker-ce from docker.com"
    return 1
  fi
  DOCKER_ROOT="/var/lib/docker"
  if [[ "${LARGEST_FS}" != "/" ]]; then
    DOCKER_ROOT="${LARGEST_FS}/var/lib/docker"
    sudo mkdir -p $DOCKER_ROOT
    sudo mkdir -p '/etc/docker'
    echo -e "{\n \"data-root\": \"${DOCKER_ROOT}\"\n}" | sudo tee /etc/docker/daemon.json > /dev/null
  fi
  
  if command -v apt-get >/dev/null 2>&1; then

    echo "Step 1: Add Docker repository"

    # Add Docker’s official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL ${DOCKER_ROOT_URL}/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    # Set up the Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_ROOT_URL}/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine, CLI, and containerd
    echo "Step 2: Install Docker packages"
    sudo apt update -y
    sudo apt install -y ${DOCKER_PACKAGES}
    
  elif command -v dnf >/dev/null 2>&1; then

    if [[ -f /etc/system-release ]] && grep -q Amazon /etc/system-release; then
      echo "Amazon Linux detected, special Docker installation"
      echo "Step 1: Add Docker repository (skipped)"
      echo "Step 2: Install Docker packages from standard repos"
      sudo dnf install -y docker crontabs
      # optionally install Docker Compose plugin
      # install_docker_compose_plugin
    else
      echo "Step 1: Add Docker repository"
      sudo dnf config-manager --add-repo ${DOCKER_ROOT_URL}/rhel/docker-ce.repo
      echo "Step 2: Install Docker packages"
      sudo dnf install -y --skip-broken ${DOCKER_PACKAGES} # --repo ${DOCKER_REPO_FILE}
    fi

    echo "Step 3: Start and enable Docker service"
    sudo systemctl start docker
    sudo systemctl enable docker

    echo "Step 4: Verify Docker installation"
    sudo docker --version

    echo "Step 5: Check on Docker group"
    if ! [[ $(getent group ${DOCKER_GROUP_NAME}) ]]; then
      echo -e "\n**** WARNING: Group '${DOCKER_GROUP_NAME}' does not exist!!"
      echo -e "**** Check troubleshooting section ********* \n"
    fi
  else
    echo "Unsupported OS, please install Docker manually."
  fi
}

install_docker_compose_plugin() {
  echo "Installing Docker Compose plugin..."
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p $DOCKER_CONFIG/cli-plugins
  sudo curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o $DOCKER_CONFIG/cli-plugins/docker-compose
  sudo chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
}

# Function to create or modify the user
create_or_modify_user() {
  if id "${NEWUSER}" &>/dev/null; then
    echo "User ${NEWUSER} already exists."
  else
    echo "Creating user ${NEWUSER}..."
    if [[ "${LARGEST_FS}" != "/" ]]; then
      LHOMEDIR="${LARGEST_FS}/home"
      sudo mkdir -p $LHOMEDIR
      sudo useradd -rm --shell ${SHELL_BIN} --home-dir "${LHOMEDIR}/${NEWUSER}" ${NEWUSER}
    else
      sudo useradd -rm --shell ${SHELL_BIN} ${NEWUSER}
    fi
  fi

  echo "Enabling linger for ${NEWUSER}..."
  sudo loginctl enable-linger ${NEWUSER}
  sudo usermod -aG docker ${NEWUSER}

  echo "Configure environment for ${NEWUSER} ..."
  sudo su - ${NEWUSER} -c "bash -c '
    echo \"export DBUS_SESSION_BUS_ADDRESS=\${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/\$(id -u)/bus}\" >> ~/.bashrc
    echo \"export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}\" >> ~/.bashrc
    source ~/.bashrc
  '"
  echo -e "\nEnter: sudo su - ${NEWUSER}"
}

write_options_ssl_nginx() {
  local file_path="/etc/letsencrypt/options-ssl-nginx.conf"
  cat << EOF | sudo tee ${file_path} > /dev/null
# SSL configuration options provided by Certbot
# Right now we just make sure that this file exists 
# as we did not install certbot with nginx options
EOF
}

# Define function to obtain, secure, and store SSL certificates
generate_le_ssl_certificate() {
  local fqdn=${1}

  # Run certbot to obtain certificate
  # run --standalone or --nginx or 'certbot certonly'
  sudo certbot certonly \
    --register-unsafely-without-email \
    --agree-tos \
    --standalone \
    --domain "${fqdn}"

  # Some manual fixes for nginx
  # if ! sudo curl -f https://ssl-config.mozilla.org/ffdhe2048.txt -o /etc/letsencrypt/ssl-dhparams.pem; then 
  #   sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
  # fi 
  # write_options_ssl_nginx
}

# Function to get public IP
get_public_ip() {
    curl -s https://api.ipify.org
}

# Function to check if a port is open, returns 0 (true) if open, 1 (false) if closed
is_port_open() {
  local port=$1
  local hostname=${2:-$(get_public_ip)}
  local url="https://ports.yougetsignal.com/check-port.php"

  sudo nc -l -p 80 &>/dev/null &
  local result=$(curl -s --data "remoteAddress=$hostname&portNumber=$port" "$url")
  sudo pkill -f "nc -l -p 80"

  if [ -z "$result" ]; then
    echo "Error: No response from YouGetSignal" >&2
    return 2
  fi

  if echo "$result" | grep -q "flag_green.gif"; then
    return 0  # Port is open
  elif echo "$result" | grep -q "flag_red.gif"; then
    return 1  # Port is closed
  else
    echo "Unable to determine the status of port $port on $hostname" >&2
    echo "Raw response: $result" >&2
    return 2  # Error
  fi
}

# Main function to execute all steps
function main {
  # get the file system with the most available space on this machine and install /home and /docker there
  LARGEST_FS=$(df -l --output=target,avail | awk 'NR>1 {print $2,$1}' | sort -nr | head -n1 | awk '{print $2}')
  install_os_packages
  install_docker
  # Check if /var/tmp/librechat-domain.txt exists and read the domain from there
  if [[ -f /var/tmp/librechat-domain.txt ]]; then
    default_domain=$(cat /var/tmp/librechat-domain.txt)
  else
    default_domain=""
  fi
  if [[ -n ${1} ]]; then
    mydomain=${1}
  else
    echo ""
    echo "Enter the full hostname (FQDN) of this server to generate a Let's Encrypt SSL certificate"
    echo "NOTE: For this to work, this server must be reachable on port 80 (http) from the internet."
    echo "Otherwise you can skip this step and manually setup SSL certs from your IT team later."
    echo "Please hit just 'Enter' to skip creating Let's Encrypt SSL certs (5 min timeout)"
    read -t 300 -e -i "$default_domain" -p "Enter FQDN: " mydomain < /dev/tty
  fi
  if [[ -n ${mydomain} ]]; then
    if is_port_open 80 $mydomain; then
      echo "Port 80 is open on $mydomain. Proceeding to generate Let's Encrypt SSL certificate..."
      generate_le_ssl_certificate $mydomain
    else
      echo "Port 80 is not open on $mydomain. Please open port 80 to incoming internet traffic and try again."
    fi
    echo "$mydomain" > /var/tmp/librechat-domain.txt
  fi
  create_or_modify_user
}

# Execute the main function
main