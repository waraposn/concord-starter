#!/usr/bin/env bash

source ./concord/setup
docker rm -f agent server dind ${CONCORD_DB_NAME}
docker volume rm -f $CONCORD_DB_NAME
