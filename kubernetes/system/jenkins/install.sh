#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add jenkins https://charts.jenkins.io
helm repo update

kubectl apply -f "$(dirname "$0")/namespace.yml"

helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values "$(dirname "$0")/helm-values.yml" \
  --wait \
  --timeout 10m

kubectl apply -f "$(dirname "$0")/ingress.yml"

echo "Jenkins installé. Pods :"
kubectl get pods -n jenkins
echo ""
echo "Jenkins disponible sur : https://jenkins.cluster.afflair.app"
echo ""
echo "Mot de passe admin initial :"
kubectl exec -n jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password
