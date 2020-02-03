#!/usr/bin/env bash

source ./concord/setup

docker rm -f agent server dind db

concord_show_variables
concord_docker_initialize
concord_server_initialize
concord_projects_initialize
