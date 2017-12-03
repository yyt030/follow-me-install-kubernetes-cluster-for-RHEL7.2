#!/bin/bash

ENVFILE=./00-setenv.sh

# env
if [ -f $ENVFILE ];then
  . $ENVFILE
else
  echo "$ENVFILE not found!"
  exit
fi

export ETCDCTL_API=3 

for ip in ${NODE_IPS}; do
  etcdctl \
  --endpoints=http://${ip}:2379  \
  endpoint health
done
