#!/bin/bash

../03-concord-destroy.sh
../01-concord-initialize.sh

for p in `ls ../examples`
do
  if [ -d ../examples/$p ]
  then
    ( cd ../examples/$p ; ./run.sh )
  fi
done
