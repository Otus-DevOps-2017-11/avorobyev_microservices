docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type g1-small \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
docker-host


gcloud compute firewall-rules create reddit-app \
--allow tcp:9292 --priority=65534 \
--target-tags=docker-machine \
--description="Allow TCP connections" \
--direction=INGRESS

docker pull mongo:latest
docker build -t post:1.0 ./post-py
docker build -t comment:1.0 ./comment
docker build -t ui:1.0 ./ui

docker network create reddit

#docker run -d --network reddit --network-alias post_db --network-alias comment_db mongo:latest
docker run -d --network reddit --network-alias post_db --network-alias comment_db  --mount src=reddit_db,target=/data/db mongo:latest
docker run -d --network reddit --network-alias comment comment:1.0
docker run -d --network reddit --network-alias post post:1.0
docker run -d --network reddit -p 9292:9292 ui:1.0

cat > envfile <<-!
COMMENT_SERVICE_HOST=commenter
POST_SERVICE_HOST=poster
COMMENT_DATABASE_HOST=commenter_db
POST_DATABASE_HOST=poster_db
!

docker run -d --network reddit --network-alias poster_db --network-alias commenter_db mongo:latest
docker run -d --network reddit --network-alias commenter --env-file ./envfile comment:1.0
docker run -d --network reddit --network-alias poster --env-file ./envfile post:1.0
docker run -d --network reddit -p 9292:9292 --env-file ./envfile ui:1.0


docker-machine mount docker-host:src .
fuse: mountpoint is not empty
fuse: if you are sure this is safe, use the 'nonempty' mount option
exit status 1

docker-machine ssh docker-host mkdir src
for _dir in comment post-py ui
do
  docker-machine scp -r $_dir docker-host:src
done


#create machine for gitlab
docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-disk-size 50 \
--google-tags gitlab \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
gitlab1


gcloud compute firewall-rules create gitlab-access \
--allow tcp:80,tcp:8080,tcp:443 \
--target-tags=gitlab \
--description="Allow gitlab access" \
--direction=INGRESS

export DOCKER_HOST_IP=$(docker-machine ip $DOCKER_MACHINE_NAME)



#https://docs.gitlab.com/runner/install/docker.html
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest


docker exec -it gitlab-runner gitlab-runner register


### monitoring-1 ###

#access to prometheus
gcloud compute firewall-rules create mon-access \
--allow=tcp:9090 \
--description="Allow prometheus access" \
--target-tags=prometheus \
--direction=INGRESS

#create prometheus vm
docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-tags prometheus \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
mon-vm

eval $(docker-machine env mon-vm)

#start prometheus container
docker run --rm -p 9090:9090 -d --name prometheus prom/prometheus


cat <<! > monitoring/prometheus/Dockerfile
FROM prom/prometheus
ADD prometheus.yml /etc/prometheus
!

#build srv images
for _d in ui comment post-py
do
  (
  cd src/$_d && sh docker_build.sh
  )
done

### monitoring-2 ###
gcloud compute firewall-rules create mon-access --allow tcp:9090,tcp:8080,tcp:3000,tcp:9093 --description="Allow prometheus access" --target-tags=prometheus

#push them
for _img in post comment ui prometheus alertman
do
  docker push $USER_NAME/$_img
done


### logging-1 ###

#create machine
docker-machine create --driver google \
--google-project docker-199516 \
--google-zone europe-west1-b \
--google-machine-type n1-standard-1 \
--google-tags logging \
--google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
--google-disk-size 30 \
--google-open-port 5601/tcp \
--google-open-port 9292/tcp \
--google-open-port 9411/tcp \
logging-vm


gcloud compute firewall-rules create logging-access \
  --allow tcp:5601,tcp:9292,tcp:9411 \
  --description="Allow logging demo access" \
  --target-tags=logging


#whoami
export USER_NAME=alxbird

#build images
for _d in ui comment post-py
do
  (
    cd src/$_d && sh docker_build.sh
  )
done


### swarm-1 ####

function switch_docker_host {
  local in_hostname=$1
  eval $(docker-machine env $in_hostname)
}

