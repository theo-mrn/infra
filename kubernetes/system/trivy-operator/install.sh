#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update

helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system \
  --create-namespace \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait \
  --timeout 5m

echo "Trivy Operator installé. Pods :"
kubectl get pods -n trivy-system
