#! /bin/bash

# re-install OurChat environment

CUSTOM_CFG_PATH=${HOME}
LIBRECHAT_PATH=${HOME}/LibreChat
DEPLOY_COMPOSE=deploy-compose-ourchat-dev-xxx.yml
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
  # insert path to ssl certs /etc/librechat/certs
  sed -i '/- \.\/client\/nginx\.conf:\/etc\/nginx\/conf\.d\/default\.conf/a\      - ./client/certs:/etc/librechat/certs' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"
  # use the full blown RAG container
  #sed -i 's/librechat-rag-api-dev-lite:latest/librechat-rag-api-dev:latest/g' "${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}"

  # if not using librechat nginx make sure we can use the system nginx by using different ports
  if ! [[ -f ${CUSTOM_CFG_PATH}/nginx.conf ]]; then 
    sed -i '/ports:/,/^[^ ]/ s/- 80:80/- 2080:80/; /ports:/,/^[^ ]/ s/- 443:443/- 2443:443/' \
              ${LIBRECHAT_PATH}/${DEPLOY_COMPOSE}
  fi
fi

# remove some non-functional bedrock models, work only in dev mode 
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

# librechat.yaml
if [[ -f ${CUSTOM_CFG_PATH}/librechat.yaml ]]; then
  echo "copying ${CUSTOM_CFG_PATH}/librechat.yaml to ${LIBRECHAT_PATH}/librechat.yaml"
  cp  ${CUSTOM_CFG_PATH}/librechat.yaml ${LIBRECHAT_PATH}/librechat.yaml
else
  echo "copying librechat.example.yaml to librechat.yaml"
  cp  ${LIBRECHAT_PATH}/librechat.example.yaml ${LIBRECHAT_PATH}/librechat.yaml
fi

# client/nginx.conf
if [[ -f ${CUSTOM_CFG_PATH}/nginx.conf ]]; then
  if ! [[ -f ${LIBRECHAT_PATH}/client/nginx.conf.org  ]]; then
    mv ${LIBRECHAT_PATH}/client/nginx.conf ${LIBRECHAT_PATH}/client/nginx.conf.org
  fi 
  echo "copying ${CUSTOM_CFG_PATH}/nginx.conf to ${LIBRECHAT_PATH}/client/nginx.conf"
  cp  ${CUSTOM_CFG_PATH}/nginx.conf ${LIBRECHAT_PATH}/client/nginx.conf
  mkdir -p ${LIBRECHAT_PATH}/client/certs
  cp ${CUSTOM_CFG_PATH}/*.pem ${LIBRECHAT_PATH}/client/certs
  cp ${CUSTOM_CFG_PATH}/*.pw ${LIBRECHAT_PATH}/client/certs  
fi

# docker-compose.override.yml
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
