# infra

Pipeline GitOps pour l'infrastructure k3s — 2 VPS Hostinger (Ubuntu 24.04 LTS, Paris).

| Nœud | IP | Rôle |
|------|----|------|
| master | 76.13.44.160 | control-plane + Traefik |
| worker | 217.65.146.24 | workloads |

DNS : `cluster.afflair.app` + `*.cluster.afflair.app` → 76.13.44.160

---

## Prérequis locaux

```bash
brew install ansible helm kubectl terraform kubeseal
pip install sshpass  # premier run sur le worker (auth par mot de passe)
```

---

## Installation from scratch

> L'ordre est important. Chaque étape dépend de la précédente.

### 1. Terraform — S3 bucket + IAM (à faire en premier)

```bash
cd terraform/aws
terraform init   # migre l'état vers S3 si nécessaire : terraform init -migrate-state
terraform apply
# noter les outputs : access_key_id et secret_access_key
cd ../..
```

### 2. Secrets Ansible Vault

```bash
ansible-vault create ansible/inventory/group_vars/all/vault.yml
# → ajouter : vault_worker_ssh_pass: "MOT_DE_PASSE_SSH_WORKER"

echo "TON_VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass
```

### 3. Bootstrap OS (hardening + clé SSH)

```bash
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass
```

Après ce step, le worker accepte la clé SSH — plus besoin de mot de passe.

### 4. Installer k3s

```bash
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass
# → génère ansible/kubeconfig.yml (le provisioner local-path est inclus par défaut)
export KUBECONFIG=./ansible/kubeconfig.yml
```

### 5. Traefik (ingress + Let's Encrypt)

```bash
bash kubernetes/system/traefik/install.sh
```

### 6. Sealed Secrets (opérateur kubeseal)

```bash
bash kubernetes/system/sealed-secrets/install.sh
```

### 7. Authelia (SSO)

```bash
# Appliquer d'abord les SealedSecrets Authelia
kubectl apply -f kubernetes/system/authelia/
bash kubernetes/system/authelia/install.sh
```

### 8. Velero (backup)

```bash
export VELERO_ACCESS_KEY_ID=$(cd terraform/aws && terraform output -raw velero_access_key_id)
export VELERO_SECRET_ACCESS_KEY=$(cd terraform/aws && terraform output -raw velero_secret_access_key)
bash kubernetes/system/velero/install.sh
kubectl apply -f kubernetes/system/velero/schedule.yml
kubectl apply -f kubernetes/system/velero/loki-backup-cronjob.yml
```

### 9. ArgoCD (GitOps — déploie tout le reste)

```bash
bash kubernetes/system/argocd/install.sh
# ArgoCD déploie automatiquement : monitoring, Loki, Promtail, Falco,
# CrowdSec, Trivy, beacon, times-server, trivyhub, sonarqube
```

### 10. Sceller la clé CrowdSec pour beacon

Après que CrowdSec soit opérationnel, récupérer la clé bouncer et la sceller :

```bash
# Récupérer la clé depuis CrowdSec
CROWDSEC_KEY=$(kubectl exec -n crowdsec deploy/crowdsec -- cscli bouncers add beacon-bouncer -o raw)

kubectl create secret generic beacon-crowdsec-api-key \
  --namespace beacon \
  --from-literal=api-key="$CROWDSEC_KEY" \
  --dry-run=client -o yaml \
| kubeseal --cert kubernetes/system/sealed-secrets/pub-cert.pem --format yaml \
> kubernetes/system/argocd/sealed-beacon-crowdsec-key.yml

kubectl apply -f kubernetes/system/argocd/sealed-beacon-crowdsec-key.yml
```

---

## Accès

```bash
export KUBECONFIG=./ansible/kubeconfig.yml
kubectl get nodes
kubectl get pods -A
```

| Service | URL | Auth |
|---------|-----|------|
| ArgoCD | https://argocd.cluster.afflair.app | Authelia + ArgoCD natif |
| Grafana | https://grafana.cluster.afflair.app | Authelia + OIDC |
| Traefik | https://traefik.cluster.afflair.app | Authelia |
| Beacon | https://beacon.cluster.afflair.app | Authelia |
| SonarQube | https://sonarqube.cluster.afflair.app | Authelia |

---

## Stack

