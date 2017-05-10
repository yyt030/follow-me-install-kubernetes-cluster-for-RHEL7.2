###################################
# global env
# set env
###################################

CURRENT_IP=192.168.59.109 # 当前部署的机器 IP
basedir=$HOME/install

# 建议用 未用的网段 来定义服务网段和 Pod 网段
# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用 IP:Port 可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达 (flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
NODE_PORT_RANGE="8400-9000"

# flanneld 网络配置前缀
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."


###################################
# etcd
###################################
NODE_NAME=etcd-host2 # 当前部署的机器名称(随便定义，只要能区分不同机器即可)
NODE_IPS="192.168.59.107 192.168.59.108 192.168.59.109" # etcd 集群所有机器 IP
## etcd 集群各机器名称和对应的IP、端口
ETCD_NODES=etcd-host0=https://192.168.59.107:2380,etcd-host1=https://192.168.59.108:2380,etcd-host2=https://192.168.59.109:2380

## etcd 集群服务地址列表
ETCD_ENDPOINTS="https://192.168.59.107:2379,https://192.168.59.108:2379,https://192.168.59.109:2379"

etcd_pkg_dir=$basedir/pkg/etcd


###################################
# ssl
###################################
ssl_workdir=$basedir/work/ssl
ssl_pkg_dir=$basedir/pkg/cfssl
ssl_bin_dir=$ssl_pkg_dir/bin
ssl_config_dir=$ssl_pkg_dir/config


###################################
# kubernetes
###################################
KUBE_APISERVER=https://192.168.59.107:6443 # kubelet 访问的 kube-apiserver 的地址
kube_pkg_dir=$basedir/pkg/kubernetes
kube_tar_file=$kube_pkg_dir/kubernetes-server-linux-amd64.tar.gz


###################################
# flanneld
###################################
flanneld_pkg_dir=$basedir/pkg/flanneld
flanneld_rpm_file=$flanneld_pkg_dir/flannel-0.7.0-1.el7.x86_64.rpm
NET_INTERFACE_NAME=enp0s3

###################################
# docker
###################################
docker_pkg_dir=$basedir/pkg/docker

