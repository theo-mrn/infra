#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update

kubectl apply -f "$(dirname "$0")/namespace.yml"
kubectl apply -f "$(dirname "$0")/sealed-secrets.yml"

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait \
  --timeout 10m

kubectl apply -f "$(dirname "$0")/ingress.yml"

echo "SonarQube installé. Pods :"
kubectl get pods -n sonarqube
echo ""
echo "SonarQube disponible sur : https://sonarqube.cluster.afflair.app"
echo "Login par défaut : admin / admin (à changer à la première connexion)"
