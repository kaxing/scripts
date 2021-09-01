#!/usr/bin/env bash

# Begin create reate 1 + 3 standard cluster
echo [INFO] Launching Instances

Cluster="c1"
ServerNameList="control"
for Server in $ServerNameList
do
  multipass launch --cpus 1 --mem 2G --disk 16G --name $Cluster-$Server
done

WorkerNameList="worker1 worker2 worker3"
for Worker in $WorkerNameList
do
  multipass launch --cpus 1 --mem 2G --disk 25G --name $Cluster-$Worker
done

echo [INFO] Setting up k3s
echo [INFO] Pause for 3 secs
sleep 3

# multipass default user
User="ubuntu"
ControlNode=$(multipass list --format csv|grep control|cut -d',' -f3)
ServerNodeList="$(multipass list --format csv|grep server|cut -d',' -f3|tr '\n' ' ')"
WorkerNodeList="$(multipass list --format csv|grep worker|cut -d',' -f3|tr '\n' ' ')"


echo [INFO] Setup main control node
k3sup install --user $User --ip $ControlNode --context local-c1 --cluster


echo [INFO] Joining additional etcd servers
for IP in $ServerNodeList
do
  k3sup join --user $User --ip $IP --server --server-user $User --server-ip $ControlNode
  # '--kubelet-arg=root-dir=/var/lib/longhorn-test'
done


echo [INFO] Joining worker nodes
# Install nodes
for IP in $WorkerNodeList
do
  k3sup join --user $User --server-ip $ControlNode --ip $IP
done

cat << EOF

export KUBECONFIG=`pwd`/kubeconfig

EOF
