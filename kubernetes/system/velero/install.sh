#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

BUCKET="velero-k3s-cluster-backup"
REGION="eu-west-3"

: "${VELERO_ACCESS_KEY_ID:?Variable VELERO_ACCESS_KEY_ID non définie}"
: "${VELERO_SECRET_ACCESS_KEY:?Variable VELERO_SECRET_ACCESS_KEY non définie}"

helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic velero-aws-credentials \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=${VELERO_ACCESS_KEY_ID}
aws_secret_access_key=${VELERO_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait

# Secret pour le CronJob de backup Loki (namespace monitoring)
kubectl create secret generic velero-aws-credentials-loki \
  --namespace monitoring \
  --from-literal=access_key_id="${VELERO_ACCESS_KEY_ID}" \
  --from-literal=secret_access_key="${VELERO_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Velero installé. Pods :"
kubectl get pods -n velero
