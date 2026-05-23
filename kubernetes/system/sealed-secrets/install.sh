#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller \
  --wait

echo "Sealed Secrets installé."
kubectl get pods -n kube-system | grep sealed-secrets
