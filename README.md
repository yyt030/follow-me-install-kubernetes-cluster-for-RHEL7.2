**本例是依照https://github.com/opsnull/follow-me-install-kubernetes-cluster步骤，在RHEL7.2版本上的实践和整合，其中涉及到的pkg下的相关安装包，请参照原地址下载** 

# 00 组件版本和集群环境
## 集群组件和版本
+ Red Hat Enterprise Linux Server 7.2 (Maipo)
+ linux kernel 3.10.0-327.el7.x86_64
+ kubernetes 1.6.2
+ docker 1.12.6
+ etcd 1.12.6
+ Flanneld 0.7.1 vxlan 网络
+ TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
+ RBAC 授权
+ kubelet TLS BootStrapping
kubedns、dashboard、heapster (influxdb、grafana)、EFK (elasticsearch、fluentd、kibana) 插件
+ 私有 docker registry，使用 ceph rgw 后端存储，TLS + HTTP Basic 认证

## 集群机器
+ 192.168.59.107
+ 192.168.59.108
+ 192.168.59.109

## 集群环境变量
```
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
```

> 该脚本内容见install/shell/00-setenv.sh

# 01 创建 TLS 证书和秘钥
kubernetes 系统各组件需要使用 TLS 证书对通信进行加密，本文档使用 CloudFlare 的 PKI 工具集 cfssl 来生成 Certificate Authority (CA) 和其它证书。

生成的 CA 证书和秘钥文件如下：
+ ca-key.pem
+ ca.pem
+ kubernetes-key.pem
+ kubernetes.pem
+ kube-proxy.pem
+ kube-proxy-key.pem
+ admin.pem
+ admin-key.pem

使用证书的组件如下：
+ etcd：使用 ca.pem、kubernetes-key.pem、kubernetes.pem；
+ kube-apiserver：使用 ca.pem、kubernetes-key.pem、kubernetes.pem；
+ kubelet：使用 ca.pem；
+ kube-proxy：使用 ca.pem、kube-proxy-key.pem、kube-proxy.pem；
+ kubectl：使用 ca.pem、admin-key.pem、admin.pem；
+ kube-controller、kube-scheduler 当前需要和 kube-apiserver部署在同一台机器上且使用非安全端口通信，故不需要证书。

> kubernetes 1.4 开始支持 TLS Bootstrapping 功能，由 kube-apiserver 为客户端生成 TLS 证书，这样就不需要为每个客户端生成证书（该功能目前仅支持 kubelet，所以本文档没有为 kubelet 生成证书和秘钥）。

## 添加集群机器ip
``` bash
# cat install/pkg/cfssl/config/kubernetes-csr.json
{
  "CN": "kubernetes",
  "hosts": [
    ...
    "192.168.59.107",
    "192.168.59.108",
    "192.168.59.109",
    ...
  ],
  ...
}

```
## 使用脚本生成TLS 证书和秘钥
```
# cd install/shell
# ./01-mkssl.sh
```
> 该脚本会在/etc/kubernetes/ssl目录下自动生成相关的证书

## 确认证书是否完整
``` bash
# cd /etc/kubernetes
[root@k8s-master kubernetes]# find token.csv  ssl
token.csv
ssl
ssl/admin-key.pem
ssl/admin.pem
ssl/ca-key.pem
ssl/ca.pem
ssl/kube-proxy-key.pem
ssl/kube-proxy.pem
ssl/kubernetes-key.pem
ssl/kubernetes.pem
```

## 分发证书
将生成的证书和秘钥文件（后缀名为.pem）拷贝到所有机器的 /etc/kubernetes/ssl 目录下

> 当前机器已在/etc/kubernetes/ssl生成了证书，只需要将该目录copy至其他机器上

> 确保/etc/kubernetes/token.csv 也一并分发

# 02 部署高可用etcd集群
kuberntes 系统使用 etcd 存储所有数据，本文档介绍部署一个三节点高可用 etcd 集群的步骤，这三个节点复用 kubernetes master 机器，分别命名为etcd-host0、etcd-host1、etcd-host2：

+ etcd-host0：192.168.59.107
+ etcd-host1：192.168.59.108
+ etcd-host2：192.168.59.109

## 修改使用的变量
修改当前机器上的00-setenv.sh上的相关ip与配置信息
+  CURRENT_IP
+  basedir
+  FLANNEL_ETCD_PREFIX
+  NODE_NAME
+  NODE_IPS
+  ETCD_NODES
+  ETCD_ENDPOINTS

