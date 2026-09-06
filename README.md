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

La migration est volontairement découpée. **Seule l'étape 1 est faite** — elle
est purement additive : elle ajoute une interface réseau sur les nœuds et ne
change rien au comportement actuel du cluster.

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

### Étape 2 — firewall sur le tailnet (à faire)

Remplacer `personal_management_ip` (IP résidentielle codée en dur dans
`inventory/group_vars/all/main.yml`) par la plage CGNAT Tailscale
`100.64.0.0/10` dans `05-firewall-hardening.yml`.

Bénéfice immédiat : si le FAI change l'IP du poste, l'accès SSH et k3s n'est
plus perdu.

### Étape 3 — fermer les services admin (à faire)

Bascule des IngressRoutes admin sur un entrypoint Traefik lié à l'IP tailnet.
Se fait dans le repo GitOps [argocd_registry](https://github.com/theo-mrn/argocd_registry),
pas ici.

Points d'attention identifiés lors de l'analyse :

- **Ne pas fermer le port 80.** Traefik utilise le `httpChallenge` Let's Encrypt
  (`apps/traefik.yml`). Si le port 80 devient injoignable depuis Internet, les
  certificats ne se renouvellent plus — et l'échec est silencieux pendant 90
  jours. Le DNS-01 n'est pas une option simple : la zone `afflair.app` est sur
  les NS par défaut Hostinger (`dns-parking.com`), pour lesquels lego n'a pas
  de provider.
- **Jenkins et n8n reçoivent des webhooks entrants** (cf. les règles `bypass`
  sur `^/github-webhook/` et `^/webhook/` dans `apps/authelia.yml`). Ces
  chemins doivent rester publics ; seule l'UI passe en privé.
- **Authelia peut être fermé** malgré son rôle d'IdP OIDC : ses 4 clients
  (Grafana, ArgoCD, MinIO, Jenkins) fonctionnent par redirection navigateur,
  pas par appel serveur-à-serveur. Un navigateur sur le tailnet joint `auth.`
  par le même chemin.
- **Traefik est en `type: LoadBalancer`** (ServiceLB k3s) et écoute sur toutes
  les interfaces. Un entrypoint réellement limité au tailnet demande un Service
  dédié lié à l'IP `100.x`, pas juste une ligne de config.

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
