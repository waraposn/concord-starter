#!/usr/bin/env bash

source ./concord/setup

[ -f /usr/bin/pbcopy ] && echo $CONCORD_API_TOKEN | pbcopy

OPEN_CMD=open
if [ "$(uname -s)" = "Linux" ]; then
  OPEN_CMD=xdg-open
fi

$OPEN_CMD "http://${CONCORD_HOST_PORT}/#/login?useApiKey=true"