## 确认TLS 认证文件
需要为 etcd 集群创建加密通信的 TLS 证书，这里复用以前创建的 /etc/kubernetes/ssl 证书,具体如下：
+ ca.pem 
+ kubernetes-key.pem 
+ kubernetes.pem
> kubernetes证书的hosts字段列表中包含上面三台机器的 IP，否则后续证书校验会失败；

## 安装etcd
执行安装脚本install/shell/02-etcd.sh
``` bash
# cd install/shell
# ./02-etcd.sh
```
> 该脚本会解压etcd安装包，配置文件及etcd.service,并启动etcd.service
> 在所有的etcd节点重复上面的步骤，直到所有机器etcd 服务都已启动。

## 确认集群状态
三台 etcd 的输出均为 healthy 时表示集群服务正常（忽略 warning 信息）
``` bash
# cd install/shell
# ./99-etcd-status.sh
2017-05-06 07:08:40.814488 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://192.168.31.180:2379 is healthy: successfully committed proposal: took = 8.442607ms
2017-05-06 07:08:40.989278 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://192.168.31.181:2379 is healthy: successfully committed proposal: took = 10.628781ms
2017-05-06 07:08:41.153308 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
https://192.168.31.182:2379 is healthy: successfully committed proposal: took = 9.988602ms
```

# 03 部署kubernetes master节点
kubernetes master 节点包含的组件：
+ kube-apiserver
+ kube-scheduler
+ kube-controller-manager
目前这三个组件需要部署在同一台机器上

## 修改环境变量
确认以下环境变量为当前机器上正确的参数
+  CURRENT_IP
+  basedir
+  FLANNEL_ETCD_PREFIX
+  KUBE_APISERVER
+  kube_pkg_dir
+  kube_tar_file

## 确认TLS 证书文件
确认token.csv，ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem 存在
``` bash
# find /etc/kubernetes/
/etc/kubernetes/
/etc/kubernetes/ssl
/etc/kubernetes/ssl/admin-key.pem
/etc/kubernetes/ssl/admin.pem
/etc/kubernetes/ssl/ca-key.pem
/etc/kubernetes/ssl/ca.pem
/etc/kubernetes/ssl/kube-proxy-key.pem
/etc/kubernetes/ssl/kube-proxy.pem
/etc/kubernetes/ssl/kubernetes-key.pem
/etc/kubernetes/ssl/kubernetes.pem
/etc/kubernetes/token.csv
```
## 部署kube-apiserver,kube-scheduler,kube-controller-manager
执行部署脚本，部署相关master应用
``` bash
# cd install/shell
# ./03-kube-master.sh
```
> 该脚本中会安装kube master相关组件并配置kubectl config

> 该脚本会安装flanneld软件，以供dashboard，heapster可以通过web访问

## 验证 master 节点功能
``` bash
[root@k8s-master shell]# kubectl get componentstatuses
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok                   
scheduler            Healthy   ok                   
etcd-0               Healthy   {"health": "true"}   
etcd-1               Healthy   {"health": "true"}   
etcd-2               Healthy   {"health": "true"} 
```

# 04 部署kubernetes node节点
kubernetes Node 节点包含如下组件：
+ flanneld
+ docker
+ kubelet
+ kube-proxy

## 确认环境变量
> cat install/shell/00-setenv.sh
+ CURRENT_IP
+ basedir
+ KUBE_APISERVER
+ kube_pkg_dir
+ kube_tar_file

## 确认TLS 证书文件
确认token.csv，ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem 存在
```
# find /etc/kubernetes/
/etc/kubernetes/
/etc/kubernetes/ssl
/etc/kubernetes/ssl/admin-key.pem
/etc/kubernetes/ssl/admin.pem
/etc/kubernetes/ssl/ca-key.pem
/etc/kubernetes/ssl/ca.pem
/etc/kubernetes/ssl/kube-proxy-key.pem
/etc/kubernetes/ssl/kube-proxy.pem
/etc/kubernetes/ssl/kubernetes-key.pem
/etc/kubernetes/ssl/kubernetes.pem
/etc/kubernetes/token.csv
```
## 安装和配置 flanneld
### 检查 etcd 集群 Pod 网段信息
```
[root@k8s-node2 shell]# ./99-etcdctl.sh get /kubernetes/network/config
---------------------------------
2017-05-08 11:35:19.541620 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
---------------------------------
2017-05-08 11:35:19.573973 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
---------------------------------
2017-05-08 11:35:19.612551 I | warning: ignoring ServerName for user-provided CA for backwards compatibility is deprecated
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
```
### 检查flanneld指定的网卡信息
```
# vi install/shell/00-setenv.sh
NET_INTERFACE_NAME=enp0s3
```
### 安装并启动flanneld
```
# cd install/shell
# ./04-flanneld.sh
```

