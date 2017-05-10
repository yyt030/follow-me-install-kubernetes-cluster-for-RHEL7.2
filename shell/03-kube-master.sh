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
cd $kube_pkg_dir && tar -xvf $kube_tar_file
cp $kube_pkg_dir/kubernetes/server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet} /usr/local/bin

# create service file
for i in kube-apiserver kube-scheduler kube-controller-manager;do
  test ! -f $kube_pkg_dir/config/$i.service && echo "$i.server not found" && exit 1 

  # replace var
  sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;s#{NODE_PORT_RANGE}#'"$NODE_PORT_RANGE"'#g;s#{CLUSTER_CIDR}#'"$CLUSTER_CIDR"'#g;s#{ETCD_ENDPOINTS}#'"$ETCD_ENDPOINTS"'#g' $kube_pkg_dir/config/$i.service > /usr/lib/systemd/system/$i.service

  # systemctl start
  systemctl daemon-reload
  systemctl enable $i
  systemctl start $i
  systemctl status -l $i

done

# create config file
cd $basedir/shell && ./03-kube-config.sh kubectl 
