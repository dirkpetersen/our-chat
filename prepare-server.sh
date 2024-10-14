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
    sudo dnf install -y --skip-broken ${OS_PACKAGES}
  fi
}

# Function to install Docker
install_docker() {

  if [[ -f /usr/bin/docker ]]; then
    echo "Docker is already installed, please remove docker from this machine before this script can install docker-ce from docker.com"
    return 1
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
      echo "Step 2: Install Docker packages"
      sudo dnf install -y docker crontabs
      # optionally install Docker Compose plugin
      # install_docker_compose_plugin
    else
      echo "Step 1: Add Docker repository"
      #DOCKER_REPO_FILE=/home/ec2-user/docker-ce.repo
      sudo dnf config-manager --add-repo ${DOCKER_ROOT_URL}/rhel/docker-ce.repo
      # if [[ ! -f ${DOCKER_REPO_FILE} ]]; then
      #   curl -fsSL ${DOCKER_ROOT_URL}/rhel/docker-ce.repo -o ${DOCKER_REPO_FILE}
      # else
      #   echo "Docker repository already exists."
      # fi
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
    sudo useradd -rm --shell ${SHELL_BIN} ${NEWUSER}
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
  cat << EOF > ${file_path}
# SSL configuration options provided by Certbot
ssl_session_cache shared:le_nginx_SSL:1m; # Caches SSL session parameters to speed up future connections
ssl_session_timeout 1440m; # Defines the duration for which the SSL session cache is valid

ssl_protocols TLSv1.2 TLSv1.3; # Specifies the protocols supported (avoiding outdated versions)
ssl_prefer_server_ciphers on; # Prioritizes server-defined cipher suites over client preferences

# List of strong SSL ciphers
ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";

# Ensures that client requests are denied if they lack SNI
ssl_ecdh_curve secp384r1; # Defines the elliptic curve for Diffie-Hellman key exchange

# Strong Diffie-Hellman parameter, typically at /etc/letsencrypt/ssl-dhparams.pem
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

ssl_session_tickets off; # Disables session tickets for added security
ssl_stapling on; # Enables OCSP stapling for faster certificate validation
ssl_stapling_verify on; # Verifies the OCSP response for added security
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
  if ! curl -f https://ssl-config.mozilla.org/ffdhe2048.txt -o /etc/letsencrypt/ssl-dhparams.pem; then 
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
  fi 
  write_options_ssl_nginx
}

# Main function to execute all steps
function main {
  install_os_packages
  install_docker
  if [[ -n ${1} ]]; then
    mydomain=${1}
  else
    echo ""
    echo "Enter the full hostname (FQDN) of this server to generate a Let's Encrypt SSL certificate"
    echo "NOTE: For this to work, this server must be reachable on port 80 from the internet."
    read -t 60 -p "Please hit just 'Enter' to skip creating Let's Encrypt SSL certs (60 sec timeout): " mydomain < /dev/tty
  fi
  if [[ -n ${mydomain} ]]; then
    generate_le_ssl_certificate $mydomain
    echo "$mydomain" > /tmp/librechat-domain.txt
  fi
  create_or_modify_user
}

# Execute the main function
main