## 安装和配置 docker
```
# cd install/shell
# ./04-docker.sh

```
> 若安装失败，请检查os版本安装时，是否是最小化安装，或者根据报错依赖信息，直接删除掉systemd-python-219-19.el7.x86_64和libcgroup-tools-0.41-8.el7.x86_64

```
# yum remove -y systemd-python-219-19.el7.x86_64 libcgroup-tools-0.41-8.el7.x86_64
```
> 该脚本会自动关闭并配置selinux为被动模式并停止防火墙;
> + 设置selinux为被动模式，是避免docker创建文件系统报权限失败；
> + 设置firewalld是为了防止添加的iptables信息与docker自身的冲突，造成访问失败；

```
# 可以通过如下命令查看下相关信息
# sestatus
# systemctl status -l firewalld
```

## 安装和配置 kubelet和kube-proxy
```
# ./04-k8s-node.sh
```

# 05 部署kubedns 插件
## 安装
``` bash
# cd install
[root@k8s-master install]# ls -lrt pkg/kubedns
总用量 20
-rw-r--r--. 1 root root 1024 5月   8 09:14 kubedns-svc.yaml
-rw-r--r--. 1 root root 5309 5月   8 09:14 kubedns-controller.yaml
-rw-r--r--. 1 root root  187 5月   8 09:14 kubedns-sa.yaml
-rw-r--r--. 1 root root  731 5月   8 09:14 kubedns-cm.yaml
[root@k8s-master install]# kubectl create -f pkg/kubedns/
configmap "kube-dns" created
deployment "kube-dns" created
serviceaccount "kube-dns" created
service "kube-dns" created
```

> 确保yaml配置的image源地址正确

> 若节点pull image时如下报错，配置/etc/sysconfig/docker，INSECURE_REGISTRY='--insecure-registry docker-hub:5000'

``` bash
level=error msg="Handler for GET /v1.24/images/docker-hub:5000/pause-amd64:3.0/json returned error: No such image: docker-hub:5000/pause-amd64:3.0"
```
## 确认状态
``` bash
root@k8s-master install]# kubectl get svc,po -o wide --all-namespaces
NAMESPACE     NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE       SELECTOR
default       svc/kubernetes   10.254.0.1   <none>        443/TCP         3d        <none>
kube-system   svc/kube-dns     10.254.0.2   <none>        53/UDP,53/TCP   7m        k8s-app=kube-dns

NAMESPACE     NAME                          READY     STATUS    RESTARTS   AGE       IP            NODE
kube-system   po/kube-dns-682617846-2k9xn   3/3       Running   0          7m        172.30.59.2   192.168.59.109
```

# 06 部署 dashboard 插件
## 创建
``` bash
[root@k8s-master install]# ls -lrt pkg/dashboard/
总用量 12
-rw-r--r--. 1 root root  339 5月   8 09:13 dashboard-service.yaml
-rw-r--r--. 1 root root  365 5月   8 09:13 dashboard-rbac.yaml
-rw-r--r--. 1 root root 1132 5月   8 09:13 dashboard-controller.yaml
[root@k8s-master install]# kubectl create -f pkg/dashboard/
deployment "kubernetes-dashboard" created
serviceaccount "dashboard" created
clusterrolebinding "dashboard" created
service "kubernetes-dashboard" created
```
## 确认状态
``` bash
root@k8s-master install]# kubectl get svc,po -o wide --all-namespaces
NAMESPACE     NAME                       CLUSTER-IP     EXTERNAL-IP   PORT(S)         AGE       SELECTOR
default       svc/kubernetes             10.254.0.1     <none>        443/TCP         3d        <none>
kube-system   svc/kube-dns               10.254.0.2     <none>        53/UDP,53/TCP   12m       k8s-app=kube-dns
kube-system   svc/kubernetes-dashboard   10.254.41.68   <nodes>       80:8522/TCP     19s       k8s-app=kubernetes-dashboard

NAMESPACE     NAME                                       READY     STATUS    RESTARTS   AGE       IP            NODE
kube-system   po/kube-dns-682617846-2k9xn                3/3       Running   0          12m       172.30.59.2   192.168.59.109
kube-system   po/kubernetes-dashboard-2172513996-thb5q   1/1       Running   0          18s       172.30.57.2   192.168.59.108
```
查看分配的 NodePort
+ 通过之前的命令，可以看到svc/kubernetes-dashboard NodePort 8522映射到 dashboard pod 80端口；

