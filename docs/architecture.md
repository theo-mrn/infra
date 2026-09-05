# Architecture

## Cluster

| Rôle | IP | OS | Auth SSH |
|------|----|----|----------|
| master | 76.13.44.160 | Ubuntu 24.04 LTS | clé SSH |
| worker | 217.65.146.24 | Ubuntu 24.04 LTS | mot de passe → clé SSH après bootstrap |
| worker2 | 179.198.197.71 | Ubuntu 24.04 LTS | mot de passe → clé SSH après bootstrap |

DNS : `cluster.afflair.app` + `*.cluster.afflair.app` → 76.13.44.160

## Stack

Tous les composants système sont déployés via ArgoCD (Applications dans
`argocd_registry/kubernetes/system/argocd/apps/`) — plus aucune installation manuelle (`install.sh`)
n'est utilisée pour ces composants.

| Couche | Composant | Namespace |
|--------|-----------|-----------|
| Kubernetes | k3s (Flannel VXLAN, sans kube-proxy) | — |
| Ingress | Traefik v3 + Let's Encrypt (httpChallenge) | `traefik` |
| Auth | Authelia SSO (OIDC + Redis) | `authelia` |
| Storage | local-path (volumes locaux par nœud) | — |
| GitOps | ArgoCD (20 applications) | `argocd` |
| CI/CD | Jenkins (SSO Authelia) | `jenkins` |
| Monitoring | kube-prometheus-stack + Loki + Promtail | `monitoring` |
| Sécurité runtime | CrowdSec (WAF) | `crowdsec` |
| Scan CVE | Trivy Operator | `trivy-system` |
| PostgreSQL | CloudNativePG | `cnpg-system` |
| Secrets | Sealed Secrets (kubeseal) | `sealed-secrets` (controller dans `kube-system`) |
| Qualité code | SonarQube | `sonarqube` |

## SSO (Authelia OIDC)

Authelia sert de point d'entrée d'authentification unique (SSO) pour le cluster.
Deux mécanismes de protection coexistent :

- **Toutes les apps** sont protégées au niveau de l'ingress via le middleware Traefik
  `authelia` (forward-auth, policy `one_factor` par domaine dans `access_control`).
- **Certaines apps supportent en plus l'OIDC natif**, ce qui unifie leur propre
  système de comptes avec Authelia (plus de mot de passe applicatif séparé) :

| App | SSO OIDC | Note |
|-----|----------|------|
| Grafana | ✅ | `generic_oauth` |
| ArgoCD | ✅ | Dex intégré |
| Jenkins | ✅ | Plugin `oic-auth`, security realm manuelle (client_secret_post) |
| SonarQube | ❌ | Non supporté en Community Edition (fonctionnalité payante) |

Les secrets clients OIDC sont stockés en `SealedSecret` dans `argocd_registry`
(ex: `kubernetes/system/argocd/sealed-oidc-secret.yml`,
`kubernetes/system/jenkins/sealed-oidc-secret.yml`), jamais en clair dans un repo.

## Applications déployées

| App | Namespace | Exposition | GitOps |
|-----|-----------|------------|--------|
| beacon | `beacon` | beacon.cluster.afflair.app | ✅ ArgoCD |
| trivy-dashboard-web | `trivyhub` | trivyhub.cluster.afflair.app | ✅ ArgoCD |
| trivyhub-landing | `trivyhub-landing` | www.trivyhub.fr | ✅ ArgoCD |
| sonarqube | `sonarqube` | sonarqube.cluster.afflair.app | ✅ ArgoCD |

### Déploiements de test hors GitOps

Ces namespaces sont créés directement par des pipelines Jenkins (`kubectl apply`),
sans manifest versionné dans ce repo. À intégrer à ArgoCD si/quand ils deviennent
des projets pérennes :

- `test-kybers-staging`, `test-kybers-production`
- `test-image-production`
- `deza-production`

## Ordre de déploiement (nouveau cluster)

```
1. ansible 01-bootstrap    → hardening OS, UFW, clé SSH worker(s)
2. ansible 02-k3s          → installe k3s master + workers (local-path provisioner inclus), génère kubeconfig.yml
3. argocd_registry/kubernetes/system/argocd/install.sh → GitOps (bootstrap manuel one-shot, seul composant hors ArgoCD)
4. kubectl apply -f argocd_registry/kubernetes/system/argocd/apps/  → toutes les Applications (Traefik, Authelia,
   sealed-secrets, CNPG, trivy-operator, SonarQube, Jenkins, monitoring, CrowdSec, apps...)
```

> ArgoCD lui-même reste installé via `argocd_registry/kubernetes/system/argocd/install.sh` (manifest brut officiel) — c'est
> le seul composant "racine" nécessairement hors GitOps, puisqu'il ne peut pas se déployer
> lui-même. Tout le reste passe par des `Application` ArgoCD (`argocd_registry/kubernetes/system/argocd/apps/*.yml`).

## Sécurité

- **Hardening OS** : CIS Level 1 (kube-bench 0 FAIL), playbooks Ansible
- **UFW** : SSH/API restreints aux IPs de gestion (calculées dynamiquement depuis l'inventaire,
  voir `ansible/inventory/group_vars/all/main.yml`) ; seuls 80/443 sont publics
- **TLS** : Let's Encrypt sur tous les endpoints via Traefik
- **SSO** : Authelia en middleware Traefik sur tous les services internes, + OIDC natif
  sur Grafana/ArgoCD/Jenkins (voir section SSO)
- **Secrets** : Sealed Secrets chiffrés asymétriquement (kubeseal)
- **WAF** : CrowdSec bouncer Traefik (50+ scénarios)
- **CVE** : Trivy Operator en continu, alertes Prometheus CRITICAL/HIGH
- **Audit** : Lynis hebdomadaire (dimanche 3h), kube-bench post-install

> Falco (détection runtime par syscall) a été retiré du cluster (2026-09) : son plugin
> `container` crashait (SIGSEGV, incompatibilité connue avec certaines versions de
> containerd) et désactiver ce plugin cassait le chargement des règles standard. À
> réévaluer si une version compatible est publiée en amont.

## Backup

Velero a été retiré du cluster (2026-09, bucket S3 supprimé). **Aucune solution de
backup automatisé n'est actuellement en place.** À planifier si besoin.

## Fichiers sensibles

| Fichier | Statut | Usage |
|---------|--------|-------|
| `ansible/kubeconfig.yml` | gitignored — généré à l'étape k3s | accès kubectl |
| `ansible/inventory/group_vars/all/vault.yml` | chiffré ansible-vault | mot de passe SSH worker(s) |
| `.vault_pass` | gitignored | déchiffrement ansible-vault |
| `argocd_registry/kubernetes/system/sealed-secrets/pub-cert.pem` | commité (public) | chiffrement kubeseal |
| Clé privée sealed-secrets | dans le cluster (`kube-system`, secrets `sealed-secrets-key*`) | **à sauvegarder manuellement**, non couverte par un backup automatisé |

> La clé privée sealed-secrets n'est sauvegardée par aucun mécanisme automatisé (Velero
> retiré). En cas de perte du cluster, tous les SealedSecrets deviennent irrécupérables
> sans une sauvegarde manuelle préalable. Voir `docs/disaster-recovery.md`.
