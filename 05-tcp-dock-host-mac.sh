#!/bin/sh

# I haven't found a better way to expose the docker daemon on the mac that works.
docker run -d --name socat -v /var/run/docker.sock:/var/run/docker.sock -p 127.0.0.1:2375:2375 bobrik/socat TCP-LISTEN:2375,fork UNIX-CONNECT:/var/run/docker.sock
