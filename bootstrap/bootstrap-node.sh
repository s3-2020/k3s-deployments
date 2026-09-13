#!/usr/bin/env bash
#
# bootstrap-node.sh — recreate this cluster's node config on a fresh Ubuntu.
#
#   node1 (cluster-init):  sudo bash bootstrap-node.sh 1
#   node2/3 (join):        sudo bash bootstrap-node.sh 2   (resp. 3)
#
# Result per node: k3s server (embedded etcd, no kube-proxy/network-policy/
# servicelb), keepalived for the API VIP, NO HAProxy (purged if present).
# Cilium is installed exactly once by node1 after all nodes have joined.
#
# Adapt the block below to your network, then run.
#
set -euo pipefail

# ---- cluster knobs -------------------------------------------------------
NODE_IPS=(10.22.50.121 10.22.50.122 10.22.50.123)  # physical node IPs, index = node number-1
API_VIP=10.22.50.120          # floating admin/API VIP (keepalived)
KEEPALIVED_PRIOS=(120 110 100)                     # priority per node
K3S_VERSION=v1.36.4+k3s1
CILIUM_VERSION=1.20.1
LB_POOL_START=10.22.50.60     # Cilium L2 pool for LoadBalancer services
LB_POOL_STOP=10.22.50.79
VRRP_ID=51
# ---------------------------------------------------------------------------

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
N="${1:?usage: $0 <1|2|3>}"
IDX=$((N-1))
IFACE=$(ip route get 1.1.1.1 | grep -oE 'dev [^ ]+' | cut -d' ' -f2)

echo ">>> node $N — iface $IFACE"

# ---- 0. packages (deliberately no haproxy) --------------------------------
apt-get update
apt-get install -y curl keepalived
apt-get purge -y haproxy 2>/dev/null || true   # the old balancer must not survive

# ---- 1. kernel prerequisites (Cilium) -------------------------------------
modprobe overlay br_netfilter
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/cilium.conf
cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system >/dev/null

# ---- 2. k3s ----------------------------------------------------------------
# kube-proxy is replaced by Cilium; network policy likewise; servicelb by
# Cilium L2. tls-san keeps the VIP valid in the API cert.
EXTRA=(server --disable servicelb --disable-network-policy --disable-kube-proxy
       --tls-san "$API_VIP")
if [ "$N" = 1 ]; then
  EXTRA+=(--cluster-init)
else
  EXTRA+=(--server "https://${NODE_IPS[0]}:6443")
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="${EXTRA[*]}" sh -

# ---- 3. keepalived (pure VRRP, tracks k3s, no haproxy anywhere) -----------
{
  cat <<EOF
vrrp_script chk_k3s {
    script "systemctl is-active --quiet k3s"
    interval 5
    fall 3
    rise 2
}
vrrp_instance K3S_API {
    state BACKUP
    interface $IFACE
    virtual_router_id $VRRP_ID
    priority ${KEEPALIVED_PRIOS[$IDX]}
    advert_int 1
    nopreempt
    unicast_src_ip ${NODE_IPS[$IDX]}
    unicast_peer {
EOF
  for i in "${!NODE_IPS[@]}"; do
    [ "$i" = "$IDX" ] || echo "        ${NODE_IPS[$i]}"
  done
  cat <<EOF
    }
    virtual_ipaddress {
        $API_VIP/24
    }
    track_script {
        chk_k3s
    }
}
EOF
} > /etc/keepalived/keepalived.conf

keepalived --config-test
systemctl enable --now keepalived

# ---- 4. Cilium — node1 only, and only after the others have joined --------
if [ "$N" = 1 ]; then
  echo ">>> Wait for all nodes: kubectl get nodes   — then re-run this script with 'cilium'"
  case "${2:-}" in
    cilium)
      curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
      helm repo add cilium https://helm.cilium.io/ && helm repo update
      helm upgrade --install cilium cilium/cilium \
        --version "$CILIUM_VERSION" --namespace kube-system \
        --set kubeProxyReplacement=true \
        --set ingressController.enabled=false \
        --set l2announcements.enabled=true
      kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --timeout=300s

      # L2 announcements + LoadBalancer IP pool (Traefik .60, blocky .62 ...)
      kubectl apply -f - <<POOL
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: lan-l2-policy
spec:
  interfaces: ["^(eno1|enp0s31f6)\$"]
  loadBalancerIPs: true
---
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: lan-pool
spec:
  blocks:
    - start: $LB_POOL_START
      stop: $LB_POOL_STOP
POOL
      echo ">>> Cilium + L2 pool done. Install Traefik via HelmChartConfig/GitOps next."
      ;;
  esac
fi

echo ">>> node $N done. Verify: systemctl is-active k3s keepalived && kubectl get nodes"
