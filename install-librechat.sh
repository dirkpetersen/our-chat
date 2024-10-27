#! /bin/bash

# (re)-install LibreChat in OurChat environment 
# To activate DEV mode, copy a custom $DEPLOY_COMPOSE
# file to $CUSTOM_CFG_PATH and remove  api: and client: 
# services from it, they are run in librechat-backend.service

CUSTOM_CFG_PATH=${HOME}
LIBRECHAT_PATH=${HOME}/LibreChat
DEPLOY_COMPOSE=deploy-compose-ourchat.yml
CLONEDIR=$(dirname ${LIBRECHAT_PATH})
SERVICE_NAME="librechat-backend.service"

# Create the systemd service file
create_service_file() {
  local SERVICE_PATH="${HOME}/.config/systemd/user/${SERVICE_NAME}"
  mkdir -p "${HOME}/.config/systemd/user"
  cat << EOF > "${SERVICE_PATH}"
[Unit]
Description=LibreChat Backend Server
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/LibreChat
ExecStart=/bin/bash -c 'source ~/.bashrc && npm run backend'
Restart=on-failure
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=NODE_ENV=development

[Install]
WantedBy=default.target
EOF
}

# Reload systemd user daemon, start the service, and enable it
setup_user_service() {
  systemctl --user daemon-reload
  systemctl --user restart "${SERVICE_NAME}"
  systemctl --user enable "${SERVICE_NAME}"
  systemctl --user status "${SERVICE_NAME}"
}

aws_creds() {

  if ! command -v aws >/dev/null 2>&1; then
    if [[ -f ~/.local/bin/aws ]]; then
      echo "AWS CLI is already installed but not in PATH"
    else  
      echo "Installing AWS CLI v2..."
      # Create a temporary directory
      tmpdir=$(mktemp -d -t awscli-XXX)
      # Download, unzip, and install AWS CLI v2 using full paths
      arch=$(uname -m)
      # Set the appropriate URL based on the architecture
      if [[ "$arch" == "x86_64" ]]; then
         cliurl="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      elif [[ "$arch" == "aarch64" ]]; then
         cliurl="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
      else
        echo "Unsupported architecture: $arch. Please install AWS CLI v2 manually and restart the script."
        exit 1
      fi
      curl "${cliurl}" -o "${tmpdir}/awscliv2.zip" \
        && unzip "${tmpdir}/awscliv2.zip" -d "${tmpdir}" \
        && "${tmpdir}/aws/install" -i ~/.local/share/aws-cli -b ~/.local/bin
      # Clean up by removing the temporary directory
      rm -rf "$tmpdir"
    fi
    export PATH=~/.local/bin:$PATH
  fi
  # Retrieve static credentials
  echo "export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)" > ~/.awsrc
  echo "export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)" >> ~/.awsrc
  echo "export AWS_DEFAULT_REGION=$(aws configure get region)" >> ~/.awsrc
  chmod 600 ~/.awsrc
  if ! grep -Fxq "source ~/.awsrc" ~/.bashrc; then
    echo "source ~/.awsrc" >> ~/.bashrc
    echo "~/.awsrc has been added to .bashrc"
  fi
  source ~/.awsrc
}

setup_cron_jobs() {
  DCCMD="/usr/bin/docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d"
  CRON_JOB="@reboot ${DCCMD} > ~/reboot.log 2>&1"
  # Add the cron job for the current user
  if ! crontab -l | grep -Fq "${DEPLOY_COMPOSE}"; then
    ( crontab -l; echo "${CRON_JOB}" ) | crontab -
    echo "Cron job added to run ${DCCMD} at reboot."
  fi  

  # Determine the current script's directory
  SCRIPT_DIR=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
  # Set the full path to the script to be run
  SCRIPT_PATH="${SCRIPT_DIR}/purge_old_messages.py"
  # Define the cron job entry
  CRON_JOB="22 2 * * * \"${SCRIPT_PATH}\" > ~/purge_old_messages.log 2>&1"
  # Add the cron job for the current user
  if ! crontab -l | grep -Fq "${SCRIPT_PATH}"; then
    ( crontab -l; echo "${CRON_JOB}" ) | crontab -
    echo "Cron job added to run ${SCRIPT_PATH} daily at 2:22 AM."
  fi  
}

install_docker_compose_plugin() {
  echo "Installing Docker Compose plugin..."
  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
  DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
  mkdir -p $DOCKER_CONFIG/cli-plugins
  curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o $DOCKER_CONFIG/cli-plugins/docker-compose
  chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
}

