#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Attente du démarrage d'ArgoCD..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "ArgoCD installé. Pods :"
kubectl get pods -n argocd
