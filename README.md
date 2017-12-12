**本例是依照[原地址](https://github.com/opsnull/follow-me-install-kubernetes-cluster)步骤，在RHEL7.2版本上的实践和整合，其中涉及到的pkg下的相关安装包，请参照[原地址](https://github.com/opsnull/follow-me-install-kubernetes-cluster)下载**

# 00 组件版本和集群环境
### 集群组件和版本
+ Red Hat Enterprise Linux Server 7.2 (Maipo)
+ linux kernel 3.10.0-327.el7.x86_64
+ kubernetes 1.6.2
+ docker 1.12.6
+ etcd 3.1.11
+ Flanneld 0.7.1 vxlan 网络
+ TLS 认证通信 (所有组件，如 etcd、kubernetes master 和 node)
+ RBAC 授权
+ kubelet TLS BootStrapping
kubedns、dashboard、heapster (influxdb、grafana)、EFK (elasticsearch、fluentd、kibana) 插件
+ 私有 docker registry，使用 ceph rgw 后端存储，TLS + HTTP Basic 认证

### 集群机器
+ k8s-master    192.168.56.4
+ k8s-node1     192.168.56.5
+ k8s-node2     192.167.56.6

### 集群环境变量
```
###################################
# global env
# set env
###################################

CURRENT_IP=192.168.56.4 # 当前部署的机器 IP
basedir=$HOME/install-k8s

# 建议用 未用的网段 来定义服务网段和 Pod 网段
# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用 IP:Port 可达
SERVICE_CIDR="10.254.0.0/16"

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达 (flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
NODE_PORT_RANGE="30000-32767"

# flanneld 网络配置前缀
FLANNEL_ETCD_PREFIX="/kubernetes/network"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
CLUSTER_DNS_DOMAIN="cluster.local."


###################################
# etcd
###################################
ETCD_VER=v3.2.10  # 版本号, 根据该版本号找下载地址
DOWNLOAD_URL=https://github.com/coreos/etcd/releases/download
NODE_NAME=etcd-host0 # 当前部署的机器名称(随便定义，只要能区分不同机器即可)
NODE_IPS="192.168.56.4 192.168.56.5 192.168.56.6" # etcd 集群所有机器 IP
## etcd 集群各机器名称和对应的IP、端口
ETCD_NODES=etcd-host0=http://192.168.56.4:2380,etcd-host1=http://192.168.56.5:2380,etcd-host2=http://192.168.56.6:2380

## etcd 集群服务地址列表
ETCD_ENDPOINTS="http://192.168.56.4:2379,http://192.168.56.5:2379,http://192.168.56.6:2379"

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
KUBE_APISERVER=https://192.168.56.4:6443 # kubelet 访问的 kube-apiserver 的地址
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

### 添加集群机器ip
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
> 此步骤在v1.0版本后去掉；不需要添加IP

### 使用脚本生成TLS 证书和秘钥
```
# cd install/shell
# ./01-mkssl.sh
```
> 该脚本会在/etc/kubernetes/ssl目录下自动生成相关的证书

### 确认证书是否完整
``` bash
# cd /etc/kubernetes
[root@k8s-master kubernetes]# find token.csv  ssl
./ssl
./ssl/admin-key.pem
./ssl/admin.pem
./ssl/ca-key.pem
./ssl/ca.pem
./ssl/kube-proxy-key.pem
./ssl/kube-proxy.pem
./token.csv
```

# 02 部署高可用etcd集群
kuberntes 系统使用 etcd 存储所有数据，本文档介绍部署一个三节点高可用 etcd 集群的步骤，这三个节点复用 kubernetes master 机器，分别命名为etcd-host0、etcd-host1、etcd-host2：

+ etcd-host0：192.168.56.4
+ etcd-host1：192.168.56.5
+ etcd-host2：192.168.56.6

### 修改使用的变量
修改当前机器上的00-setenv.sh上的相关ip与配置信息
+  CURRENT_IP
+  basedir
+  FLANNEL_ETCD_PREFIX
+  NODE_NAME
+  NODE_IPS
+  ETCD_NODES
+  ETCD_ENDPOINTS

### 确认TLS 认证文件
需要为 etcd 集群创建加密通信的 TLS 证书，这里复用以前创建的 /etc/kubernetes/ssl 证书,具体如下：
+ ca.pem 
+ kubernetes-key.pem 
+ kubernetes.pem
> kubernetes证书的hosts字段列表中包含上面三台机器的 IP，否则后续证书校验会失败；

### 安装etcd
执行安装脚本install/shell/02-etcd.sh
``` bash
# cd install/shell
# ./02-etcd.sh
```
> 该脚本会解压etcd安装包，配置文件及etcd.service,并启动etcd.service
> 在所有的etcd节点重复上面的步骤，直到所有机器etcd 服务都已启动。

### 确认集群状态
三台 etcd 的输出均为 healthy 时表示集群服务正常（忽略 warning 信息）
``` bash
# cd install/shell
[root@k8s-master shell]# ./99-etcds.sh
http://192.168.56.4:2379 is healthy: successfully committed proposal: took = 1.896744ms
http://192.168.56.5:2379 is healthy: successfully committed proposal: took = 1.881764ms
http://192.168.56.6:2379 is healthy: successfully committed proposal: took = 2.034592ms
```
### 检查 etcd集群中配置的网段信息
```
[root@k8s-master shell]# ./99-etcdctl.sh get /kubernetes/network/config
---------------------------------
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
---------------------------------
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
---------------------------------
{"Network":"172.30.0.0/16", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}
```

# 03 部署kubernetes master节点
kubernetes master 节点包含的组件：
+ kube-apiserver
+ kube-scheduler
+ kube-controller-manager
+ flanneld

> 安装flanneld组件用以dashboard，heapster访问node上的pod用

目前这三个组件需要部署在同一台机器上

### 修改环境变量
确认以下环境变量为当前机器上正确的参数
+  CURRENT_IP
+  basedir
+  FLANNEL_ETCD_PREFIX
+  ETCD_ENDPOINTS
+  KUBE_APISERVER
+  kube_pkg_dir
+  kube_tar_file

> ETCD_ENDPOINTS该参数被flanneld启动使用

### 确认TLS 证书文件
确认token.csv，ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem 存在

### 安装和配置 flanneld
+ 查看实际ip所在的网卡名字
```bash
[root@k8s-master shell]# ip a
...
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 08:00:27:9a:d3:e3 brd ff:ff:ff:ff:ff:ff
    inet 192.168.59.107/24 brd 192.168.59.255 scope global enp0s3
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fe9a:d3e3/64 scope link
       valid_lft forever preferred_lft forever
...
```
+ 设置网卡名字为：**enp0s3**
``` bash
# vi install/shell/00-setenv.sh
NET_INTERFACE_NAME=enp0s3
```
> 因flanneld启动会绑定网卡以生成虚拟ip信息，若不指定，会自动找寻除lookback外的网卡信息

+ 安装并启动flanneld
```
# cd install/shell
# ./04-flanneld.sh
```
> 该脚本会安装flanneld软件，以供dashboard，heapster可以通过web访问
> 若安装过程中报错flannel-0.7.0-1.el7.x86_64.rpm找不到，则需要手工下载rpm包至install-k8s/pkg/flanneld/flannel-0.7.0-1.el7.x86_64.rpm下；

### 部署kube-apiserver,kube-scheduler,kube-controller-manager, 执行部署脚本，部署相关master应用
``` bash
# cd install/shell
# ./03-kube-master.sh
```
> 该脚本中会安装kube master相关组件并配置kubectl config

### 验证 master 节点功能
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

### 确认环境变量
> cat install/shell/00-setenv.sh
+ CURRENT_IP
+ basedir
+ KUBE_APISERVER
+ kube_pkg_dir
+ kube_tar_file

### 确认TLS 证书文件
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
### 安装和配置 flanneld  
具体见master上安装flanneld步骤

### 安装和配置 docker
```
# cd install/shell
# ./04-docker.sh

cat << EOF > /etc/docker/daemon.json
{
  "exec-opt": ["native.cgroupdriver=systemd"]
}
EOF
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

### 安装和配置 kubelet和kube-proxy
```
# ./04-kube-node.sh
```

### 配置内网镜像源地址
将dockerhub的镜像源地址写入/etc/hosts里面，如：
``` bash
echo "192.168.59.107 docker-hub" >> /etc/hosts
```

# 05 部署kubedns 插件

### 安装
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
### 确认状态
``` bash
root@k8s-master install]# kubectl get svc,po -o wide --all-namespaces
NAMESPACE     NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE       SELECTOR
default       svc/kubernetes   10.254.0.1   <none>        443/TCP         3d        <none>
kube-system   svc/kube-dns     10.254.0.2   <none>        53/UDP,53/TCP   7m        k8s-app=kube-dns

NAMESPACE     NAME                          READY     STATUS    RESTARTS   AGE       IP            NODE
kube-system   po/kube-dns-682617846-2k9xn   3/3       Running   0          7m        172.30.59.2   192.168.59.109
```

# 06 部署 dashboard 插件
### 创建
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
### 确认状态
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

### 访问dashboard
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
### 创建
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
### 确认状态
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
### 安装
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
### 检查状态

``` bash
# kubectl cluster-info
```

### 访问
直接通过https访问会报错，可以通过http直接访问8080端口

> 在 Settings -> Indices 页面创建一个 index（相当于 mysql 中的一个database），选中 Index contains time-based events，使用默认的 logstash-* pattern，点击 Create ;

> 节点上的docker日志类型默认为journald, 若需要EFK监控，需要修改docker配置文件，并重启才可以操作生效

```bash
# vi /etc/sysconfig/docker
将如下配置
OPTIONS='--selinux-enabled --log-driver=journald --signature-verification=false'
修改为：
OPTIONS='--selinux-enabled --log-driver=json-file --signature-verification=false'
重启docker服务后，生效
```

# 09 基于prometheus对k8s进行监控
参见[jimmysong](https://jimmysong.io/kubernetes-handbook/practice/using-prometheus-to-monitor-kuberentes-cluster.html)

```bash
cd pkg/prometheus
## 创建 monitoring namespaece
kubectl create -f prometheus-monitoring-ns.yaml
## 创建 serviceaccount
kubectl create -f prometheus-monitoring-serviceaccount.yaml
## 创建 configmaps
kubectl create -f prometheus-configmaps.yaml
## 创建 clusterrolebinding
kubectl create clusterrolebinding kube-state-metrics --clusterrole=cluster-admin --serviceaccount=monitoring:kube-state-metrics
kubectl create clusterrolebinding prometheus --clusterrole=cluster-admin --serviceaccount=monitoring:prometheus
## 部署 Prometheus
kubectl create -f prometheus-monitoring.yaml
```
