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
cp $kube_pkg_dir/kubernetes/server/bin/{kubectl,kube-proxy,kubelet} /usr/local/bin

# create bootstrapper role
kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap

# mkdir work dir for kubelet & kube-proxy
test ! -d /var/lib/kube-proxy && mkdir -p /var/lib/kube-proxy
test ! -d /var/lib/kubelet && mkdir -p /var/lib/kubelet

# create service file
for i in kubelet kube-proxy;do
  test ! -f $kube_pkg_dir/config/$i.service && echo "$i.server not found" && continue

  # replace var
  sed 's#{CURRENT_IP}#'"$CURRENT_IP"'#g;s#{CLUSTER_DNS_SVC_IP}#'"$CLUSTER_DNS_SVC_IP"'#g;s#{CLUSTER_DNS_DOMAIN}#'"$CLUSTER_DNS_DOMAIN"'#g;s#{SERVICE_CIDR}#'"$SERVICE_CIDR"'#g;' $kube_pkg_dir/config/$i.service > /usr/lib/systemd/system/$i.service
  
  # config
  cd $basedir/shell && ./03-kube-config.sh $i

  # systemctl start
  systemctl daemon-reload
  systemctl enable $i
  systemctl start $i
  systemctl status -l $i
done

# Approce csr
cd $basedir/shell && ./03-kube-config.sh kubectl
kubectl get csr |awk '/Pending/{print $1}' |while read csr_name;do
  kubectl certificate approve $csr_name
done
