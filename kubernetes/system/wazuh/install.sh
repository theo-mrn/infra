#!/bin/bash
set -euo pipefail

WAZUH_VERSION="v4.14.5"
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
EOF

# ── Deploy ────────────────────────────────────────────────────────────────────
echo "==> Deploying Wazuh..."
kubectl apply -k envs/local-env/

echo "==> Waiting for Wazuh indexer (can take several minutes)..."
kubectl rollout status statefulset/wazuh-indexer -n wazuh --timeout=600s

echo "==> Waiting for Wazuh manager master..."
kubectl rollout status statefulset/wazuh-manager-master -n wazuh --timeout=300s

echo "==> Waiting for Wazuh dashboard..."
kubectl rollout status deployment/wazuh-dashboard -n wazuh --timeout=300s

echo ""
echo "==> Wazuh is up!"
echo "    Dashboard: kubectl port-forward svc/wazuh-dashboard 443:443 -n wazuh"
echo "    Login: admin / SecretPassword  <-- change immediately!"