export GCP_PROJ=docker-199516
export USER_NAME=alxbird
export STACK_NAME=DEV
declare -a MACHINES=(master-1 worker-1 worker-2)

#create machines
for _m in ${MACHINES[@]}
do
  docker-machine create --driver google \
     --google-project $GCP_PROJ \
     --google-zone europe-west1-b \
     --google-machine-type g1-small \
     --google-machine-image $(gcloud compute images list --filter ubuntu-1604-lts --uri) \
     $_m
done

#drop machines
for _m in ${MACHINES[@]}
do
  docker-machine rm $_m
done

#touch node labes
docker node update --label-add reliability=high master-1
docker node ls -q | xargs docker node inspect   -f '{{ .ID }} [{{ .Description.Hostname }}]: {{ .Spec.Labels }}'


### kubernetes-1 ###

#controllers
for i in 0 1 2; do
  gcloud compute instances create controller-${i} \
    --async \
    --zone europe-west1-b \
    --can-ip-forward \
    --image-family ubuntu-1804-lts \
    --image-project ubuntu-os-cloud \
    --machine-type g1-small \
    --private-network-ip 10.240.0.1${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-hard-way,controller
done

#workers
for i in 0 1 2; do
  gcloud compute instances create worker-${i} \
    --async \
    --zone europe-west1-b \
    --can-ip-forward \
    --image-family ubuntu-1804-lts \
    --image-project ubuntu-os-cloud \
    --machine-type g1-small \
    --metadata pod-cidr=10.200.${i}.0/24 \
    --private-network-ip 10.240.0.2${i} \
    --scopes compute-rw,storage-ro,service-management,service-control,logging-write,monitoring \
    --subnet kubernetes \
    --tags kubernetes-the-hard-way,worker
done


# etcd cluster

for i in 0 1 2
do
  gcloud compute ssh controller-${i} <<\!

    wget -q --show-progress --https-only --timestamping \
      "https://github.com/coreos/etcd/releases/download/v3.3.5/etcd-v3.3.5-linux-amd64.tar.gz"

    tar -xvf etcd-v3.3.5-linux-amd64.tar.gz
    sudo mv etcd-v3.3.5-linux-amd64/etcd* /usr/local/bin/

    sudo mkdir -p /etc/etcd /var/lib/etcd
    sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

    INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
      http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

    ETCD_NAME=$(hostname -s)

    cat <<-EOF | sudo tee /etc/systemd/system/etcd.service
    [Unit]
    Description=etcd
    Documentation=https://github.com/coreos

    [Service]
    ExecStart=/usr/local/bin/etcd \\
      --name ${ETCD_NAME} \\
      --cert-file=/etc/etcd/kubernetes.pem \\
      --key-file=/etc/etcd/kubernetes-key.pem \\
      --peer-cert-file=/etc/etcd/kubernetes.pem \\
      --peer-key-file=/etc/etcd/kubernetes-key.pem \\
      --trusted-ca-file=/etc/etcd/ca.pem \\
      --peer-trusted-ca-file=/etc/etcd/ca.pem \\
      --peer-client-cert-auth \\
      --client-cert-auth \\
      --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
      --listen-peer-urls https://${INTERNAL_IP}:2380 \\
      --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
      --advertise-client-urls https://${INTERNAL_IP}:2379 \\
      --initial-cluster-token etcd-cluster-0 \\
      --initial-cluster controller-0=https://10.240.0.10:2380,controller-1=https://10.240.0.11:2380,controller-2=https://10.240.0.12:2380 \\
      --initial-cluster-state new \\
      --data-dir=/var/lib/etcd
    Restart=on-failure
    RestartSec=5

    [Install]
    WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable etcd
    sudo systemctl start etcd


    sudo ETCDCTL_API=3 etcdctl member list \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/etcd/ca.pem \
      --cert=/etc/etcd/kubernetes.pem \
      --key=/etc/etcd/kubernetes-key.pem
!
done

#control pane
for i in 0 1 2
do
  gcloud compute ssh controller-${i} <<\!

  sudo mkdir -p /etc/kubernetes/config

### Download and Install the Kubernetes Controller Binaries ###

  wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl"

  chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
  sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/


### Configure the Kubernetes API Server ###

  sudo mkdir -p /var/lib/kubernetes/

  sudo mv ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
    service-account-key.pem service-account.pem \
    encryption-config.yaml /var/lib/kubernetes/

  INTERNAL_IP=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)

  cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://10.240.0.10:2379,https://10.240.0.11:2379,https://10.240.0.12:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


