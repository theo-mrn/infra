#!/bin/bash
set -euo pipefail

WAZUH_VERSION="v4.14.1"
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

echo "==> Cloning wazuh-kubernetes ${WAZUH_VERSION}..."
git clone --depth=1 --branch "${WAZUH_VERSION}" https://github.com/wazuh/wazuh-kubernetes.git "${TMPDIR}/wazuh-kubernetes"

cd "${TMPDIR}/wazuh-kubernetes"

# Use longhorn as the wazuh-storage provisioner
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

echo "==> Deploying Wazuh (local-env overlay with Longhorn storage)..."
kubectl apply -k envs/local-env/

echo "==> Waiting for Wazuh indexer..."
kubectl rollout status statefulset/wazuh-indexer -n wazuh --timeout=300s

echo "==> Waiting for Wazuh manager master..."
kubectl rollout status statefulset/wazuh-manager-master -n wazuh --timeout=300s

echo "==> Waiting for Wazuh dashboard..."
kubectl rollout status deployment/wazuh-dashboard -n wazuh --timeout=300s

echo ""
echo "==> Wazuh is up!"
echo "    Dashboard: kubectl port-forward svc/wazuh-dashboard 5601:5601 -n wazuh"
echo "    Login: admin / SecretPassword  <-- change immediately!"
