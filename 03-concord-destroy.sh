#!/usr/bin/env bash

source ./concord/setup
if [ ! -z "${useMinikubeConfigs}" -a "${useMinikubeConfigs}" = "true" ]
then
    rm -rf $HOME/.kube_local
    rm -rf $HOME/.minikube_local
fi
docker rm -f agent server dind ${CONCORD_DB_NAME}
docker volume rm -f $CONCORD_DB_NAME