# Function to activate Certbot certificates
activate_certbot_certs() {

  # Check if the domain file exists
  if [[ -z ${FQDN} ]]; then
    echo "FQDN has not been set. Skipping certbot SSL activation."
    return 1
  fi
  if ! [[ -d /etc/letsencrypt ]]; then
    echo "/etc/letsencrypt does not exist. Skipping certbot SSL activation."
    return 1
  fi

  # Edit nginx-ourchat.conf to comment out the old SSL lines and add new ones
  sed -i \
    -e '\|ssl_certificate /etc/librechat/ssl/our-chat.pem;| s|^|# |' \
    -e '\|ssl_certificate_key /etc/librechat/ssl/our-chat.pem;| s|^|# |' \
    -e '\|ssl_password_file /etc/librechat/ssl/our-chat.pw;| s|^|# |' \
    -e "\|ssl_password_file /etc/librechat/ssl/our-chat.pw;|a\\
    ssl_certificate /etc/letsencrypt/live/${FQDN}/fullchain.pem;\\
    ssl_certificate_key /etc/letsencrypt/live/${FQDN}/privkey.pem;" \
    "${CUSTOM_CFG_PATH}/nginx-ourchat.conf"

  echo "nginx-ourchat.conf has been updated with the new SSL configuration."

  # Add the /etc/letsencrypt line in deploy-compose file
  sed -i '\|/etc/nginx/conf.d/default.conf|a\      - /etc/letsencrypt:/etc/letsencrypt' \
      "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"  

  echo "${DEPLOY_COMPOSE} has been updated to include /etc/letsencrypt."

}

######### Main Script ###################################################

FQDN=""
DOMAIN_FILE="/var/tmp/librechat-domain.txt"
if [[ -f ${DOMAIN_FILE} ]]; then
  FQDN=$(<${DOMAIN_FILE})
fi

if ! docker compose version &> /dev/null; then
  install_docker_compose_plugin
fi

if [[ -d ${LIBRECHAT_PATH} ]]; then
  if ! [[ -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} ]]; then
    echo "System has not been deployed with"
    echo "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}."
    echo "Exiting."
    exit
  fi
  echo "Shutting down containers..."
  docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} down
  DOCK=$(docker images -q)
  if [[ -n ${DOCK} ]]; then 
    echo -e "Keep Docker images:\n ${DOCK}"
  fi
  DOCK=$(docker volume ls -q)
  if [[ -n ${DOCK} ]]; then
    docker volume rm ${DOCK}
  fi
  if [[ -f ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ]]; then
    systemctl --user stop librechat-backend 
  fi  
  echo "${LIBRECHAT_PATH} already exists. Rename this folder and run again"
  cd "${CLONEDIR}"
  exit
fi 

if ! [[ -d ${CLONEDIR} ]]; then
  echo "Dir ${CLONEDIR}, does not exist, cannot run git clone. Exiting."
  exit
fi
cd ${CLONEDIR}

git clone https://github.com/danny-avila/LibreChat.git

if [[ -f ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} to ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  cp ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ${LIBRECHAT_PATH}/
else 
  echo "Copying ${LIBRECHAT_PATH}/deploy-compose.yml to ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  if head -n 1 "${LIBRECHAT_PATH}/deploy-compose.yml" | grep -q '^version:'; then
    tail -n +2 "${LIBRECHAT_PATH}/deploy-compose.yml" > "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  else
    cp "${LIBRECHAT_PATH}/deploy-compose.yml" "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  fi
  # insert path to ssl certs at /etc/librechat/ssl
  sed -i '\|/etc/nginx/conf.d/default.conf|a\      - ./client/ssl:/etc/librechat/ssl' \
      "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  # allow access to Mongo DB to purge old messages
  sed -i '/# ports:.*# Uncomment this to access mongodb/,+1 s/^    # /    /' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  
  # use the full blown RAG container - not needed for bedrock 
  #sed -i 's/librechat-rag-api-dev-lite:latest/librechat-rag-api-dev:latest/g' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"

  # use libechat nginx with a custom config file
  if [[ -f ${CUSTOM_CFG_PATH}/nginx-ourchat.conf ]]; then 
    sed -i 's|      - ./client/nginx.conf:/etc/nginx/conf.d/default.conf|      - ./client/nginx-ourchat.conf:/etc/nginx/conf.d/default.conf|' \
    "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
    echo "${DEPLOY_COMPOSE} has been updated to use nginx-ourchat.conf"

    activate_certbot_certs
  else
    # if not using librechat nginx make sure we can use the system nginx by using different ports
    sed -i '/ports:/,/^[^ ]/ s/- 80:80/- 2080:80/; /ports:/,/^[^ ]/ s/- 443:443/- 2443:443/' \
              ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}
  fi
