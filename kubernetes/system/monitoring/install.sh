#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl apply -f "$(dirname "$0")/namespace.yml"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait \
  --timeout 10m

kubectl apply -f "$(dirname "$0")/ingress.yml"

helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values "$(dirname "$0")/loki-values.yml" \
  --wait \
  --timeout 5m

helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --values "$(dirname "$0")/promtail-values.yml" \
  --wait \
  --timeout 5m

echo "Monitoring installé. Pods :"
kubectl get pods -n monitoring
echo ""
echo "Grafana disponible sur : https://grafana.cluster.afflair.app"
echo "Login : admin / voir helm-values.yml"
