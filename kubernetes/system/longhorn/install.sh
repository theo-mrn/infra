#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add longhorn https://charts.longhorn.io
helm repo update

kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait --timeout 10m

# Longhorn devient le seul storage par défaut
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Configure le backup target S3 (utilise les mêmes credentials que Velero)
: "${VELERO_ACCESS_KEY_ID:?Variable VELERO_ACCESS_KEY_ID non définie}"
: "${VELERO_SECRET_ACCESS_KEY:?Variable VELERO_SECRET_ACCESS_KEY non définie}"

kubectl create secret generic longhorn-aws-credentials \
  --namespace longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID="${VELERO_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${VELERO_SECRET_ACCESS_KEY}" \
  --from-literal=AWS_ENDPOINTS="" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl patch backuptargets.longhorn.io default -n longhorn-system --type merge -p "{
  \"spec\": {
    \"backupTargetURL\": \"s3://velero-k3s-cluster-backup@eu-west-3/longhorn\",
    \"credentialSecret\": \"longhorn-aws-credentials\",
    \"pollInterval\": 300
  }
}"

echo "Longhorn installé. Pods :"
kubectl get pods -n longhorn-system
