# Architecture

## Cluster

| Rôle | IP | OS | Auth SSH |
|------|----|----|----------|
| master | 76.13.44.160 | Ubuntu 24.04 LTS | clé SSH |
| worker | 217.65.146.24 | Ubuntu 24.04 LTS | mot de passe → clé SSH après bootstrap |

DNS : `cluster.afflair.app` + `*.cluster.afflair.app` → 76.13.44.160

## Stack

| Couche | Composant | Namespace |
|--------|-----------|-----------|
| Kubernetes | k3s (Flannel VXLAN, sans kube-proxy) | — |
| Ingress | Traefik v3 + Let's Encrypt (httpChallenge) | `traefik` |
| Auth | Authelia SSO (OIDC + Redis) | `authelia` |
| Storage | Longhorn (réplication 2x, backup S3) | `longhorn-system` |
| GitOps | ArgoCD (12 applications) | `argocd` |
| Monitoring | kube-prometheus-stack + Loki + Promtail | `monitoring` |
| Backup | Velero (quotidien 2h) + CronJob Loki → S3 | `velero` |
| Sécurité runtime | Falco (syscall) + CrowdSec (WAF) | `falco` / `crowdsec` |
| Scan CVE | Trivy Operator | `trivy-system` |
| PostgreSQL | CloudNativePG | `cnpg-system` |
| Secrets | Sealed Secrets (kubeseal) | `sealed-secrets` |
| Qualité code | SonarQube | `sonarqube` |

## Applications déployées

| App | Namespace | Exposition |
|-----|-----------|------------|
| times-server (prod) | `times-server` | api.afflair.app |
| times-server (staging) | `times-server-staging` | stag.api.afflair.app |
| beacon | `beacon` | beacon.cluster.afflair.app |
| trivy-dashboard-web | `trivyhub` | trivyhub.cluster.afflair.app |
| trivyhub-landing | `trivyhub-landing` | www.trivyhub.fr |
| sonarqube | `sonarqube` | sonarqube.cluster.afflair.app |

## Ordre de déploiement

```
1. terraform/aws/          → S3 bucket + IAM user (velero credentials)
2. ansible 01-bootstrap    → hardening OS, UFW, clé SSH worker
3. ansible 02-k3s          → installe k3s master + worker, génère kubeconfig.yml
4. ansible longhorn-prereqs → modules kernel iscsi/nfs
5. traefik install.sh      → ingress controller
6. sealed-secrets install.sh → opérateur kubeseal
7. authelia install.sh     → SSO (dépend de Traefik)
8. longhorn install.sh     → storage (dépend des prérequis Ansible)
9. velero install.sh       → backup (dépend de Longhorn + S3)
10. argocd install.sh      → GitOps (déploie tout le reste)
```

> **Note** : monitoring, Falco, CrowdSec, Trivy et les applications sont déployés
> automatiquement par ArgoCD à l'étape 10. Il n'y a pas de script install.sh pour ces composants.

## Sécurité

- **Hardening OS** : CIS Level 1 (kube-bench 0 FAIL), playbooks Ansible
- **UFW** : SSH/API restreints aux 3 IPs de gestion ; seuls 80/443 sont publics
- **TLS** : Let's Encrypt sur tous les endpoints via Traefik
- **SSO** : Authelia en middleware Traefik sur tous les services internes
- **Secrets** : Sealed Secrets chiffrés asymétriquement (kubeseal)
- **Runtime** : Falco → alertes Discord temps réel
- **WAF** : CrowdSec bouncer Traefik (50+ scénarios)
- **CVE** : Trivy Operator en continu, alertes Prometheus CRITICAL/HIGH
- **Audit** : Lynis hebdomadaire (dimanche 3h), kube-bench post-install

## Backup

| Quoi | Outil | Fréquence | Destination | Rétention |
|------|-------|-----------|-------------|-----------|
| Manifests k8s + snapshots PVC | Velero CSI | Quotidien 2h | `s3://.../velero/` | 7 jours |
| Données Loki | CronJob aws-cli | Horaire | `s3://.../loki/` | Illimité |
| Snapshots Longhorn | Longhorn → S3 | Via Velero | `s3://.../longhorn/` | 7 jours |

Bucket S3 : `velero-k3s-cluster-backup` (eu-west-3) — chiffrement AES256, versioning activé.

## Fichiers sensibles

| Fichier | Statut | Usage |
|---------|--------|-------|
| `ansible/kubeconfig.yml` | gitignored — généré étape 3 | accès kubectl |
| `ansible/inventory/group_vars/all/vault.yml` | chiffré ansible-vault | mot de passe SSH worker |
| `.vault_pass` | gitignored | déchiffrement ansible-vault |
| `kubernetes/system/sealed-secrets/pub-cert.pem` | commité (public) | chiffrement kubeseal |
| Clé privée sealed-secrets | sur le master `/etc/sealed-secrets/` | **à sauvegarder manuellement** |

> La clé privée sealed-secrets n'est pas sauvegardée par Velero. En cas de perte du nœud master,
> tous les SealedSecrets deviennent irrécupérables. Voir `docs/disaster-recovery.md`.
