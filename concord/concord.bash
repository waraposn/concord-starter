#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Concord
# ------------------------------------------------------------------------------
CONCORD_DOTDIR=$HOME/.concord
CONCORD_PROFILE=${CONCORD_DOTDIR}/profile
[ -f ${CONCORD_PROFILE} ] && source ${CONCORD_PROFILE}

# Running minikube locally for development so determine the host and port by asking minikube
if [ ! -z "${minikube}" -a "${minikube}" = "true" ]
then
  CONCORD_HOST_PORT=`minikube service concord-server --namespace concord --format "{{.IP}}:{{.Port}}" --url | sed 's@^\* @@'`
fi

CONCORD_VERSION=${CONCORD_VERSION:-1.36.0}
CONCORD_ORGANIZATION=${CONCORD_ORGANIZATION:-concord}
CONCORD_DOCKER_NAMESPACE=${CONCORD_DOCKER_NAMESPACE:-walmartlabs}
CONCORD_HOST_PORT=${CONCORD_HOST_PORT:-localhost:8080}
PORT=`echo $CONCORD_HOST_PORT | sed "s/^.*://"`
SERVER_CONFIGURATION_TEMPLATE="${DIR}/concord/templates/server.conf.template"
SERVER_CONFIGURATION="${DIR}/concord/config/server.conf"
AGENT_CONFIGURATION_TEMPLATE="${DIR}/concord/templates/agent.conf.template"
AGENT_CONFIGURATION="${DIR}/concord/config/agent.conf"
CONCORD_DB_NAME="concord-db-${CONCORD_ORGANIZATION}-${CONCORD_ACCOUNT}"

# ------------------------------------------------------------------------------
# Support multiple organizations in the same Concord instance with a simple
# namespace mechanism.
# ------------------------------------------------------------------------------
NS="${CONCORD_ACCOUNT}"

# ------------------------------------------------------------------------------
# Postgres
# ------------------------------------------------------------------------------
POSTGRES_VERSION=${POSTGRES_VERSION:-10.6}
POSTGRES_PORT=${POSTGRES_PORT:-5432}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-q1q1q1q1}
POSTGRES_PASSWORD_B64=`echo ${POSTGRES_PASSWORD} | base64`

HOST_PATH="$HOME/.m2/repository"

CONTAINER_PATH="/repo"
DIND_HOST_PATH="/repo"
DIND_CONTAINER="docker:stable-dind"

# ------------------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------------------
GET_AWS_PROFILE="${CONCORD_DOTDIR}/aws/get-aws-profile.sh"

CURL="curl -L -sS -o /dev/null "
CURL_WITH_OUTPUT="curl -L -sS"

concord_profile() {
  mkdir -p ${CONCORD_DOTDIR} > /dev/null 2>&1
  cp ${DIR}/concord/templates/profile.template ${CONCORD_DOTDIR}/default
  cp ${DIR}/concord/concord.bash ${CONCORD_DOTDIR}
  ln -s ${CONCORD_DOTDIR}/default ${CONCORD_DOTDIR}/profile
  # AWS Helper to extract
  cp -r ${DIR}/concord/aws $CONCORD_DOTDIR
}

concord_show_variables() {
  echo
  echo "Using the following values:"
  echo
  echo "           WORKING_DIRECTORY = ${DIR}"
  echo "             CONCORD_PROFILE = ${CONCORD_PROFILE}"
  echo "             CONCORD_VERSION = ${CONCORD_VERSION}"
  echo "        CONCORD_ORGANIZATION = ${CONCORD_ORGANIZATION}"
  echo "CONCORD_SERVER_CONFIGURATION = ${SERVER_CONFIGURATION}"
  echo "  AGENT_SERVER_CONFIGURATION = ${AGENT_CONFIGURATION}"
  echo "           CONCORD_HOST_PORT = ${CONCORD_HOST_PORT}"
  echo "           CONCORD_API_TOKEN = ${CONCORD_API_TOKEN}"
  echo "            POSTGRES_VERSION = ${POSTGRES_VERSION}"
  echo "           POSTGRES_PASSWORD = ${POSTGRES_PASSWORD}"
  echo "               POSTGRES_PORT = ${POSTGRES_PORT}"
  echo "                 AWS_KEYPAIR = ${AWS_KEYPAIR}"
  echo "                     AWS_PEM = ${AWS_PEM}"
  echo "             AWS_CREDENTIALS = ${AWS_CREDENTIALS}"
  echo "                 AWS_PROFILE = ${AWS_PROFILE}"
  echo
}

