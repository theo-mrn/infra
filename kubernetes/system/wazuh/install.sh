#!/bin/bash
set -euo pipefail

WAZUH_VERSION="v4.14.5"
WAZUH_MANAGER_IP="76.13.44.160"
AUTHD_PASS="password"
NODES=("76.13.44.160" "217.65.146.24")
NODE_NAMES=("master" "worker")

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

echo "==> Cloning wazuh-kubernetes ${WAZUH_VERSION}..."
git clone https://github.com/wazuh/wazuh-kubernetes.git "${TMPDIR}/wazuh-kubernetes"
git -C "${TMPDIR}/wazuh-kubernetes" checkout "${WAZUH_VERSION}"

cd "${TMPDIR}/wazuh-kubernetes"

# ── Generate TLS certificates ─────────────────────────────────────────────────
echo "==> Generating TLS certificates..."
bash wazuh/certs/indexer_cluster/generate_certs.sh > /dev/null
bash wazuh/certs/dashboard_http/generate_certs.sh > /dev/null

# ── Patch storage class to Longhorn ──────────────────────────────────────────
cat > envs/local-env/storage-class.yaml <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: wazuh-storage
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"
reclaimPolicy: Retain
allowVolumeExpansion: true
EOF

# ── Patch PVC sizes (default 500Mi is too small) ──────────────────────────────
find . -name "*.yaml" -exec sed -i 's/storage: 500Mi/storage: 5Gi/g' {} \;

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "==> Deploying Wazuh..."
kubectl apply -k envs/local-env/

echo "==> Waiting for Wazuh indexer (can take several minutes)..."
kubectl rollout status statefulset/wazuh-indexer -n wazuh --timeout=600s

echo "==> Waiting for Wazuh manager master..."
kubectl rollout status statefulset/wazuh-manager-master -n wazuh --timeout=300s

echo "==> Waiting for Wazuh dashboard..."
kubectl rollout status deployment/wazuh-dashboard -n wazuh --timeout=300s

# ── Install agents on nodes ───────────────────────────────────────────────────
echo "==> Installing Wazuh agents on nodes..."
for i in "${!NODES[@]}"; do
  NODE="${NODES[$i]}"
  NAME="${NODE_NAMES[$i]}"
  echo "    -> ${NAME} (${NODE})"
  ssh "root@${NODE}" bash <<EOF
set -e
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo 'deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main' > /etc/apt/sources.list.d/wazuh.list
apt-get update -qq
WAZUH_MANAGER='${WAZUH_MANAGER_IP}' WAZUH_AGENT_NAME='${NAME}' apt-get install -y wazuh-agent 2>/dev/null || true
sed -i 's|<address>.*</address>|<address>${WAZUH_MANAGER_IP}</address>|g' /var/ossec/etc/ossec.conf
echo '${AUTHD_PASS}' > /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass
chown root:wazuh /var/ossec/etc/authd.pass
systemctl enable wazuh-agent
systemctl restart wazuh-agent
EOF
done

echo ""
echo "==> Wazuh is up!"
echo "    Dashboard: https://wazuh.cluster.afflair.app"
echo "    Login: admin / SecretPassword  <-- change immediately!"
