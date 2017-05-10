#!/bin/bash

cp $ssl_pkg_dir/config/token.csv /etc/kubernetes

cp -ri $kube_pkg_dir/kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl} /usr/local/bin
