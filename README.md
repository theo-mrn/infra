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
brew install ansible helm kubectl terraform
pip install sshpass  # auth par mot de passe au premier run sur le worker
```

---

## Installation from scratch

### 1. Secrets Ansible Vault

```bash
# Créer le fichier vault avec le mot de passe SSH du worker
ansible-vault create ansible/inventory/group_vars/all/vault.yml
# → ajouter : vault_worker_ssh_pass: "MOT_DE_PASSE"

# Créer le fichier vault password (gitignored)
echo "TON_VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass
```

### 2. Bootstrap OS (hardening + clé SSH)

```bash
cd ansible
ansible-playbook playbooks/01-bootstrap.yml --vault-password-file ../.vault_pass
```

Après ce step, le worker accepte la clé SSH — plus besoin de mot de passe.

### 3. Installer k3s

```bash
ansible-playbook playbooks/02-k3s.yml --vault-password-file ../.vault_pass
# → génère ansible/kubeconfig.yml
```

### 4. Prérequis Longhorn

```bash
ansible-playbook longhorn-prereqs.yml --vault-password-file ../.vault_pass
```

### 5. Traefik (ingress + Let's Encrypt)

```bash
bash kubernetes/system/traefik/install.sh
```

### 6. Monitoring (Prometheus + Grafana + Loki + Promtail)

```bash
bash kubernetes/system/monitoring/install.sh
```

### 7. Longhorn (storage distribué)

```bash
export VELERO_ACCESS_KEY_ID=...
export VELERO_SECRET_ACCESS_KEY=...
bash kubernetes/system/longhorn/install.sh
```

### 8. Velero (backup)

```bash
export VELERO_ACCESS_KEY_ID=...
export VELERO_SECRET_ACCESS_KEY=...
bash kubernetes/system/velero/install.sh

# Appliquer le schedule et le CronJob Loki
kubectl apply -f kubernetes/system/velero/schedule.yml
kubectl apply -f kubernetes/system/velero/loki-backup-cronjob.yml
```

### 9. Terraform (S3 + IAM — à faire en premier si bucket inexistant)

```bash
cd terraform/aws
terraform init
terraform apply
# → noter les outputs access_key_id et secret_access_key
```

---

## Accès

| Service | URL |
|---------|-----|
| Grafana | https://grafana.cluster.afflair.app |
| Traefik dashboard | https://traefik.cluster.afflair.app |
| Longhorn UI | https://longhorn.cluster.afflair.app |

```bash
export KUBECONFIG=./ansible/kubeconfig.yml
kubectl get nodes
kubectl get pods -A
```

---

## Stack

### Infrastructure
- **k3s** v1.35 — Kubernetes léger, Flannel VXLAN overlay
- **Traefik** v3 — ingress controller, Let's Encrypt httpChallenge
- **Longhorn** — storage distribué avec réplication 2x (master + worker)

### Monitoring
- **kube-prometheus-stack** — Prometheus (15j rétention), Grafana, AlertManager
- **Loki + Promtail** — agrégation des logs cluster-wide

### Backup
- **Velero** — backup quotidien à 2h des manifests k8s + snapshots CSI Longhorn
- **CronJob aws-cli** — sync horaire des données Loki vers S3
- **S3** `velero-k3s-cluster-backup` (eu-west-3) — stockage des backups

---

## Backup

### Ce qui est sauvegardé

| Quoi | Outil | Fréquence | Destination | Rétention |
|------|-------|-----------|-------------|-----------|
| Manifests k8s + snapshots PVC | Velero CSI | Quotidien 2h | `s3://.../velero/` | 7 jours |
| Données Loki (logs) | CronJob aws-cli | Horaire | `s3://.../loki/` | Illimité |
| Snapshots Longhorn | Longhorn → S3 | Via Velero | `s3://.../longhorn/` | 7 jours |

### Déclencher un backup manuel

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
  snapshotVolumes: true
  volumeSnapshotLocations:
    - csi
EOF
```

### Restaurer

```bash
velero restore create --from-backup NOM_DU_BACKUP
```

---

## Structure du repo

```
ansible/
  inventory/
    hosts.yml                   # master (clé SSH) + worker (vault)
    group_vars/all/vault.yml    # secrets chiffrés (gitignored en clair)
  playbooks/
    01-bootstrap.yml            # hardening OS + déploiement clé SSH
    02-k3s.yml                  # installation k3s master + worker
  longhorn-prereqs.yml          # prérequis Longhorn (iscsi, nfs-common)
  roles/
    common/                     # hardening, UFW, packages
    k3s_master/                 # install k3s server
    k3s_worker/                 # install k3s agent
    longhorn_prereqs/           # modules kernel + packages requis

kubernetes/
  system/
    traefik/                    # ingress + Let's Encrypt
    monitoring/                 # prometheus, grafana, loki, promtail
    longhorn/                   # storage distribué + backup target S3
    velero/                     # backup k8s + CSI snapshots

terraform/
  aws/                          # S3 bucket + IAM user velero

docs/
  architecture.md
```

---

## Secrets requis

| Variable | Usage |
|----------|-------|
| `vault_worker_ssh_pass` | Ansible Vault — mot de passe SSH worker |
| `VELERO_ACCESS_KEY_ID` | Env var — clé AWS pour Velero + Longhorn |
| `VELERO_SECRET_ACCESS_KEY` | Env var — secret AWS pour Velero + Longhorn |

Les credentials AWS sont issus du Terraform output (`terraform output velero_access_key_id`).