### Configure the Kubernetes Controller Manager ###

  sudo mv kube-controller-manager.kubeconfig /var/lib/kubernetes/

  cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  ### Configure the Kubernetes Scheduler ###

  sudo mv kube-scheduler.kubeconfig /var/lib/kubernetes/

  cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF

  cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
--config=/etc/kubernetes/config/kube-scheduler.yaml \\
--v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

### Start the Controller Services ###

  sudo systemctl daemon-reload
  sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
!
done


#control pane continued
for i in 0 1 2
do
  gcloud compute ssh controller-${i} <<\!

### Enable HTTP Health Checks ###

sudo apt-get install -y nginx

cat > kubernetes.default.svc.cluster.local <<EOF
server {
  listen      80;
  server_name kubernetes.default.svc.cluster.local;

  location /healthz {
     proxy_pass                    https://127.0.0.1:6443/healthz;
     proxy_ssl_trusted_certificate /var/lib/kubernetes/ca.pem;
  }
}
EOF

{
  sudo mv kubernetes.default.svc.cluster.local \
    /etc/nginx/sites-available/kubernetes.default.svc.cluster.local

  sudo ln -s /etc/nginx/sites-available/kubernetes.default.svc.cluster.local /etc/nginx/sites-enabled/
}

sudo systemctl restart nginx

sudo systemctl enable nginx

### Verification ###

kubectl get componentstatuses --kubeconfig admin.kubeconfig

curl -H "Host: kubernetes.default.svc.cluster.local" -i http://127.0.0.1/healthz
!
done


#RBAC for Kubelet Authorization

gcloud compute ssh controller-0 <<\!
cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
!

#The Kubernetes Frontend Load Balancer
{
  KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
    --region $(gcloud config get-value compute/region) \
    --format 'value(address)')

  gcloud compute http-health-checks create kubernetes \
    --description "Kubernetes Health Check" \
    --host "kubernetes.default.svc.cluster.local" \
    --request-path "/healthz"

  gcloud compute firewall-rules create kubernetes-the-hard-way-allow-health-check \
    --network kubernetes-the-hard-way \
    --source-ranges 209.85.152.0/22,209.85.204.0/22,35.191.0.0/16 \
    --allow tcp

  gcloud compute target-pools create kubernetes-target-pool \
    --http-health-check kubernetes

  gcloud compute target-pools add-instances kubernetes-target-pool \
   --instances controller-0,controller-1,controller-2

  gcloud compute forwarding-rules create kubernetes-forwarding-rule \
    --address ${KUBERNETES_PUBLIC_ADDRESS} \
    --ports 6443 \
    --region $(gcloud config get-value compute/region) \
    --target-pool kubernetes-target-pool
}

# Provisioning a Kubernetes Worker Node
for i in 0 1 2
do
  gcloud compute ssh worker-${i} <<\!


### Install the OS dependencies:

{
  sudo apt-get update
  sudo apt-get -y install socat conntrack ipset
}


### Download and Install Worker Binaries

wget -q --show-progress --https-only --timestamping \
  https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.0/crictl-v1.0.0-beta.0-linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-the-hard-way/runsc \
  https://github.com/opencontainers/runc/releases/download/v1.0.0-rc5/runc.amd64 \
  https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz \
  https://github.com/containerd/containerd/releases/download/v1.1.0/containerd-1.1.0.linux-amd64.tar.gz \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.10.2/bin/linux/amd64/kubelet

sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

{
  chmod +x kubectl kube-proxy kubelet runc.amd64 runsc
  sudo mv runc.amd64 runc
  sudo mv kubectl kube-proxy kubelet runc runsc /usr/local/bin/
  sudo tar -xvf crictl-v1.0.0-beta.0-linux-amd64.tar.gz -C /usr/local/bin/
  sudo tar -xvf cni-plugins-amd64-v0.6.0.tgz -C /opt/cni/bin/
  sudo tar -xvf containerd-1.1.0.linux-amd64.tar.gz -C /
}