concord_docker_initialize() {
  concord_database
  concord_server
  # We run dind because we need a docker daemon for the Concord Docker task to use. But if you are
  # doing local development you can use your local docker daemon for faster development cycles.
  if [ -z "${useHostDockerDaemon}" -o "${useHostDockerDaemon}" = "false" ]
  then
    concord_dind
  fi
  concord_agent
}

concord_database() {
  docker run -d \
  -p ${POSTGRES_PORT}:5432 \
  -e "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  --name ${CONCORD_DB_NAME} \
  --mount source=${CONCORD_DB_NAME},target=/var/lib/postgresql/data \
  library/postgres:${POSTGRES_VERSION}
}

concord_server() {

  sed \
    -e "s@EXTERNAL_URL@${EXTERNAL_URL}@" \
    -e "s@CONCORD_DB_NAME@${CONCORD_DB_NAME}@" \
    -e "s@POSTGRES_PASSWORD_B64@${POSTGRES_PASSWORD_B64}@" \
    -e "s@POSTGRES_PASSWORD@${POSTGRES_PASSWORD}@" \
    -e "s@POSTGRES_PORT@${POSTGRES_PORT}@" \
    -e "s@GITHUB_DOMAIN@${GITHUB_DOMAIN}@" \
    -e "s@GITHUB_WEBHOOK_SECRET@${GITHUB_WEBHOOK_SECRET}@" \
    $SERVER_CONFIGURATION_TEMPLATE > $SERVER_CONFIGURATION

  docker run -d \
  -p $PORT:8001 \
  --name server \
  --link ${CONCORD_DB_NAME} \
  -v ${SERVER_CONFIGURATION}:${SERVER_CONFIGURATION} \
  -e CONCORD_CFG_FILE=${SERVER_CONFIGURATION} \
  ${CONCORD_DOCKER_NAMESPACE}/concord-server:${CONCORD_VERSION}

  echo
  echo -n "Waiting for the server to start by checking http://${CONCORD_HOST_PORT}/api/v1/server/ping ..."
  until $(curl --output /dev/null --silent --head --fail "http://${CONCORD_HOST_PORT}/api/v1/server/ping"); do
      printf '.'
      sleep 1
  done
  echo "done!"
  echo

}

concord_dind() {
  if [ ! -z "${useLocalMavenRepoWithDocker}" -a "${useLocalMavenRepoWithDocker}" = "true" ]
  then
    mavenRepoForDocker="-v ${HOST_PATH}:${DIND_HOST_PATH}"
  else
    mavenRepoForDocker=""
  fi

  docker run -d \
  --privileged \
  --name dind \
  -v "/tmp:/tmp" \
  ${mavenRepoForDocker} \
  ${DIND_CONTAINER} \
  dockerd -H tcp://0.0.0.0:6666 --bip=10.11.13.1/24
}

