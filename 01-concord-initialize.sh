#!/usr/bin/env bash

source ./concord/setup

concord_show_variables
concord_docker_initialize
concord_server_initialize
concord_projects_initialize

( cd concord ; ./test.sh )
