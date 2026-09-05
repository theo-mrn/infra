# infra

Provisioning de l'infrastructure physique du cluster k3s — 3 VPS Hostinger
(Ubuntu 24.04 LTS, Paris).

| Nœud | IP | Rôle |
|------|----|------|
| master | 76.13.44.160 | control-plane |
| worker | 217.65.146.24 | workloads |
| worker2 | 179.198.197.71 | workloads |

DNS : `cluster.afflair.app` + `*.cluster.afflair.app` → 76.13.44.160

Ce repo couvre uniquement l'infra physique : provisioning des nœuds (Ansible),
hardening OS, réseau. **L'état désiré du cluster Kubernetes** (Applications
ArgoCD, NetworkPolicies, SealedSecrets...) vit dans un repo séparé :
[theo-mrn/argocd_registry](https://github.com/theo-mrn/argocd_registry) —
c'est volontaire : ces deux préoccupations ont des cycles de vie très
différents (l'infra physique change rarement, les manifests Kubernetes
évoluent à chaque nouvelle app ou bump de version).

---

## Prérequis locaux

```bash
brew install ansible kubectl kubeseal
```

---

## Installation from scratch

> L'ordre est important. Chaque étape dépend de la précédente.

### 1. Secrets Ansible Vault

```bash
ansible-vault create ansible/inventory/group_vars/all/vault.yml
# → ajouter : vault_worker_ssh_pass: "MOT_DE_PASSE_SSH_WORKER(S)"

echo "TON_VAULT_PASSWORD" > .vault_pass
chmod 600 .vault_pass
```

### 2. Bootstrap OS (hardening + clé SSH)

```bash
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass
```

Après ce step, les workers acceptent la clé SSH — plus besoin de mot de passe.

Pour n'agir que sur un nœud précis (ex: après ajout d'un nouveau worker) :
```bash
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit worker3
```

### 3. Installer k3s

```bash
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass
# → génère ansible/kubeconfig.yml (le provisioner local-path est inclus par défaut)
export KUBECONFIG=./ansible/kubeconfig.yml
```

### 4. ArgoCD (bootstrap GitOps — seul composant Kubernetes installé depuis ce repo)

ArgoCD ne peut pas se déployer lui-même, donc c'est le seul composant installé
manuellement depuis ce repo. Le manifest vit dans
[argocd_registry](https://github.com/theo-mrn/argocd_registry) :

```bash
git clone https://github.com/theo-mrn/argocd_registry.git
bash argocd_registry/kubernetes/system/argocd/install.sh
```

### 5. Déployer tout le reste

```bash
kubectl apply -f argocd_registry/kubernetes/system/argocd/apps/
```

ArgoCD prend le relais et déploie tout : Traefik, Authelia (SSO), sealed-secrets,
CNPG, trivy-operator, SonarQube, Jenkins, monitoring (kube-prometheus-stack,
Loki, Promtail), CrowdSec, et les applications (beacon, trivyhub...).

Voir le README de `argocd_registry` pour le détail des Applications et leur
ordre de dépendance.

---

## Ajouter un nouveau nœud

```bash
# 1. Ajouter le nœud dans ansible/inventory/hosts.yml (masters ou workers)
#    management_ips (firewall) se met à jour automatiquement — rien d'autre à toucher.

# 2. Bootstrap + join
ansible-playbook ansible/playbooks/01-bootstrap.yml --vault-password-file .vault_pass --limit <nom-du-noeud>
ansible-playbook ansible/playbooks/02-k3s.yml --vault-password-file .vault_pass --limit <nom-du-noeud>
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
| ArgoCD | https://argocd.cluster.afflair.app | Authelia (OIDC) |
| Grafana | https://grafana.cluster.afflair.app | Authelia (OIDC) |
| Jenkins | https://jenkins.cluster.afflair.app | Authelia (OIDC) |
| Traefik | https://traefik.cluster.afflair.app | Authelia |
| Beacon | https://beacon.cluster.afflair.app | Authelia |
| SonarQube | https://sonarqube.cluster.afflair.app | Authelia + compte SonarQube (pas d'OIDC en Community Edition) |

---

## Stack (résumé — détail dans `argocd_registry`)

- **k3s** — Kubernetes léger, Flannel VXLAN overlay, sans kube-proxy
- **ArgoCD** — GitOps, ~20 Applications déployées depuis `argocd_registry`
- **Traefik v3** + Let's Encrypt (httpChallenge)
- **Authelia** — SSO OIDC (Grafana, ArgoCD, Jenkins)
- **CrowdSec** — WAF + bouncer Traefik
- **Trivy Operator** — scan CVE continu
- **kube-prometheus-stack + Loki + Promtail** — monitoring et logs
- **CloudNativePG** — PostgreSQL
- **Sealed Secrets** — chiffrement asymétrique des secrets Kubernetes

> **Aucun backup automatisé n'est actuellement en place** (Velero retiré,
> voir `docs/security-todo.md`). Falco a également été retiré (incompatibilité
> avec containerd, voir `docs/architecture.md`).

---

## Secrets requis

| Variable | Usage | Source |
|----------|-------|--------|
| `vault_worker_ssh_pass` | Ansible Vault — mot de passe SSH des workers | manuel |

---

## Structure du repo

```
ansible/
  inventory/
    hosts.yml                       # master + worker(s)
    group_vars/all/main.yml         # management_ips calculée dynamiquement
    group_vars/all/vault.yml        # secrets chiffrés ansible-vault (gitignored)
  playbooks/
    01-bootstrap.yml                # hardening OS + déploiement clé SSH
    02-k3s.yml                      # installation k3s master + workers
    03-cis-hardening.yml            # contrôles CIS Level 1
    04-kube-bench.yml               # audit CIS k3s
    05-firewall-hardening.yml       # règles UFW par nœud
  roles/
    common/                         # hardening, UFW, packages
    cis_hardening/                  # contrôles CIS Level 1
    k3s_master/                     # install k3s server
    k3s_worker/                     # install k3s agent

docs/
  architecture.md                   # stack, SSO, fichiers sensibles
  security-todo.md                  # points de sécurité ouverts
  network-exposure.yml              # matrice firewall + services exposés
  disaster-recovery.md              # procédures de restauration
```

Manifests Kubernetes (Applications ArgoCD, NetworkPolicies, SealedSecrets) :
voir [theo-mrn/argocd_registry](https://github.com/theo-mrn/argocd_registry).
