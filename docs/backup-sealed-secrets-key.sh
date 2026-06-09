#!/usr/bin/env bash
# Exporte et chiffre la clé privée Sealed Secrets.
# À exécuter manuellement après installation ou rotation de la clé.
# Le fichier .gpg produit est à stocker hors du repo (iCloud, gestionnaire de secrets).
set -euo pipefail

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

BACKUP_FILE="$HOME/sealed-secrets-master-key-$(date +%Y%m%d).yaml"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"

echo "→ Export de la clé privée Sealed Secrets..."
kubectl get secrets -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
  echo "ERREUR : aucune clé trouvée dans kube-system. Vérifier que sealed-secrets est installé."
  rm -f "$BACKUP_FILE"
  exit 1
fi

echo "→ Chiffrement GPG..."
gpg --symmetric --cipher-algo AES256 --output "$ENCRYPTED_FILE" "$BACKUP_FILE"
rm -f "$BACKUP_FILE"

echo ""
echo "✓ Clé sauvegardée dans : $ENCRYPTED_FILE"
echo "  → À stocker sur iCloud Drive, Bitwarden, ou 1Password."
echo "  → NE PAS committer dans git."
echo ""
echo "Vérification :"
gpg --decrypt "$ENCRYPTED_FILE" | grep "name:" | head -3
