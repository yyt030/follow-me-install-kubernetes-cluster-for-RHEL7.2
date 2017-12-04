#!/bin/bash
# author: yantao

ENVFILE=./00-setenv.sh

# env
if [ -f $ENVFILE ];then
    . $ENVFILE
else
    echo "$ENVFILE not found!"
    exit
fi

current_timestamp=`date +%Y%m%d%H%M%S`

if test -d $ssl_workdir;then
    mv $ssl_workdir $ssl_workdir.$current_timestamp
fi
mkdir -p $ssl_workdir && cd $ssl_workdir || (echo "$ssl_workdir not exist";exit 1)
export PATH=$PATH:$ssl_bin_dir

# check bin file exist
for i in cfssl cfssljson cfssl-certinfo;do
    mkdir -p $ssl_bin_dir
    if test ! -f $ssl_bin_dir/$i ;then
        echo "starting download $i ..."
        curl https://pkg.cfssl.org/R1.2/${i}_linux-amd64 -o $ssl_bin_dir/$i
        if [ $? -eq 0 ];then
            chmod +x $ssl_bin_dir/$i
        fi
    fi
    test ! -f $ssl_bin_dir/$i && echo "file $ssl_bin_dir/$i not found!" && exit 1
done

# check config file exist
for i in ca-config.json admin-csr.json kube-proxy-csr.json;do
    test ! -f $ssl_config_dir/$i && echo "file $ssl_config_dir/$i not found!" && exit 1
done

#cfssl print-defaults config > config.json
#cfssl print-defaults csr > csr.json

# create
## create ca
cfssl gencert -initca $ssl_config_dir/ca-csr.json | cfssljson -bare ca

## create kubernetes
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=$ssl_config_dir/ca-config.json -profile=kubernetes $ssl_config_dir/kubernetes-csr.json | cfssljson -bare kubernetes

## create admin
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=$ssl_config_dir/ca-config.json -profile=kubernetes $ssl_config_dir/admin-csr.json | cfssljson -bare admin

## create kube-proxy
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=$ssl_config_dir/ca-config.json -profile=kubernetes $ssl_config_dir/kube-proxy-csr.json | cfssljson -bare kube-proxy

# deploy ssl key files
echo "----------------"
echo -n "Do you Deploy SSL KEY FILE to /etc/kubernetes/ssl???[Y/enter N] "
read flag
if [ "X$flag" == "XY" ];then
    test ! -d /etc/kubernetes/ssl && mkdir -p /etc/kubernetes/ssl
    cp $ssl_workdir/*.pem /etc/kubernetes/ssl
fi

# copy token csv
cp $ssl_config_dir/token.csv /etc/kubernetes/
