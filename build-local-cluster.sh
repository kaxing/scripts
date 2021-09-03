#!/usr/bin/env bash
set -e

test -f $HOME/.ssh/id_rsa.pub || ( echo "We are going to use your default id_rsa.pub, and you have it, please generate one." && exit 1 )

for package in multipass cut grep tr rg k3sup
do
  command -v $package || exit_status="true"
  [[ "$exit_status" = "true" ]] && echo "Please install $package"
done
[[ "$exit_status" = "true" ]] && echo "Please fix dependency before continue." && exit 1 || echo "Dependencies met, continue..."

cloud-init.yaml() {
cat <<-BLOCK
#cloud-config
users:
- default
- name: ubuntu
  ssh_authorized_keys: 
  - $(cat $HOME/.ssh/id_rsa.pub)
BLOCK
}


# Begin create 1 + 3 standard cluster
echo [INFO] Launching Instances

Cluster="c1"
ServerNameList="control"
for Server in $ServerNameList
do
  cat <(cloud-init.yaml) | \
    multipass launch --cpus 2 --mem 4096M --disk 16G --name $Cluster-$Server --cloud-init -
done

WorkerNameList="worker1 worker2 worker3"
for Worker in $WorkerNameList
do
  cat <(cloud-init.yaml) | \
    multipass launch --cpus 1 --mem 3072M --disk 25G --name $Cluster-$Worker --cloud-init -
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
