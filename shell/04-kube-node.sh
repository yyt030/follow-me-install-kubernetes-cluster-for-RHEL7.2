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
test ! -f $kube_tar_file && echo "$kube_tar_file not found!" && exit 1
cd $kube_pkg_dir && tar -xvf $kube_tar_file
cp $kube_pkg_dir/kubernetes/server/bin/{kubectl,kube-proxy,kubelet} /usr/local/bin

# create bootstrapper role
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap

# mkdir work dir for kubelet & kube-proxy
test ! -d /var/lib/kube-proxy && mkdir -p /var/lib/kube-proxy
test ! -d /var/lib/kubelet && mkdir -p /var/lib/kubelet

# create service file and config file
test ! -f $kube_pkg_dir/config/config && echo "$kube_pkg_dir/config/config not found" && exit 1
sed 's#{KUBE_APISERVER}#'"$KUBE_APISERVER"'#g' $kube_pkg_dir/config/config > /etc/kubernetes/config

################ kubelet
test ! -f $kube_pkg_dir/config/kubelet.service && echo "kubelet.server not found" && continue

# replace var
sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{CLUSTER_DNS_SVC_IP}#'"$CLUSTER_DNS_SVC_IP"'#g;s#{CLUSTER_DNS_DOMAIN}#'"$CLUSTER_DNS_DOMAIN"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;s#{KUBE_APISERVER}#'"$KUBE_APISERVER"'#g;' $kube_pkg_dir/config/kubelet > /etc/kubernetes/kubelet
cp $kube_pkg_dir/config/kubelet.service /usr/lib/systemd/system/kubelet.service

# config
cd $basedir/shell && ./03-kube-config.sh kubelet

# systemctl start
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
systemctl status -l kubelet

############### kube-proxy
test ! -f $kube_pkg_dir/config/kube-proxy.service && echo "kube-proxy.server not found" && continue

# replace var
sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{CLUSTER_DNS_SVC_IP}#'"$CLUSTER_DNS_SVC_IP"'#g;s#{CLUSTER_DNS_DOMAIN}#'"$CLUSTER_DNS_DOMAIN"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;' $kube_pkg_dir/config/proxy > /etc/kubernetes/proxy 
cp $kube_pkg_dir/config/kube-proxy.service /usr/lib/systemd/system/kube-proxy.service

# config
cd $basedir/shell && ./03-kube-config.sh kube-proxy

# systemctl start
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status -l kube-proxy

# Approce csr
cd $basedir/shell && ./03-kube-config.sh kubectl
kubectl get csr |awk '/Pending/{print $1}' |while read csr_name;do
  kubectl certificate approve $csr_name
done
