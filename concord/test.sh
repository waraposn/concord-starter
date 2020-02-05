#!/bin/bash

source ./setup

echo
echo "Submitting verification process..."

# Submit process
RESULT=`curl --silent -H "Authorization: ${CONCORD_API_TOKEN}" -F concord.yml=@test.yaml http://${CONCORD_HOST_PORT}/api/v1/process`
#echo ${RESULT}
ID=`echo ${RESULT} | jq -r .instanceId | tr -d '"\r\n'`
echo ${ID}

echo "Waiting for the Concord process to finish"
while [ "$(curl --silent -H "Authorization: ${CONCORD_API_TOKEN}" http://${CONCORD_HOST_PORT}/api/v1/process/${ID} | jq -r .status | tr -d '"\r\n')" != "FINISHED" ]
do
  printf '.'
  sleep 2
done

echo

#echo ${RESULT}
#STATUS=`echo ${RESULT} | jq -r .status`
#echo ${STATUS}

# Something like the following will be emitted:
#
# {
#   "instanceId" : "2a0c5238-1102-4eaa-857a-80c252cb91fc",
#   "kind" : "DEFAULT",
#   "createdAt" : "2019-03-06T13:59:22.186Z",
#   "initiator" : "admin",
#   "initiatorId" : "230c5c9c-d9a7-11e6-bcfd-bb681c07b26c",
#   "status" : "FINISHED",
#   "lastAgentId" : "ab3632f9-42d0-4b13-a210-1fdbaaeb22a4",
#   "lastUpdatedAt" : "2019-03-06T13:59:39.375Z",
#   "logFileName" : "2a0c5238-1102-4eaa-857a-80c252cb91fc.log",
#   "meta" : {
#     "_system" : {
#       "requestId" : "35e1cee9-a8b6-4668-94ff-247c11f218d6"
#     }
#   }
# }

echo
# Inspect logs from executed process
RESULT=`curl --silent -H "Authorization: ${CONCORD_API_TOKEN}" http://${CONCORD_HOST_PORT}/api/v1/process/${ID}/log`
#echo ${LOG}
if echo ${RESULT} | grep -q 'COMPLETED'; then
    echo "-----------------------------------------------------------------------------------------------------------------"
    echo "SUCCESS!"
    echo
    echo "You have a fully functional Concord installation!"
    echo
    echo "You can see the log for this test job here (remember to log in first):"
    echo "http://${CONCORD_HOST_PORT}/#/process/${ID}/log"
    echo
    echo "We highly encourage you to read the Concord documentation which you can find here:"
    echo "https://concord.walmartlabs.com/docs/index.html"
    echo "-----------------------------------------------------------------------------------------------------------------"
    echo
else
    echo "-----------------------------------------------------------------------------------------------------------------"
    echo "FAILED :("
    echo
    echo "You can see the log for this test job here (remember to log in first):"
    echo "http://${CONCORD_HOST_PORT}/#/process/${ID}/log"
    echo "-----------------------------------------------------------------------------------------------------------------"
    echo
fi
