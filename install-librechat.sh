#! /bin/bash

# (re)-install LibreChat in OurChat environment 
# To activate DEV mode, copy a custom $DEPLOY_COMPOSE
# file to $CUSTOM_CFG_PATH and remove  api: and client: 
# services from it, they are run in librechat-backend.service

CUSTOM_CFG_PATH=${HOME}
LIBRECHAT_PATH=${HOME}/LibreChat
DEPLOY_COMPOSE=deploy-compose-ourchat-dev.yml
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

purge_cron_job() {
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
  systemctl --user stop librechat-backend 
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
  sed -i '/- \.\/client\/nginx\.conf:\/etc\/nginx\/conf\.d\/default\.conf/a\      - ./client/ssl:/etc/librechat/ssl' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  # allow access to Mongo DB to purge old messages
  sed -i '/# ports:.*# Uncomment this to access mongodb/,+1 s/^    # /    /' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  
  # use the full blown RAG container - not needed for bedrock 
  #sed -i 's/librechat-rag-api-dev-lite:latest/librechat-rag-api-dev:latest/g' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"

  # if not using librechat nginx make sure we can use the system nginx by using different ports
  if ! [[ -f ${CUSTOM_CFG_PATH}/nginx.conf ]]; then 
    sed -i '/ports:/,/^[^ ]/ s/- 80:80/- 2080:80/; /ports:/,/^[^ ]/ s/- 443:443/- 2443:443/' \
              ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}
  fi
fi

# remove some non-functional bedrock models; this works only in dev mode 
sed -i "/^[[:space:]]*'ai21.jamba-instruct-v1:0',/s/^[[:space:]]*/&\/\/ /" \
              ${LIBRECHAT_PATH}/packages/data-provider/src/config.ts

# pull aws credentials into env vars
aws_creds

# .env file
if [[ -f ${CUSTOM_CFG_PATH}/.env ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/.env to ${LIBRECHAT_PATH}/.env and expanding env vars"
  envsubst < ${CUSTOM_CFG_PATH}/.env > ${LIBRECHAT_PATH}/.env
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

# client/nginx.conf
if [[ -f ${CUSTOM_CFG_PATH}/nginx.conf ]]; then
  if ! [[ -f ${LIBRECHAT_PATH}/client/nginx.conf.org  ]]; then
    mv ${LIBRECHAT_PATH}/client/nginx.conf ${LIBRECHAT_PATH}/client/nginx.conf.org
  fi 
  echo "Copying ${CUSTOM_CFG_PATH}/nginx.conf to ${LIBRECHAT_PATH}/client/nginx.conf"
  cp  ${CUSTOM_CFG_PATH}/nginx.conf ${LIBRECHAT_PATH}/client/nginx.conf
  mkdir -p ${LIBRECHAT_PATH}/client/ssl
  cp ${CUSTOM_CFG_PATH}/*.pem ${LIBRECHAT_PATH}/client/ssl
  cp ${CUSTOM_CFG_PATH}/*.pw ${LIBRECHAT_PATH}/client/ssl
  chmod 600 ${LIBRECHAT_PATH}/client/ssl/*.pw
  
  if ! curl -f https://ssl-config.mozilla.org/ffdhe2048.txt -o ${LIBRECHAT_PATH}/client/ssl/dhparam; then 
    openssl dhparam -out ${LIBRECHAT_PATH}/client/ssl/dhparam 2048
  fi 
fi

# docker-compose.override.yml
if [[ -f ${CUSTOM_CFG_PATH}/docker-compose.override.yml ]]; then
  echo "Copying ${CUSTOM_CFG_PATH}/docker-compose.override.yml to ${LIBRECHAT_PATH}"
  cp ${CUSTOM_CFG_PATH}/docker-compose.override.yml ${LIBRECHAT_PATH}
fi

purge_cron_job

docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d

echo "stopping: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} down"
echo "starting: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d"

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
