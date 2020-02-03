#!/usr/bin/env bash

docker rm -f agent server dind db
docker volume rm -f db
