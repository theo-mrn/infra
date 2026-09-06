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

## Tailscale — accès privé au cluster

Objectif : joindre les services d'administration (ArgoCD, Grafana, Authelia,
Traefik dashboard...) via un réseau privé WireGuard plutôt qu'en les exposant
sur Internet.

La migration est terminée. Les interfaces d'administration ne répondent plus
qu'aux clients du tailnet ; les produits publics (`www.trivyhub.fr`, landings)
et les webhooks entrants restent joignables depuis Internet.

| Host | Accès |
|------|-------|
| `argocd` `grafana` `auth` `traefik` `reports` `sonarqube` | tailnet |
| `minio` (console) `s3` (API) | tailnet |
| `jenkins` `n8n` | UI : tailnet — chemins de webhook : publics |
| `www.trivyhub.fr`, landings | public |

Les ports 80 et 443 restent ouverts : le filtrage est applicatif (middleware
Traefik), pas au niveau du firewall. C'est ce qui permet au challenge HTTP-01
de Let's Encrypt de continuer à renouveler les certificats.

### Étape 1 — installer Tailscale sur les nœuds ✅

```bash
# 1. Créer un compte sur https://tailscale.com (gratuit jusqu'à 100 machines)

# 2. Générer une clé d'auth RÉUTILISABLE (Settings → Keys → Generate auth key)
#    Cocher "Reusable". Optionnel : "Ephemeral" non, "Tags" → tag:k3s

# 3. L'ajouter au vault
ansible-vault edit ansible/inventory/group_vars/all/vault.yml --vault-password-file .vault_pass
# → vault_tailscale_authkey: "tskey-auth-xxxxx"

# 4. Installer sur les 3 nœuds
ansible-playbook ansible/playbooks/06-tailscale.yml --vault-password-file .vault_pass

# 5. Installer Tailscale sur ton poste, puis vérifier
tailscale status          # les 3 nœuds doivent apparaître
ssh root@<ip-100.x-du-master>
```

