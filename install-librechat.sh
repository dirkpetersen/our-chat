#! /bin/bash

# re-install OurChat environment

CUSTOM_CFG_PATH=${HOME}
LIBRECHAT_PATH=${HOME}/LibreChat
DEPLOY_COMPOSE=deploy-compose-ourchat-dev.yml
CLONEDIR=$(dirname ${LIBRECHAT_PATH})

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
  echo "copying ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} to ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  cp ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ${LIBRECHAT_PATH}/
else 
  if head -n 1 "${LIBRECHAT_PATH}/deploy-compose.yml" | grep -q '^version:'; then
    tail -n +2 "${LIBRECHAT_PATH}/deploy-compose.yml" > "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  else
    cp "${LIBRECHAT_PATH}/deploy-compose.yml" "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  fi
  # setup proxy
  sed -i '/ports:/,/^[^ ]/ s/- 80:80/- 2080:80/; /ports:/,/^[^ ]/ s/- 443:443/- 2443:443/' \
              ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}
fi

# remove some non-functional bedrock models
sed -i "/^[[:space:]]*'ai21.jamba-instruct-v1:0',/s/^[[:space:]]*/&\/\/ /" \
              ${LIBRECHAT_PATH}/packages/data-provider/src/config.ts


# .env file
if [[ -f ${CUSTOM_CFG_PATH}/.env ]]; then
  echo "copying ${CUSTOM_CFG_PATH}/.env to ${LIBRECHAT_PATH}/.env"
  cp  ${CUSTOM_CFG_PATH}/.env ${LIBRECHAT_PATH}/.env
else
  echo ".env.example to .env"
  cp  ${LIBRECHAT_PATH}/.env.example ${LIBRECHAT_PATH}/.env
fi

if [[ -f ${CUSTOM_CFG_PATH}/librechat.yaml ]]; then
  echo "copying ${CUSTOM_CFG_PATH}/librechat.yaml to ${LIBRECHAT_PATH}/librechat.yaml"
  cp  ${CUSTOM_CFG_PATH}/librechat.yaml ${LIBRECHAT_PATH}/librechat.yaml
else
  echo "copying librechat.example.yaml to librechat.yaml"
  cp  ${LIBRECHAT_PATH}/librechat.example.yaml ${LIBRECHAT_PATH}/librechat.yaml
fi

if [[ -f ${CUSTOM_CFG_PATH}/docker-compose.override.yml ]]; then
  echo "copying ${CUSTOM_CFG_PATH}/docker-compose.override.yml to ${LIBRECHAT_PATH}"
  cp ${CUSTOM_CFG_PATH}/docker-compose.override.yml ${LIBRECHAT_PATH}
fi

docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d

echo "stopping: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} down"
echo "starting: docker compose -f ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE} up -d"

if [[ -f ${CUSTOM_CFG_PATH}/${DEPLOY_COMPOSE} ]]; then
  cd ${LIBRECHAT_PATH}
  npm ci
  npm run frontend 
  #npm run backend # run by systemd
  echo "systemctl --user status librechat-backend .... "
  systemctl --user restart librechat-backend
  systemctl --user status librechat-backend
fi

