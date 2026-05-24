#!/bin/bash
set -e

echo "=== Authelia + Redis — Installation ==="

# Namespace
kubectl apply -f namespace.yml

# Sceller le secret avec kubeseal avant de committer
# Pour l'instant, appliquer en clair (à sceller ensuite)
echo "⚠️  Application du secret en clair — à sceller avec kubeseal avant de committer !"
kubectl apply -f secrets.yml

# Redis
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm upgrade --install authelia-redis bitnami/redis \
  --namespace authelia \
  --values redis-values.yml \
  --wait

# Authelia
helm repo add authelia https://charts.authelia.com
helm repo update
helm upgrade --install authelia authelia/authelia \
  --namespace authelia \
  --values helm-values.yml \
  --wait

# Ingress + Middleware
kubectl apply -f ingress.yml
kubectl apply -f middleware.yml

echo ""
echo "=== Authelia déployé ==="
echo "Portal : https://auth.cluster.afflair.app"
echo ""
echo "Prochaine étape : protéger les apps avec le middleware authelia@authelia"