### Infrastructure
- **k3s** — Kubernetes léger, Flannel VXLAN overlay, sans kube-proxy
- **Traefik v3** — ingress controller, Let's Encrypt httpChallenge
- **local-path** — provisioner de volumes locaux (k3s natif, sans réplication)
- **Sealed Secrets** — chiffrement asymétrique des secrets Kubernetes
- **ArgoCD** — GitOps, 12 applications déployées automatiquement

### Monitoring
- **kube-prometheus-stack** — Prometheus (7j rétention), Grafana, AlertManager → Discord
- **Loki + Promtail** — agrégation des logs cluster-wide

### Sécurité
- **Authelia** — SSO OIDC sur tous les services internes
- **CrowdSec** — WAF + bouncer Traefik (50+ scénarios)
- **Falco** — runtime security, alertes Discord temps réel
- **Trivy Operator** — scan CVE continu, alertes Prometheus CRITICAL/HIGH
- **kube-bench** — audit CIS k3s (0 FAIL)
- **Lynis** — audit hebdomadaire des nœuds (dimanche 3h)
- **UFW** — SSH/API restreints aux IPs de gestion

### Backup
- **Velero** — backup quotidien à 2h (manifests k8s + volumes via node-agent restic/kopia)
- **CronJob aws-cli** — sync horaire Loki → S3
- **S3** `velero-k3s-cluster-backup` (eu-west-3) — chiffrement AES256, versioning activé

---

## Backup

### Ce qui est sauvegardé

| Quoi | Outil | Fréquence | Destination | Rétention |
|------|-------|-----------|-------------|-----------|
| Manifests k8s + volumes PVC | Velero (node-agent restic/kopia) | Quotidien 2h | `s3://.../velero/` | 7 jours |
| Données Loki (logs) | CronJob aws-cli | Horaire | `s3://.../loki/` | Illimité |

### Backup manuel

```bash
export KUBECONFIG=./ansible/kubeconfig.yml
kubectl create -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: backup-manuel-$(date +%Y%m%d)
  namespace: velero
spec:
  includedNamespaces:
    - monitoring
    - traefik
  storageLocation: aws
  ttl: 168h
  defaultVolumesToFsBackup: true
EOF
```

### Restaurer

```bash
velero restore create --from-backup NOM_DU_BACKUP
```

Voir `docs/disaster-recovery.md` pour les procédures complètes.

---

## Secrets requis

| Variable | Usage | Source |
|----------|-------|--------|
| `vault_worker_ssh_pass` | Ansible Vault — mot de passe SSH worker | manuel |
| `VELERO_ACCESS_KEY_ID` | AWS pour Velero | `terraform output velero_access_key_id` |
| `VELERO_SECRET_ACCESS_KEY` | AWS pour Velero | `terraform output velero_secret_access_key` |

---

## Structure du repo

```
ansible/
  inventory/
    hosts.yml                    # master (clé SSH) + worker (vault)
    group_vars/all/vault.yml     # secrets chiffrés ansible-vault
  playbooks/
    01-bootstrap.yml             # hardening OS + déploiement clé SSH
    02-k3s.yml                   # installation k3s master + worker
    03-cis-hardening.yml         # contrôles CIS Level 1
    04-kube-bench.yml            # audit CIS k3s
    05-firewall-hardening.yml    # règles UFW par nœud
  roles/
    common/                      # hardening, UFW, packages
    cis_hardening/                # contrôles CIS Level 1
    k3s_master/                  # install k3s server
    k3s_worker/                  # install k3s agent

kubernetes/
  system/
    argocd/                      # GitOps — install.sh + 12 app manifests
    authelia/                    # SSO — helm-values + sealed secrets
    traefik/                     # ingress + Let's Encrypt
    velero/                      # backup k8s + volumes (restic/kopia)
    sealed-secrets/              # opérateur kubeseal + pub-cert.pem
    monitoring/                  # dashboards, alerting rules (Prometheus/Grafana)
    network-policies/            # NetworkPolicies par namespace
    crowdsec/                    # sealed secrets bouncer
    falco/                       # règles syscall locales
    trivy-operator/              # helm-values scan CVE
    cnpg/                        # CloudNativePG install
    sonarqube/                   # qualité code
  apps/
    times-server/                # sealed secrets prod + staging

terraform/
  aws/                           # S3 bucket + IAM user velero (remote state S3)

docs/
  architecture.md                # stack, ordre de déploiement, fichiers sensibles
  security-todo.md               # points de sécurité ouverts
  network-exposure.yml           # matrice firewall + services exposés
  disaster-recovery.md           # procédures de restauration
```
