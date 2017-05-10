#!/bin/bash 

ENVFILE=./00-setenv.sh

# env
if [ -f $ENVFILE ];then
  . $ENVFILE
else
  echo "$ENVFILE not found!"
  exit 
fi

# deploy
test ! -f $flanneld_rpm_file && echo "$flanneld_rpm_file not found!" && exit 1
yum install -y $flanneld_rpm_file
sed 's#{ETCD_ENDPOINTS}#'"$ETCD_ENDPOINTS"'#g;s#{FLANNEL_ETCD_PREFIX}#'"$FLANNEL_ETCD_PREFIX"'#g;s#{NET_INTERFACE_NAME}#'"$NET_INTERFACE_NAME"'#g' $flanneld_pkg_dir/flanneld > /etc/sysconfig/flanneld

# reset 
systemctl daemon-reload
systemctl enable flanneld
systemctl restart flanneld
systemctl status -l flanneld
