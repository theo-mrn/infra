# Disaster Recovery

Procédures de restauration pour le cluster afflair.app.

> **Aucun backup automatisé n'est actuellement en place** (Velero retiré en 2026-09,
> bucket S3 supprimé). Les procédures ci-dessous couvrent uniquement ce qui est
> récupérable via l'IaC (GitOps) et les sauvegardes manuelles existantes (clé
> sealed-secrets). Les données applicatives (PVC : bases de données, volumes) ne
> sont **pas récupérables** en cas de perte d'un nœud tant qu'aucune solution de
> backup n'est remise en place.

---

## 1. Backup de la clé privée Sealed Secrets

**À faire manuellement après chaque installation ou rotation — c'est la seule
sauvegarde manuelle critique du cluster.**

Sans cette clé, tous les `SealedSecret` du repo sont définitivement irrécupérables.

```bash
export KUBECONFIG=/Users/theo/Developer/infra/ansible/kubeconfig.yml

# Exporter la clé privée (le controller sealed-secrets tourne dans kube-system)
kubectl get secrets -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-master-key.yaml
```

Le fichier contient la clé privée TLS en clair — **ne jamais committer dans git**.
Le chiffrer avant de le stocker :

```bash
gpg --symmetric --cipher-algo AES256 ~/sealed-secrets-master-key.yaml
rm ~/sealed-secrets-master-key.yaml
# → ~/sealed-secrets-master-key.yaml.gpg à stocker sur iCloud, Google Drive, etc.
```

Pour vérifier que le fichier est valide :

```bash
gpg --decrypt ~/sealed-secrets-master-key.yaml.gpg | head -5
```

Pour restaurer la clé sur un nouveau cluster :

```bash
gpg --decrypt ~/sealed-secrets-master-key.yaml.gpg > /tmp/sealed-secrets-master-key.yaml
kubectl apply -f /tmp/sealed-secrets-master-key.yaml
kubectl rollout restart deployment -n kube-system -l app.kubernetes.io/name=sealed-secrets
rm /tmp/sealed-secrets-master-key.yaml
```

---

## 2. Perte d'un nœud worker (worker ou worker2)

Avec `local-path`, les PVC sont liés au nœud sur lequel ils ont été créés —
**aucune réplication entre nœuds**.

**Impact** : pods schedulés sur ce nœud indisponibles ; PVC de ce nœud **perdus
définitivement** (pas de backup actuellement).

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# 1. Vérifier l'état du nœud
kubectl get nodes

# 2. Retirer proprement l'ancien enregistrement si le nœud est irrécupérable
kubectl delete node <nom-du-worker>

# 3. Reprovisionner le nœud (Ansible) — bootstrap complet + join k3s
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit <worker|worker2>
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit <worker|worker2>

# 4. ArgoCD reschedule automatiquement les workloads stateless sur les nœuds
#    disponibles (selfHeal). Les workloads avec PVC sur le nœud perdu doivent
#    être recréés manuellement (les données ne sont pas récupérables).
```

---

## 3. Perte du nœud master

**Impact** : cluster entièrement indisponible (control-plane k3s). Les PVC du
master sont perdus (Loki, Jenkins, Traefik acme.json, Authelia — pas de backup
actuellement).

### 3a. Reprovisionner le master

```bash
# 1. Bootstrap OS
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit master

# 2. Installer k3s master
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit master
# → régénère ansible/kubeconfig.yml

export KUBECONFIG=./ansible/kubeconfig.yml

# 3. Rejoindre les workers existants au nouveau master
# (chaque worker doit être reprovisionné si son token k3s a changé)
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit worker,worker2
```

### 3b. Réinstaller ArgoCD (seul composant hors GitOps)

```bash
bash argocd_registry/kubernetes/system/argocd/install.sh
```

### 3c. Restaurer la clé Sealed Secrets

```bash
gpg --decrypt ~/sealed-secrets-master-key.yaml.gpg | kubectl apply -f -
kubectl rollout restart deployment -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

### 3d. Réappliquer toutes les Applications ArgoCD

Toute la stack système (Traefik, Authelia, sealed-secrets, CNPG, trivy-operator,
SonarQube, Jenkins, monitoring, CrowdSec) et les applications sont décrites en
`Application` ArgoCD :

```bash
kubectl apply -f argocd_registry/kubernetes/system/argocd/apps/
```

ArgoCD reconstruit alors l'intégralité de la stack depuis Git. Les `SealedSecret`
présents dans le repo se déchiffrent automatiquement une fois la clé privée
restaurée (étape 3c).

> Les données perdues (bases de données CNPG/PostgreSQL, index SonarQube, historique
> Jenkins, dashboards Grafana custom) ne sont pas récupérées par cette procédure —
> seule la configuration/l'infrastructure l'est.

---

## 4. Vérifications post-restauration

```bash
export KUBECONFIG=./ansible/kubeconfig.yml

# Nœuds
kubectl get nodes -o wide

# Pods
kubectl get pods -A | grep -v Running | grep -v Completed

# PVC
kubectl get pvc -A

# ArgoCD sync status — toutes les Applications doivent finir Synced/Healthy
kubectl get applications -n argocd

# Accès HTTPS (certificats Let's Encrypt réémis automatiquement par Traefik)
curl -I https://auth.cluster.afflair.app
```

---

## À faire pour améliorer la résilience

- **Remettre en place un backup automatisé** (Velero + nouveau bucket S3 avec un
  backend Terraform séparé du bucket de backup, ou alternative) — priorité haute,
  aucune donnée applicative n'est actuellement récupérable en cas de perte de nœud.
- Automatiser la sauvegarde périodique de la clé sealed-secrets (actuellement 100%
  manuelle).