fi

# this needs to be disabled as it interferes with git pull updates 
# remove some non-functional bedrock models; this works only in dev mode 
#sed -i "/^[[:space:]]*'ai21.jamba-instruct-v1:0',/s/^[[:space:]]*/&\/\/ /" \
#              ${LIBRECHAT_PATH}/packages/data-provider/src/config.ts

# pull aws credentials into env vars
aws_creds

# .env file
if [[ -f ${CUSTOM_CFG_PATH}/.env ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/.env to ${LIBRECHAT_PATH}/.env and expanding env vars"
  envsubst < ${CUSTOM_CFG_PATH}/.env > ${LIBRECHAT_PATH}/.env
  cp -f ${LIBRECHAT_PATH}/.env ${CUSTOM_CFG_PATH}/.env 
else
  echo ".env.example to .env"
  cp  ${LIBRECHAT_PATH}/.env.example ${LIBRECHAT_PATH}/.env
fi

# librechat.yaml
if [[ -f ${CUSTOM_CFG_PATH}/librechat.yaml ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/librechat.yaml to ${LIBRECHAT_PATH}/librechat.yaml"
  cp  ${CUSTOM_CFG_PATH}/librechat.yaml ${LIBRECHAT_PATH}/librechat.yaml
else
  echo "Copying librechat.example.yaml to librechat.yaml"
  cp  ${LIBRECHAT_PATH}/librechat.example.yaml ${LIBRECHAT_PATH}/librechat.yaml
fi

# client/nginx-ourchat.conf
if [[ -f ${CUSTOM_CFG_PATH}/nginx-ourchat.conf ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/nginx-ourchat.conf to ${LIBRECHAT_PATH}/client/nginx-ourchat.conf"
  cp  ${CUSTOM_CFG_PATH}/nginx-ourchat.conf ${LIBRECHAT_PATH}/client/nginx-ourchat.conf
  mkdir -p ${LIBRECHAT_PATH}/client/ssl
  if [[ -f ${CUSTOM_CFG_PATH}/our-chat.pem ]]; then
    cp ${CUSTOM_CFG_PATH}/our-chat.pem ${LIBRECHAT_PATH}/client/ssl
    cp ${CUSTOM_CFG_PATH}/our-chat.pw ${LIBRECHAT_PATH}/client/ssl
    chmod 600 ${LIBRECHAT_PATH}/client/ssl/*.pw
  fi
  if ! curl -f https://ssl-config.mozilla.org/ffdhe2048.txt -o ${LIBRECHAT_PATH}/client/ssl/dhparam; then 
    openssl dhparam -out ${LIBRECHAT_PATH}/client/ssl/dhparam 2048
  fi 
fi

# docker-compose.override.yml
if [[ -f ${CUSTOM_CFG_PATH}/docker-compose.override.yml ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/docker-compose.override.yml to ${LIBRECHAT_PATH}"
  cp ${CUSTOM_CFG_PATH}/docker-compose.override.yml ${LIBRECHAT_PATH}
fi

setup_cron_jobs

docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d

echo "stopping: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} down"
echo "starting: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d"

if [[ -n ${FQDN} ]]; then
  echo "*** If you wait a little and run this command you should see '<title>LibreChat</title>': ***"
  echo "curl -s https://${FQDN} | grep LibreChat"
fi 

if [[ -f ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ]]; then
  cd ${LIBRECHAT_PATH}
  npm ci
  npm run frontend 
  #npm run backend # run by systemd
  echo "systemctl --user status librechat-backend .... "
  # Main script execution
  create_service_file
  setup_user_service
fi

grep -qxF '# Instructions to update LibreChat' ~/.bashrc || echo -e \
'\n# Instructions to update LibreChat\ncat << EOF\nTo update LibreChat run this:' \
'\n\ncd ~/LibreChat\ndocker compose -f deploy-compose-ourchat.yml down\ngit pull' \
'\ndocker compose -f deploy-compose-ourchat.yml pull\ndocker compose -f' \
'deploy-compose-ourchat.yml up\nEOF\n' >> ~/.bashrc