concord_agent() {
  # https://forums.docker.com/t/connecting-via-unix-socket-to-the-docker-daemon/17396
  # https://medium.com/@mingheng/solving-permission-denied-while-trying-to-connect-to-docker-daemon-socket-from-container-in-mac-os-600c457f1276
  # ----------------------------------------------------------------------------
  # The agent itself having access to the host's ~/.m2/repository for local
  # development so that Concord plugins you are working on locally are
  # available for the agent to use directly.
  # ----------------------------------------------------------------------------
  if [ ! -z "${useLocalMavenRepoWithAgent}" -a "${useLocalMavenRepoWithAgent}" = "true" ]
  then
    localMavenRepoMount="-v ${HOME}/.m2/repository:/home/concord/.m2/repository"
  else
    localMavenRepoMount=""
  fi

  if [ ! -z "${useHostDockerDaemon}" -a "${useHostDockerDaemon}" = "true" ]
  then
    DOCKER_HOST_PATH=${HOME}/.m2/repository
    CONCORD_DOCKER_LOCAL_MODE=true
    DOCKER_HOST=tcp://127.0.0.1:2375
    SERVER_API_BASE_URL=http://localhost:${PORT}
    SERVER_WEBSOCKET_URL=ws://localhost:${PORT}/websocket
    NETWORK_OPTIONS="--net=host"
    localMavenRepoMount="-v ${HOME}/.m2/repository:/home/concord/.m2/repository"
  else
    DOCKER_HOST_PATH=${DIND_HOST_PATH}
    CONCORD_DOCKER_LOCAL_MODE=false
    DOCKER_HOST=tcp://dind:6666
    SERVER_API_BASE_URL=http://server:8001
    SERVER_WEBSOCKET_URL=ws://server:8001/websocket
    NETWORK_OPTIONS="--link server --link dind"
  fi

  if [ ! -z "${useLocalMavenRepoWithDocker}" -a "${useLocalMavenRepoWithDocker}" = "true" ]
  then
    mavenRepoForDocker="-v ${AGENT_CONFIGURATION}:/opt/concord/conf/agent.conf:ro \
                        -e CONCORD_CFG_FILE=/opt/concord/conf/agent.conf"

    sed \
      -e "s@DOCKER_HOST_PATH@${DOCKER_HOST_PATH}@" \
      -e "s@CONTAINER_PATH@${CONTAINER_PATH}@" \
      $AGENT_CONFIGURATION_TEMPLATE > $AGENT_CONFIGURATION
  else
    mavenRepoForDocker=""
  fi

  echo docker run -d \
  --name agent \
  -v "/tmp:/tmp" \
  ${localMavenRepoMount} \
  ${mavenRepoForDocker} \
  -e CONCORD_DOCKER_LOCAL_MODE=${CONCORD_DOCKER_LOCAL_MODE} \
  -e DOCKER_HOST=${DOCKER_HOST} \
  -e SERVER_API_BASE_URL=${SERVER_API_BASE_URL} \
  -e SERVER_WEBSOCKET_URL=${SERVER_WEBSOCKET_URL} \
  ${NETWORK_OPTIONS} \
  ${CONCORD_DOCKER_NAMESPACE}/concord-agent:${CONCORD_VERSION}

  docker run -d \
  --name agent \
  -v "/tmp:/tmp" \
  ${localMavenRepoMount} \
  ${mavenRepoForDocker} \
  -e CONCORD_DOCKER_LOCAL_MODE=${CONCORD_DOCKER_LOCAL_MODE} \
  -e DOCKER_HOST=${DOCKER_HOST} \
  -e SERVER_API_BASE_URL=${SERVER_API_BASE_URL} \
  -e SERVER_WEBSOCKET_URL=${SERVER_WEBSOCKET_URL} \
  ${NETWORK_OPTIONS} \
  ${CONCORD_DOCKER_NAMESPACE}/concord-agent:${CONCORD_VERSION}
}

concord_organization() {
  # $1 = organization
  echo "Creating organization '$1' ..."
  $CURL -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"name\": \"$1\" }" \
   http://${CONCORD_HOST_PORT}/api/v1/org
}

concord_team() {
  # $1 = team
  echo "Creating team '$1' in organization '$CONCORD_ORGANIZATION'..."
  $CURL -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"name\": \"$1\", \"description\": \"\" }" \
   http://${CONCORD_HOST_PORT}/api/v1/$CONCORD_ORGANIZATION/team
}

concord_add_user_to_team() {
  # $1 = team
  # $2 = user
  echo "Adding user '$2' to team '$1' in '$CONCORD_ORGANIZATION'..."
  $CURL  -X PUT -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "[ { \"username\": \"$2\", \"role\": \"OWNER\" } ]" \
   http://${CONCORD_HOST_PORT}/api/v1/org/$CONCORD_ORGANIZATION/team/$1/users
}

concord_user() {
  # $1 = user
  echo "Creating user '$1'..."
  $CURL -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"username\": \"$1\", \"type\": \"LOCAL\", \"roles\": [\"testRole1\", \"testRole2\"] }" \
   http://${CONCORD_HOST_PORT}/api/v1/user
   concord_apikey $1
}

