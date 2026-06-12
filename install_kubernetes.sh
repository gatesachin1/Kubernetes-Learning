#!/bin/bash

# ============================================================
#   Kubernetes (kubeadm) Installation Script
#   OS: Amazon Linux 2023 / CentOS / RHEL / Ubuntu / Debian
#   Sets up: Master Node OR Worker Node
#   Run: sudo bash install-kubernetes.sh
# ============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()    { echo -e "${GREEN}[✔] $1${NC}"; }
warn()   { echo -e "${YELLOW}[⚠] $1${NC}"; }
error()  { echo -e "${RED}[✘] $1${NC}"; exit 1; }
header() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}  $1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Detect OS ───────────────────────────────────────────────
detect_os() {
  [ -f /etc/os-release ] && . /etc/os-release || error "Cannot detect OS"
  OS=$ID
  log "Detected OS: $OS $VERSION_ID"
}

# ── STEP 0: Prerequisites ───────────────────────────────────
header "STEP 0 — Checking Prerequisites"
[ "$EUID" -ne 0 ] && error "Run as root: sudo bash install-kubernetes.sh"
log "Running as root"
detect_os

CPU=$(nproc)
RAM=$(free -m | awk '/^Mem:/{print $2}')
log "CPU: $CPU cores | RAM: ${RAM}MB"
[ "$CPU" -lt 2 ] && warn "Kubernetes needs at least 2 CPUs"
[ "$RAM" -lt 1700 ] && warn "Kubernetes needs at least 2GB RAM"

# Ask node type
echo ""
echo -e "${YELLOW}What type of node are you setting up?${NC}"
echo "  1) Master (Control Plane)"
echo "  2) Worker Node"
read -p "Enter choice [1 or 2]: " NODE_TYPE
[ "$NODE_TYPE" != "1" ] && [ "$NODE_TYPE" != "2" ] && error "Invalid choice. Enter 1 or 2"
[ "$NODE_TYPE" == "1" ] && log "Setting up MASTER node" || log "Setting up WORKER node"

# ── STEP 1: Update System ───────────────────────────────────
header "STEP 1 — Updating System"
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  apt-get update -y
  apt-get install -y curl wget apt-transport-https ca-certificates \
    gnupg lsb-release conntrack socat ipvsadm
elif [[ "$OS" == "amzn" || "$OS" == "centos" || "$OS" == "rhel" || \
        "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
  yum update -y
  yum install -y wget conntrack socat ipvsadm tc --skip-broken
fi
log "System updated"

# ── STEP 2: Disable Swap ────────────────────────────────────
header "STEP 2 — Disabling Swap"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
log "Swap disabled"

# ── STEP 3: Load Kernel Modules ─────────────────────────────
header "STEP 3 — Loading Kernel Modules"
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
log "Kernel modules loaded"

# ── STEP 4: Kernel Settings ─────────────────────────────────
header "STEP 4 — Configuring Kernel Settings"
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null 2>&1
log "Kernel settings applied"

# ── STEP 5: Install containerd ──────────────────────────────
header "STEP 5 — Installing containerd (Container Runtime)"
if command -v containerd &>/dev/null; then
  log "containerd already installed: $(containerd --version)"
else
  if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
    # Add Docker repo for containerd
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y containerd.io
  else
    # Amazon Linux / CentOS / RHEL
    yum install -y yum-utils --skip-broken
    yum-config-manager --add-repo \
      https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
    yum install -y containerd.io --skip-broken || \
      yum install -y containerd --skip-broken
  fi
fi

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd
log "containerd configured and running"

# ── STEP 6: Install kubeadm, kubelet, kubectl ───────────────
header "STEP 6 — Installing kubeadm, kubelet, kubectl"

K8S_VERSION="1.31"

if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
    https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
    tee /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
else
  # Amazon Linux / CentOS / RHEL
  cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF
  yum install -y kubelet kubeadm kubectl \
    --disableexcludes=kubernetes --skip-broken
fi

systemctl enable kubelet
systemctl start kubelet
log "kubeadm: $(kubeadm version --output short 2>/dev/null || echo 'installed')"
log "kubelet: installed"
log "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'installed')"

# ── STEP 7: Master Node Setup ───────────────────────────────
if [ "$NODE_TYPE" == "1" ]; then
  header "STEP 7 — Initializing Master Node (Control Plane)"

  # Get private IP
  PRIVATE_IP=$(hostname -I | awk '{print $1}')
  log "Using IP: $PRIVATE_IP"

  # Initialize cluster
  kubeadm init \
    --apiserver-advertise-address=$PRIVATE_IP \
    --pod-network-cidr=192.168.0.0/16 \
    --ignore-preflight-errors=all \
    2>&1 | tee /tmp/kubeadm-init.log

  # Setup kubectl for root
  mkdir -p $HOME/.kube
  cp /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config
  export KUBECONFIG=/etc/kubernetes/admin.conf
  log "kubectl configured for root"

  # Setup for non-root user
  if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~$SUDO_USER)
    mkdir -p $USER_HOME/.kube
    cp /etc/kubernetes/admin.conf $USER_HOME/.kube/config
    chown -R $SUDO_USER:$SUDO_USER $USER_HOME/.kube
    log "kubectl configured for $SUDO_USER"
  fi

  # ── STEP 8: Install Calico CNI ────────────────────────────
  header "STEP 8 — Installing Calico CNI (Pod Networking)"
  kubectl apply -f \
    https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
  log "Calico CNI installed"

  # ── STEP 9: Allow pods on master (single node) ────────────
  header "STEP 9 — Untainting Master Node (Single Node Setup)"
  kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
  log "Master node untainted — pods can run here"

  # ── STEP 10: Verify ───────────────────────────────────────
  header "STEP 10 — Verifying Installation"
  echo ""
  echo "▶ Waiting for node to be Ready (60s)..."
  sleep 60
  kubectl get nodes -o wide
  echo ""
  kubectl get pods -n kube-system

  # Save join command
  JOIN_CMD=$(kubeadm token create --print-join-command)
  echo "$JOIN_CMD" > /root/worker-join-command.sh
  chmod +x /root/worker-join-command.sh

  # ── Done ──────────────────────────────────────────────────
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ✅  Kubernetes Master Ready!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${YELLOW}Quick Commands:${NC}"
  echo -e "  kubectl get nodes          → list nodes"
  echo -e "  kubectl get pods -A        → all pods"
  echo -e "  kubectl get all            → everything"
  echo ""
  echo -e "  ${YELLOW}To add a Worker Node:${NC}"
  echo -e "  Run this on worker EC2:"
  echo -e "  ${GREEN}$JOIN_CMD${NC}"
  echo ""
  echo -e "  ${YELLOW}Join command saved to:${NC}"
  echo -e "  /root/worker-join-command.sh"
  echo ""

# ── Worker Node Setup ────────────────────────────────────────
else
  header "STEP 7 — Worker Node Ready"
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  ✅  Worker Node Ready to Join!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  ${YELLOW}Now join this worker to master:${NC}"
  echo -e "  Copy the join command from your Master node:"
  echo -e "  ${GREEN}cat /root/worker-join-command.sh${NC}"
  echo ""
  echo -e "  It looks like:"
  echo -e "  kubeadm join <master-ip>:6443 --token xxx --discovery-token-ca-cert-hash sha256:xxx"
  echo ""
fi