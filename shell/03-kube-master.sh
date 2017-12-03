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
test ! -f $kube_tar_file && echo "$kube_tar_file not found!"
cd $kube_pkg_dir 
test ! -d $kube_pkg_dir/kubernetes/ && tar -xvf $kube_tar_file
cp $kube_pkg_dir/kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} /usr/local/bin

# create service file and config file
test ! -f $kube_pkg_dir/config/config && echo "$kube_pkg_dir/config/config not found" && exit 1
sed 's#{KUBE_APISERVER}#http://'"$CURRENT_IP"':8080#g' $kube_pkg_dir/config/config > /etc/kubernetes/config
for i in apiserver scheduler controller-manager;do
  test ! -f $kube_pkg_dir/config/kube-$i.service && echo "kube-$i.server not found" && exit 1 

  # create services & replace var
  sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;s#{NODE_PORT_RANGE}#'"$NODE_PORT_RANGE"'#g;s#{CLUSTER_CIDR}#'"$CLUSTER_CIDR"'#g;s#{ETCD_ENDPOINTS}#'"$ETCD_ENDPOINTS"'#g' $kube_pkg_dir/config/kube-$i.service > /usr/lib/systemd/system/kube-$i.service

  # create config files
  sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;s#{NODE_PORT_RANGE}#'"$NODE_PORT_RANGE"'#g;s#{CLUSTER_CIDR}#'"$CLUSTER_CIDR"'#g;s#{ETCD_ENDPOINTS}#'"$ETCD_ENDPOINTS"'#g' $kube_pkg_dir/config/$i > /etc/kubernetes/$i

  # systemctl start
  systemctl daemon-reload
  systemctl enable kube-$i
  systemctl start kube-$i
  systemctl status -l kube-$i

done

# create config file
cd $basedir/shell && ./03-kube-config.sh kubectl 
