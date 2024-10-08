#!/bin/bash

# Run this to install docker packages and configure the `ochat`` user 

# Constants
DOCKER_REPO_URL="https://download.docker.com/linux/rhel/docker-ce.repo"
DOCKER_REPO_FILE=~/docker-ce.repo
DOCKER_PACKAGES="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
RHEL_PACKAGES="git python3-pip python3-boto3 python3-pymongo python3-ldap3 python3-dotenv"
NEWUSER="ochat"
SHELL_BIN="/bin/bash"

install_rhel_packages() {
  echo "Update the package database and install packages: "
  sudo dnf update -y
  sudo dnf install -y ${RHEL_PACKAGES}
}

# Function to install Docker
install_docker() {

  if [[ -f /usr/bin/docker ]]; then
    echo "Docker is already installed, please remove docker from this machine before this script can install docker-ce: dnf remove -y docker"
    return 1
  fi

  echo "Step 1: Add Docker repository"
  if [[ ! -f ${DOCKER_REPO_FILE} ]]; then
    sudo curl -fsSL ${DOCKER_REPO_URL} -o ${DOCKER_REPO_FILE}
  else
    echo "Docker repository already exists."
  fi

  echo "Step 2: Install Docker packages"
  sudo dnf install -y ${DOCKER_PACKAGES} --repo ${DOCKER_REPO_FILE}

  echo "Step 3: Start and enable Docker service"
  sudo systemctl start docker
  sudo systemctl enable docker

  echo "Step 4: Verify Docker installation"
  sudo docker --version

  echo "Step 5: Check on Docker group"
  if ! [[ $(getent group docker) ]]; then
    echo -e "\n**** WARNING: Group '${GROUP_NAME}' does not exist!!"
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
  install_rhel_packages
  install_docker
  create_or_modify_user
}

# Execute the main function
main