#!/usr/bin/env bash
set -euo pipefail

# Installe Traefik via Helm sur le cluster k3s
# Prérequis : helm installé localement, KUBECONFIG pointant vers kubeconfig.yml

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add traefik https://helm.traefik.io/traefik
helm repo update

kubectl apply -f "$(dirname "$0")/namespace.yml"

helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait

echo "Traefik installé. Pods :"
kubectl get pods -n traefik
echo ""
echo "Service :"
kubectl get svc -n traefik