concord_apikey() {
  # $1 = user
  mkdir -p ${CONCORD_DOTDIR}/users > /dev/null 2>&1
  echo "Creating API key for '$1'..."
  $CURL_WITH_OUTPUT -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"username\": \"$1\" }" \
   -o ${CONCORD_DOTDIR}/users/$1.json \
   http://${CONCORD_HOST_PORT}/api/v1/apikey

   apikey=`cat ${CONCORD_DOTDIR}/users/$1.json | jq -r .key`
   echo "The API key for $1 is '$apikey'" > ${CONCORD_DOTDIR}/users/$1.txt
   rm -f ${CONCORD_DOTDIR}/users/$1.json
}

concord_project() {
  # $1 = projectname
  echo "Creating project in organization $1..."
  $CURL -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"name\": \"$1\", \"acceptsRawPayload\": true, \"rawPayloadMode\" : \"EVERYONE\" }" \
   http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/project
}

concord_project_configuration() {
  # $1 = projectname
  echo "Retrieving project configuration for $1..."
  curl -s -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/project/${1}/cfg
}

concord_projects() {
  # $1 = projectname
  echo "Retrieving projects in ${CONCORD_ORGANIZATION}..."
  curl -s -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/project
}

# {
#    "name": "...",
#    "url": "...",
#    "branch": "...",
#    "commitId": "...",
#    "path": "...",
#    "secretId": "..."
#  }
concord_repository() {
  # $1 = projectname
  # $2 = repository name
  # $3 = repository url
  # $4 = repository branch
  # $$ = repository commitid (omit)
  # $$ = repository path (omit)
  # $6 = secretId
  echo "Creating repository '${2}' in project $CONCORD_ORGANIZATION..."
  secretId=$(concord_get_secret $5 | jq -r .id)
  $CURL -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   -d "{ \"name\": \"$2\", \"url\": \"$3\", \"branch\": \"$4\", \"secretId\": \"$secretId\" }" \
   http://${CONCORD_HOST_PORT}/api/v1/org/$CONCORD_ORGANIZATION/project/${1}/repository
}

# ----------------------------------------------------------------------------------------------------------------------
# Inventory
# ----------------------------------------------------------------------------------------------------------------------

concord_terraform_inventory() {
  # $1 = clusterId
  $CURL_WITH_OUTPUT -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/inventory/${1}/data/${1}?singleItem=true
}

concord_cluster_inventory() {
  # $1 = stateid
  $CURL_WITH_OUTPUT -H 'Content-Type: application/json' \
   -H "Authorization: ${CONCORD_API_TOKEN}" \
   http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/inventory/k8sClusters/data/k8sClusters/${1}?singleItem=true
}

# ----------------------------------------------------------------------------------------------------------------------
# Secrets functions
# ----------------------------------------------------------------------------------------------------------------------

concord_secret() {
  # $1 = secret id
  # $2 = secret value
  echo "Adding secret '$1' to organization '$CONCORD_ORGANIZATION'..."
  $CURL -H "Authorization: ${CONCORD_API_TOKEN}" \
  -F name=$1 \
  -F type=data \
  -F data=$2 \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret
}

concord_get_secret() {
  # $1 = secret id
  curl -L -s -H "Authorization: ${CONCORD_API_TOKEN}" \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret/${1}
}

concord_kubeconfig() {
  # $1 = secret id
  echo "Retrieving kubeconfig '$2' from organization '${CONCORD_ORGANIZATION}'..."
  curl -L -v -H "Authorization: ${CONCORD_API_TOKEN}" \
  -H 'Content-Type: multipart/form-data' \
  -F storePassword="" \
  -o ${1} \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret/${1}/data
}

concord_secret_from_file() {
  # $1 = secret id
  # $2 = secret value file
  echo "Adding secret '$1' to organization '$CONCORD_ORGANIZATION'..."
  $CURL -H "Authorization: ${CONCORD_API_TOKEN}" \
  -F name=${1} \
  -F type=data \
  -F data=@${2} \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret
}

