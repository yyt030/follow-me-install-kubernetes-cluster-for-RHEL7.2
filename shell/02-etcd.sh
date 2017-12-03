#!/bin/bash

ENVFILE=./00-setenv.sh

# env
if [ -f $ENVFILE ];then
  . $ENVFILE
else
  echo "$ENVFILE not found!"
  exit
fi

test ! -d /var/lib/etcd && mkdir -p /var/lib/etcd
test ! -d /etc/etcd && mkdir -p /etc/etcd

### download 
if [ ! -f $etcd_pkg_dir/etcd-${ETCD_VER}-linux-amd64.tar.gz ];then
    curl -C - -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o $etcd_pkg_dir/etcd-${ETCD_VER}-linux-amd64.tar.gz
fi 

cd $etcd_pkg_dir
tar -xf $etcd_pkg_dir/etcd-${ETCD_VER}-linux-amd64.tar.gz
cp -i $etcd_pkg_dir/etcd-${ETCD_VER}-linux-amd64/etcd* /usr/local/bin
cat $etcd_pkg_dir/etcd.conf |sed 's#{NODE_NAME}#'"$NODE_NAME"'#g;s#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{ETCD_NODES}#'"$ETCD_NODES"'#g' > /etc/etcd/etcd.conf
cp -i $etcd_pkg_dir/etcd.service /usr/lib/systemd/system/etcd.service

# disable firewalld & start etcd
systemctl daemon-reload
systemctl disable firewalld
systemctl stop firewalld
systemctl enable etcd
systemctl restart etcd

# write kubernete pod ip range
### 向 etcd 写入集群 Pod 网段信息
etcdctl \
  --endpoints=${ETCD_ENDPOINTS} \
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
