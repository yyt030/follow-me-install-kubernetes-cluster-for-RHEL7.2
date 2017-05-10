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
  --endpoints=https://${ip}:2379  \
  --cacert=/etc/kubernetes/ssl/ca.pem \
  --cert=/etc/kubernetes/ssl/kubernetes.pem \
  --key=/etc/kubernetes/ssl/kubernetes-key.pem \
  endpoint health
done
