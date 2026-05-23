#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

BUCKET="velero-k3s-cluster-backup"
REGION="eu-west-3"

# Vérifie que les variables sont définies
: "${VELERO_ACCESS_KEY_ID:?Variable VELERO_ACCESS_KEY_ID non définie}"
: "${VELERO_SECRET_ACCESS_KEY:?Variable VELERO_SECRET_ACCESS_KEY non définie}"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -

# Crée le secret AWS
kubectl create secret generic velero-aws-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=${VELERO_ACCESS_KEY_ID}
aws_secret_access_key=${VELERO_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --set configuration.backupStorageLocation[0].name=aws \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket="${BUCKET}" \
  --set configuration.backupStorageLocation[0].config.region="${REGION}" \
  --set configuration.volumeSnapshotLocation[0].name=aws \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.region="${REGION}" \
  --set credentials.existingSecret=velero-aws-credentials \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.10.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set deployNodeAgent=true \
  --wait

echo "Velero installé. Pods :"
kubectl get pods -n velero
