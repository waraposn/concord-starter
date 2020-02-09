#!/usr/bin/env bash

source ./concord/setup

[ -f /usr/bin/pbcopy ] && echo $CONCORD_API_TOKEN | pbcopy
[ -e /dev/clipboard ] && echo $CONCORD_API_TOKEN > /dev/clipboard

echo "Concord API Key: $CONCORD_API_TOKEN"
$OPEN_CMD "http://${CONCORD_HOST_PORT}/#/login?useApiKey=true"
