#!/bin/bash

# Run this to install docker packages and configure the `ochat`` user 

# Constants
DOCKER_ROOT_URL="https://download.docker.com/linux"
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
DOCKER_GROUP_NAME="docker"
OS_PACKAGES="git unzip python3-pip python3-boto3 python3-pymongo python3-ldap3"
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
    sudo dnf update -y
    sudo dnf install -y --skip-broken ${OS_PACKAGES}
  fi
}

# Function to install Docker
install_docker() {

  if [[ -f /usr/bin/docker ]]; then
    echo "Docker is already installed, please remove docker from this machine before this script can install docker-ce: dnf remove -y docker"
    return 1
  fi

  if command -v apt-get >/dev/null 2>&1; then

    echo "Step 1: Add Docker repository"

    sudo apt install -y ca-certificates gnupg lsb-release
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
    echo "Step 1: Add Docker repository"
    DOCKER_REPO_FILE=~/docker-ce.repo
    if [[ ! -f ${DOCKER_REPO_FILE} ]]; then
      sudo curl -fsSL ${DOCKER_ROOT_URL}/rhel/docker-ce.repo -o ${DOCKER_REPO_FILE}
    else
      echo "Docker repository already exists."
    fi
    echo "Step 2: Install Docker packages"
    sudo dnf install -y ${DOCKER_PACKAGES} --repo ${DOCKER_REPO_FILE}
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


# Main function to execute all steps
function main {
  install_os_packages
  install_docker
  create_or_modify_user
}

# Execute the main function
main