#!/usr/bin/env bash
set -euo pipefail

# Le manifest officiel ArgoCD (install.yaml) ne définit aucune resources
# requests/limits. On les ajoute via kubectl patch (strategic merge) plutôt
# que via kubectl apply, car un manifest partiel échoue en apply (champs
# requis manquants : selector, image...).
# Calibré sur la consommation réelle observée (kubectl top), avec marge
# pour les pics (sync de nombreuses Applications en parallèle).

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

kubectl patch deployment argocd-server -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"500m","memory":"256Mi"}}}]}}}}'

kubectl patch deployment argocd-repo-server -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-repo-server","resources":{"requests":{"cpu":"50m","memory":"256Mi"},"limits":{"cpu":"1","memory":"1Gi"}}}]}}}}'

kubectl patch deployment argocd-dex-server -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"dex","resources":{"requests":{"cpu":"20m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}}]}}}}'

kubectl patch deployment argocd-redis -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"redis","resources":{"requests":{"cpu":"20m","memory":"32Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}}]}}}}'

kubectl patch deployment argocd-applicationset-controller -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-applicationset-controller","resources":{"requests":{"cpu":"20m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}}]}}}}'

kubectl patch deployment argocd-notifications-controller -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-notifications-controller","resources":{"requests":{"cpu":"20m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}}]}}}}'

kubectl patch statefulset argocd-application-controller -n argocd --type strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-application-controller","resources":{"requests":{"cpu":"100m","memory":"512Mi"},"limits":{"cpu":"1","memory":"1Gi"}}}]}}}}'

echo "Resources ArgoCD patchées."