### Configure CNI Networking ###

POD_CIDR=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/pod-cidr)

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "0.3.1",
    "type": "loopback"
}
EOF

cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "0.3.1",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${POD_CIDR}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

### Configure containerd

sudo mkdir -p /etc/containerd/

cat << EOF | sudo tee /etc/containerd/config.toml
[plugins]
  [plugins.cri.containerd]
    snapshotter = "overlayfs"
    [plugins.cri.containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runc"
      runtime_root = ""
    [plugins.cri.containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/local/bin/runsc"
      runtime_root = "/run/containerd/runsc"
EOF

cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF


### Configure the Kubelet ###
{
  sudo mv ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/
  sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
  sudo mv ca.pem /var/lib/kubernetes/
}

#Create the kubelet-config.yaml configuration file:

cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.32.0.10"
podCIDR: "${POD_CIDR}"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${HOSTNAME}-key.pem"
EOF

#Create the kubelet.service systemd unit file:

cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --container-runtime=remote \\
  --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF


### Configure the Kubernetes Proxy

sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

#Create the kube-proxy-config.yaml configuration file:

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF

#Create the kube-proxy.service systemd unit file:

cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

### Start the Worker Services

{
  sudo systemctl daemon-reload
  sudo systemctl enable containerd kubelet kube-proxy
  sudo systemctl start containerd kubelet kube-proxy
}

!
done


function make_manifest {
  local in_app_name=$1
  local in_image_name=$2
  echo -n "\
---
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: ${in_app_name}-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${in_app_name}
  template:
    metadata:
      name: ${in_app_name}
      labels:
        app: ${in_app_name}
    spec:
      containers:
      - image: ${in_image_name}
        name: ${in_app_name}
"
}

declare -a APPS=(post ui mongo comment)
USER_NAME=alxbird
declare -A APP_IMAGE=(
  [post]=$USER_NAME/post
  [ui]=$USER_NAME/ui
  [comment]=$USER_NAME/comment
  [mongo]=mongo:3.2
)

for _app in ${APPS[@]}
do
  _manifest=$(make_manifest $_app ${APP_IMAGE[$_app]})
  echo "$_manifest" > ${_app}_deployment.yml
  echo "$_manifest" | kubectl apply -f -
done

admine@ubun-vm:~/MyBox/Projects/Otus/avorobyev_microservices/kubernetes$ kubectl get pods
NAME                                  READY     STATUS    RESTARTS   AGE
busybox-68654f944b-6fnmb              1/1       Running   1          1h
comment-deployment-7784766558-dwg52   1/1       Running   0          1m
mongo-deployment-778dcd865b-29vhn     1/1       Running   0          1m
nginx-65899c769f-qf86h                1/1       Running   0          1h
post-deployment-c9697fc94-hs7kf       1/1       Running   0          1m
ui-deployment-78fb684db-sktc7         1/1       Running   0          1m
untrusted                             1/1       Running   0          1h
admine@ubun-vm:~/MyBox/Projects/Otus/avorobyev_microservices/kubernetes$

#### minikube ####

minikube start

λ kubectl.exe apply -f comment_deployment.yml
Error from server (Timeout): error when retrieving current configuration of:
&{0xc04397ccc0 0xc043ef8a80 default comment-deployment comment_deployment.yml 0xc043d96658 0xc043d96658  false}
from server for: "comment_deployment.yml": the server was unable to return a response in the time allotted, but may still be processing the request (get deployments.apps comment-deployment)



### kubernetez 3 ###

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=35.201.76.254"

# star task lazy way
kubectl get secret ui-ingress -o=yaml -n dev | grep -v "creationTimestamp|uid|resourceVersion" > reddit-app\ui-ingress-secret.yml
kubectl delete -f reddit-app\ui-ingress.yml -f reddit-app\ui-ingress-secret.yml -n dev
kubectl.exe apply -f reddit-app\ui-ingress-secret.yml -f reddit-app\ui-ingress.yml -n dev