concord_keypair() {
  # $2 = keypair id
  # $3 = public key
  # $4 = private key
  echo "Adding secret '$1' to organization '$CONCORD_ORGANIZATION'..."
  $CURL -H "Authorization: ${CONCORD_API_TOKEN}" \
  -F name=${1} \
  -F type=key_pair \
  -F public=@${2} \
  -F private=@${3} \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret
}

concord_username_password() {
  # $1 = secret id
  # $2 = username
  # $3 = password
  echo "Adding secret '${1}' to organization '$CONCORD_ORGANIZATION'..."
  $CURL -H "Authorization: ${CONCORD_API_TOKEN}" \
  -F name=${1} \
  -F type=username_password \
  -F username=${2} \
  -F password=${3} \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret
}

concord_secrets_list() {
  $CURL_WITH_OUTPUT -H "Authorization: ${CONCORD_API_TOKEN}" \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret | jq -r .[].name
}

concord_secret_delete() {
  # $1 = secret id
  echo "Deleting secret '${1}' to organization '$CONCORD_ORGANIZATION'..."
  $CURL -H "Authorization: ${CONCORD_API_TOKEN}" \
  -X DELETE \
  http://${CONCORD_HOST_PORT}/api/v1/org/${CONCORD_ORGANIZATION}/secret/${1}
}
# ----------------------------------------------------------------------------------------------------------------------
# Secrets functions for specific services like AWS, Slack, GitHub
# ----------------------------------------------------------------------------------------------------------------------

concord_aws_initialize_secrets() {

    # We have a base namespace, usually the organization, but in addition to
    # that base namespace in AWS you almost always have to have credentials
    # per account you are operating.
    AWS_NS="${NS}-"
    AWS_ACCESS_KEY_SECRET_ID="${AWS_NS}awsAccessKey";
    AWS_ACCESS_SECRET_SECRET_ID="${AWS_NS}awsSecretKey"

    if [ ! -z "$AWS_CREDENTIALS" ] && [ -f "$AWS_CREDENTIALS" ]
    then
      AWS_ACCESS_KEY_ID=`${GET_AWS_PROFILE} --key --credentials=${AWS_CREDENTIALS} --profile=$AWS_PROFILE`
      AWS_SECRET_ACCESS_KEY=`${GET_AWS_PROFILE} --secret --credentials=${AWS_CREDENTIALS} --profile=$AWS_PROFILE`
    else
      echo "The specified AWS credentials file $AWS_CREDENTIALS does not exist!"
      exit
    fi

    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]
    then
      echo "Adding AWS credentials for organization '$CONCORD_ORGANIZATION'..."
      concord_secret "${AWS_ACCESS_KEY_SECRET_ID}" $AWS_ACCESS_KEY_ID
      concord_secret "${AWS_ACCESS_SECRET_SECRET_ID}" $AWS_SECRET_ACCESS_KEY
    fi

    [ ! -f $AWS_PEM ] && AWS_PEM=${CONCORD_DOTDIR}/${AWS_PEM}
    if [ -f $AWS_PEM ]
    then
      # Set an internal name so we can clean it up later
      PUBLIC_KEY=public.openssh

      echo "Adding AWS keypair '$AWS_KEYPAIR' for organization '$CONCORD_ORGANIZATION'..."
      ssh-keygen -f $AWS_PEM -y > $PUBLIC_KEY
      concord_keypair "${AWS_NS}${AWS_ACCOUNT}-${AWS_KEYPAIR}" $PUBLIC_KEY $AWS_PEM

      echo "Adding AWS PEM file for organization '$CONCORD_ORGANIZATION'..."
      concord_secret_from_file "${AWS_NS}${AWS_ACCOUNT}-${AWS_KEYPAIR}-pem" ${AWS_PEM}

      rm -f $PUBLIC_KEY
    fi
}