## 访问dashboard
+ kubernetes-dashboard 服务暴露了 NodePort，可以使用 http://NodeIP:nodePort 地址访问 dashboard；
``` bash
[root@k8s-master shell]# kubectl get po,svc -o wide --all-namespaces |grep dashboard

kube-system   po/kubernetes-dashboard-2172513996-thb5q   1/1       Running   1          21h       172.30.77.3   192.168.59.108
kube-system   svc/kubernetes-dashboard   10.254.41.68     <nodes>       80:8522/TCP                   21h       k8s-app=kubernetes-dashboard
```
> 直接访问： http://192.168.59.108:8522 
+ 通过 kube-apiserver 访问 dashboard；

``` bash
[root@k8s-master shell]# kubectl cluster-info
Kubernetes master is running at https://192.168.59.107:6443
Heapster is running at https://192.168.59.107:6443/api/v1/proxy/namespaces/kube-system/services/heapster
KubeDNS is running at https://192.168.59.107:6443/api/v1/proxy/namespaces/kube-system/services/kube-dns
kubernetes-dashboard is running at https://192.168.59.107:6443/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard
monitoring-grafana is running at https://192.168.59.107:6443/api/v1/proxy/namespaces/kube-system/services/monitoring-grafana
monitoring-influxdb is running at https://192.168.59.107:6443/api/v1/proxy/namespaces/kube-system/services/monitoring-influxdb
```
> 直接通过https访问会报错，可以通过http api的8080端口访问
+ 通过 kubectl proxy 访问 dashboard：

``` bash
# kubectl proxy --address=0.0.0.0 --accept-hosts='^*$'
# 通过http://ip:8001/ui/访问
```

# 07 部署 Heapster插件
## 创建
``` bash
[root@k8s-master install]# kubectl create -f pkg/heapster/
deployment "monitoring-grafana" created
service "monitoring-grafana" created
deployment "heapster" created
serviceaccount "heapster" created
clusterrolebinding "heapster" created
service "heapster" created
configmap "influxdb-config" created
deployment "monitoring-influxdb" created
service "monitoring-influxdb" created
```
## 确认状态
``` bash
[root@k8s-master install]# kubectl get svc,po -o wide --all-namespaces
kube-system   svc/heapster               10.254.244.190   <none>        80/TCP                        28s       k8s-app=heapster
kube-system   svc/monitoring-grafana     10.254.72.242    <none>        80/TCP                        28s       k8s-app=grafana
kube-system   svc/monitoring-influxdb    10.254.129.64    <nodes>       8086:8815/TCP,8083:8471/TCP   27s       k8s-app=influxdb

NAMESPACE     NAME                                       READY     STATUS    RESTARTS   AGE       IP            NODE
kube-system   po/heapster-1982147024-17ltr               1/1       Running   0          27s       172.30.59.4   192.168.59.109
kube-system   po/monitoring-grafana-1505740515-46r2h     1/1       Running   0          28s       172.30.57.3   192.168.59.108
kube-system   po/monitoring-influxdb-14932621-ztgh4      1/1       Running   0          27s       172.30.59.3   192.168.59.109
```
# 08 部署 EFK 插件
## 安装
``` bash
cd install/pkg/EFK
kubectl create -f .
```
> 确保yaml里面配置的image可用
## 给 Node 设置标签
DaemonSet fluentd-es-v1.22 只会调度到设置了标签 beta.kubernetes.io/fluentd-ds-ready=true 的 Node，需要在期望运行 fluentd 的 Node 上设置该标签；

``` bash
kubectl label nodes 192.168.59.109 beta.kubernetes.io/fluentd-ds-ready=true
```
## 检查状态

``` bash
# kubectl cluster-info
```

## 访问
直接通过https访问会报错，可以通过http直接访问8080端口
