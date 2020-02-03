#!/usr/bin/env bash

source ../../concord/setup

terraformDestroy=false
[ ! -z "$1" -a "$1" = "destroy" ] && terraformDestroy=true

concord="../../concord"
forms="../../concord/forms"

# By convention the Concord project name will be the same as the name of this
# example, which is also the name of the directory:
projectName=`basename $(PWD)`

rm -rf target && mkdir target

[ -d ${forms}    ] && cp -R ${forms}   target/
[ -f concord.yml ] && cp  concord.yml  target/

cd target && zip -x terraform/.terraform/**\* -r payload.zip ./* > /dev/null && cd ..

curl -i -H "Authorization: ${CONCORD_API_TOKEN}" \
 -F archive=@target/payload.zip \
 -F org=${CONCORD_ORGANIZATION} \
 -F project=${projectName} \
 http://${CONCORD_HOST_PORT}/api/v1/process