# ----------------------------------------------------------------------------------------------------------------------
# A GitHub access token is used in multiple ways inside Concord
#
# - when using the git task the usage is with username/token
# - when using the github task the usage is with token
# ----------------------------------------------------------------------------------------------------------------------
concord_github_initialize_secrets() {

  GH_NS="${NS}-"
  GH_USER_SECRET_ID="${GH_NS}gitHubUser"
  GH_ACCESS_TOKEN_NAME="${GH_NS}gitHubAccessToken"
  GH_WEBHOOK_SECRET_ID="${GH_NS}gitHubWebhookSecret"

  if [ ! -z $GH_ACCESS_TOKEN ]
  then
    echo "Adding GitHub access token for organization '$CONCORD_ORGANIZATION'..."
    concord_secret "${GH_WEBHOOK_SECRET_ID}" "${GH_WEBHOOK_SECRET}"
    concord_secret "${GH_USER_SECRET_ID}" "${GH_USER}"
    concord_secret "${GH_ACCESS_TOKEN_NAME}" "${GH_ACCESS_TOKEN}"
    concord_username_password "${GH_ACCESS_TOKEN_NAME}-up" ${GH_USER} ${GH_ACCESS_TOKEN}
  fi
}

concord_docker_initialize_secrets() {

  DOCKER_NS="${NS}-"

  DOCKER_REGISTRY_SECRET_ID="${DOCKER_NS}dockerRegistry"
  DOCKER_REGISTRY_USERNAME_SECRET_ID="${DOCKER_NS}dockerRegistryUsername"
  DOCKER_REGISTRY_PASSWORD_SECRET_ID="${DOCKER_NS}dockerRegistryPassword"

  if [ ! -z $DOCKER_REGISTRY_USERNAME ]
  then
    echo "Adding Docker registry credentials tot '$CONCORD_ORGANIZATION'..."
    concord_secret "${DOCKER_REGISTRY_SECRET_ID}" "${DOCKER_REGISTRY}"
    concord_secret "${DOCKER_REGISTRY_USERNAME_SECRET_ID}" "${DOCKER_REGISTRY_USERNAME}"
    concord_secret "${DOCKER_REGISTRY_PASSWORD_SECRET_ID}" "${DOCKER_REGISTRY_PASSWORD}"
  fi
}

concord_slack_initialize_secrets() {

  SLACK_NS="${NS}-"
  SLACK_BOT_API_TOKEN_NAME="${SLACK_NS}slackBotToken"
  SLACK_USER_API_TOKEN_NAME="${SLACK_NS}slackBotUserToken"

  if [ ! -z $SLACK_BOT_API_TOKEN ]
  then
    echo "Adding Slack API token for organization '$CONCORD_ORGANIZATION'..."
    concord_secret "${SLACK_BOT_API_TOKEN_NAME}" ${SLACK_BOT_API_TOKEN}
  fi

  if [ ! -z $SLACK_USER_API_TOKEN ]
  then
    echo "Adding Slack API token for organization '$CONCORD_ORGANIZATION'..."
    concord_secret "${SLACK_USER_API_TOKEN_NAME}" ${SLACK_USER_API_TOKEN}
  fi
}

concord_secrets_initialize() {

  # PEM is needed for TF remote exec provisioner
  # KEYPAIR is needed for Ansible connections

  # Setup the Concord organization as defined in the $CONCORD_PROFILE
  concord_organization $CONCORD_ORGANIZATION
  # Initialize AWS secrets
  concord_aws_initialize_secrets
  # Initialize GH secrets
  concord_github_initialize_secrets
  # Initialize Docker secrets
  concord_docker_initialize_secrets
  # Initialize Slack secrets
  concord_slack_initialize_secrets
}

concord_server_initialize() {

  concord_secrets_initialize

  HOST_NS="$NS"

  if [ ! -z "${CONCORD_EXTERNAL_HOST}" ]
  then
    concord_secret "${HOST_NS}concord-host" ${CONCORD_EXTERNAL_HOST}
  fi
}

concord_projects_initialize() {
  for p in `(cd examples; ls -1)`
  do
    if [ -d $DIR/examples/$p ]
    then
      cp ${DIR}/concord/templates/run.sh.template ${DIR}/examples/$p/run.sh
      chmod +x ${DIR}/examples/$p/run.sh
      echo "Creating project '${p}' in organization $CONCORD_ORGANIZATION... "
      $CURL -H 'Content-Type: application/json' \
       -H "Authorization: ${CONCORD_API_TOKEN}" \
       -d "{ \"name\": \"$p\", \"acceptsRawPayload\": true }" \
       http://${CONCORD_HOST_PORT}/api/v1/org/$CONCORD_ORGANIZATION/project
    fi
  done
}
