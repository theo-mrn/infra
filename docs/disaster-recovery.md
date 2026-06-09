# Disaster Recovery

Procédures de restauration pour le cluster afflair.app.

---

## 1. Backup de la clé privée Sealed Secrets

**À faire manuellement après chaque installation ou rotation.**

La clé privée sealed-secrets n'est jamais sauvegardée par Velero. Sans elle, tous les
SealedSecrets du repo sont définitivement irrécupérables.

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# Exporter la clé privée
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > /tmp/sealed-secrets-master-key.yaml

# Stocker ce fichier dans un gestionnaire de secrets hors-cluster (Bitwarden, 1Password…)
# NE PAS committer dans git
```

Pour restaurer la clé sur un nouveau cluster :

```bash
kubectl apply -f sealed-secrets-master-key.yaml
kubectl rollout restart deployment -n sealed-secrets
```

---

## 2. Perte d'un nœud worker

Le worker héberge les workloads applicatifs. Longhorn réplique les PVC sur les 2 nœuds.

**Impact** : applications indisponibles, données accessibles depuis le master.

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# 1. Vérifier l'état Longhorn
kubectl get nodes
kubectl get volumes -n longhorn-system

# 2. Reprovisionner le nœud (Ansible)
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit worker
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit worker

# 3. Longhorn réplique automatiquement les volumes sur le nœud rejoint
# Surveiller la réplication :
kubectl get replicas -n longhorn-system -w
```

---

## 3. Perte du nœud master

**Impact** : cluster entièrement indisponible. Toutes les données sont dans Longhorn (worker) et S3 (Velero).

### 3a. Reprovisionner le master

```bash
# 1. Bootstrap OS
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit master

# 2. Installer k3s master
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit master
# → régénère ansible/kubeconfig.yml

export KUBECONFIG=./ansible/kubeconfig.yml

# 3. Rejoindre le worker existant au nouveau master
# (le worker doit être reprovisoinné si son token k3s a changé)
```

### 3b. Restaurer la clé Sealed Secrets

```bash
# Récupérer la clé sauvegardée depuis le gestionnaire de secrets
kubectl apply -f sealed-secrets-master-key.yaml
kubectl rollout restart deployment -n sealed-secrets
```

### 3c. Réinstaller les composants système

Suivre l'ordre d'installation du README (étapes 6 à 11).

### 3d. Restaurer depuis Velero

```bash
# Lister les backups disponibles
velero backup get

# Restaurer le dernier backup complet
velero restore create --from-backup NOM_DU_BACKUP --wait

# Vérifier
kubectl get pods -A
```

---

## 4. Restauration Velero ciblée

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# Lister les backups
velero backup get

# Restaurer un namespace spécifique
velero restore create \
  --from-backup NOM_DU_BACKUP \
  --include-namespaces times-server \
  --wait

# Restaurer une ressource spécifique
velero restore create \
  --from-backup NOM_DU_BACKUP \
  --include-resources deployments \
  --include-namespaces beacon \
  --wait
```

---

## 5. Restaurer les logs Loki depuis S3

Les données Loki sont syncées toutes les heures dans `s3://velero-k3s-cluster-backup/loki/`.

```bash
# Synchroniser S3 → local pour inspection
aws s3 sync s3://velero-k3s-cluster-backup/loki/ /tmp/loki-restore/ \
  --region eu-west-3

# Ou restaurer directement dans le PVC Loki
# (nécessite d'arrêter Loki, copier les données, redémarrer)
kubectl scale statefulset loki -n monitoring --replicas=0
# ... copier les données dans le PVC ...
kubectl scale statefulset loki -n monitoring --replicas=1
```

---

## 6. Vérifications post-restauration

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# Nœuds
kubectl get nodes -o wide

# Pods
kubectl get pods -A | grep -v Running | grep -v Completed

# PVC
kubectl get pvc -A

# ArgoCD sync status
kubectl get applications -n argocd

# Volumes Longhorn
kubectl get volumes -n longhorn-system

# Certificats TLS
kubectl get certificates -A
```