Rollback complet (désinstalle Tailscale, retour à l'état actuel) :

```bash
ansible-playbook ansible/playbooks/06-tailscale.yml --vault-password-file .vault_pass -e tailscale_state=absent
```

### Étape 2 — firewall restreint au tailnet ✅

`management_ips` (dans `inventory/group_vars/all/main.yml`) vaut désormais la
plage CGNAT `100.64.0.0/10` au lieu d'une IP résidentielle codée en dur.
SSH (22), l'API k3s (6443) et kubelet (10250) ne sont plus joignables depuis
Internet.

```bash
ansible-playbook ansible/playbooks/05-firewall-hardening.yml --vault-password-file .vault_pass
```

Conséquences, toutes gérées dans le code :

- `ansible_host` pointe sur les IP tailnet dans `inventory/hosts.yml` ;
  `node_public_ip` conserve l'IP publique, nécessaire aux règles
  intra-cluster (k3s et Flannel communiquent sur les IP publiques).
- Le certificat de l'API k3s doit couvrir l'IP tailnet, sinon `kubectl` le
  rejette. Géré par `--tls-san` dans `/etc/rancher/k3s/config.yaml` :

```bash
ansible-playbook ansible/playbooks/02-k3s.yml --tags tls-san --limit master
ansible-playbook ansible/playbooks/02-k3s.yml --tags kubeconfig --limit master
```

### Étape 3 — services admin restreints au tailnet ✅

Faite dans le repo GitOps
[argocd_registry](https://github.com/theo-mrn/argocd_registry) : un middleware
Traefik `tailnet-only` (`ipAllowList`) est appliqué aux IngressRoutes
d'administration. Une requête venant d'Internet reçoit 403 avant d'atteindre
le service.

Deux prérequis découverts à l'application :

- **`externalTrafficPolicy: Local`** sur le Service Traefik. Sans lui, le SNAT
  du ServiceLB remplace l'IP cliente par celle du pod svclb (`10.42.x.x`) et
  le filtre ne distingue plus rien. Bénéfice annexe : CrowdSec voit enfin les
  vraies IP au lieu d'adresses internes.
- **Coolify a dû être supprimé** (`playbooks/07-remove-coolify.yml`). Installé
  hors IaC sur le master, son proxy Traefik occupait 0.0.0.0:80 et :443 sans
  rien router, ce qui empêchait le ServiceLB k3s de servir ces ports sur l'IP
  Tailscale. Données archivées dans `/root/coolify-backup` sur le nœud.

Jenkins et n8n sont scindés en deux IngressRoutes : les chemins de webhook
restent publics (GitHub et les services tiers ne savent pas s'authentifier),
l'interface passe en privé. Ces chemins étaient déjà en `bypass` Authelia,
donc déjà ouverts — mais servis par la même route que l'UI.

### Accès depuis un poste client — `/etc/hosts`

Le DNS public de `*.cluster.afflair.app` pointe vers l'IP publique du master.
Un navigateur, même avec Tailscale actif, sort donc par Internet et reçoit
403 : être sur le tailnet ne suffit pas, encore faut-il que le nom résolve
vers l'IP tailnet.

La solution retenue est un `/etc/hosts` sur chaque poste d'administration :

```
100.69.1.127  argocd.cluster.afflair.app
100.69.1.127  grafana.cluster.afflair.app
100.69.1.127  auth.cluster.afflair.app
100.69.1.127  sonarqube.cluster.afflair.app
100.69.1.127  traefik.cluster.afflair.app
100.69.1.127  minio.cluster.afflair.app
100.69.1.127  s3.cluster.afflair.app
100.69.1.127  reports.cluster.afflair.app
100.69.1.127  jenkins.cluster.afflair.app
100.69.1.127  n8n.cluster.afflair.app
```

**Pourquoi pas le split-DNS Tailscale** (Nameservers → Custom, restreint à
`cluster.afflair.app`) : il suppose un résolveur DNS joignable sur l'IP
tailnet du master. Il n'y en a pas — `systemd-resolved` n'écoute que sur
`127.0.0.53` et CoreDNS n'est accessible que depuis le cluster
(`10.43.0.10`). Vérifié : `dig @100.69.1.127` ne répond pas. Le configurer
tel quel casserait la résolution au lieu de l'améliorer.

L'exposer demanderait de publier un résolveur sur le tailnet — un service de
plus à maintenir, pour un bénéfice limité à un administrateur unique. À
reconsidérer si plusieurs personnes ou de nombreux appareils accèdent au
cluster.

Si l'accès échoue alors que la résolution est bonne (`dscacheutil -q host -a
name argocd.cluster.afflair.app`), c'est le navigateur qui réutilise une
connexion HTTP/2 vers l'ancienne IP : fenêtre privée, ou vider le cache DNS
du navigateur (`chrome://net-internals/#dns`).

### Reste à faire

- **Le tag `tag:k3s`** n'est pas activé : il doit d'abord être déclaré dans
  les `tagOwners` de l'ACL du tailnet. Sans lui, les clés des nœuds expirent
  (~6 mois) et il faut les ré-authentifier à la main. Une fois l'ACL en place :

```bash
ansible-playbook ansible/playbooks/06-tailscale.yml --vault-password-file .vault_pass -e tailscale_tags=tag:k3s
```

- **Rollback d'un service** : retirer le middleware `tailnet-only` de son
  IngressRoute dans `argocd_registry` et pousser.

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
| `vault_tailscale_authkey` | Clé d'auth réutilisable pour joindre le tailnet | [Tailscale admin → Keys](https://login.tailscale.com/admin/settings/keys) |

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
    06-tailscale.yml                # install Tailscale (accès privé)
  roles/
    common/                         # hardening, UFW, packages
    cis_hardening/                  # contrôles CIS Level 1
    k3s_master/                     # install k3s server
    k3s_worker/                     # install k3s agent
    tailscale/                      # install Tailscale + join tailnet

docs/
  architecture.md                   # stack, SSO, fichiers sensibles
  security-todo.md                  # points de sécurité ouverts
  network-exposure.yml              # matrice firewall + services exposés
  disaster-recovery.md              # procédures de restauration
```

Manifests Kubernetes (Applications ArgoCD, NetworkPolicies, SealedSecrets) :
voir [theo-mrn/argocd_registry](https://github.com/theo-mrn/argocd_registry).
