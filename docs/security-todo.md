# Sécurité — points ouverts

## Priorité haute

### Backup clé privée Sealed Secrets
La clé privée sealed-secrets réside uniquement dans le cluster (namespace `kube-system`,
secrets `sealed-secrets-key*`). Si le cluster est perdu sans backup de cette clé, tous
les SealedSecrets du repo sont irrécupérables. Voir `docs/disaster-recovery.md` §1.

**Action** : exporter et stocker la clé dans un gestionnaire de secrets hors-cluster (ex. Bitwarden, 1Password).
```bash
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
# Stocker ce fichier HORS du repo git
```

### Backup automatisé absent
Velero a été retiré du cluster (2026-09, bucket S3 supprimé) — aucune solution de backup
n'est actuellement en place pour les données applicatives (PVC, bases de données).

**Action** : remettre en place Velero (ou alternative) avec un nouveau bucket S3 dont le
backend Terraform est **séparé** du bucket de backup lui-même (l'ancienne config stockait
le state Terraform dans le bucket qu'il gérait — auto-référence qui a causé la perte du
state lors de la suppression manuelle du bucket).

---

## Priorité moyenne

### NetworkPolicies — namespaces infrastructure restants
- **Couverts ✅** : `trivyhub`, `monitoring`, `crowdsec`, `sonarqube`, `authelia`, `argocd`
- **Restants** : `beacon`, `jenkins`, `traefik`, `cnpg-system`, `trivy-system`

Les namespaces infra sont volontairement laissés en dernier — risque de casser les communications internes entre composants (ex. Prometheus → node-exporter, Loki scraping).

### Pod Security Standards (PSS)
Aucune politique PSS sur les namespaces. N'importe quel pod peut demander des capabilities élevées.

**Action** : appliquer `baseline` sur les namespaces applicatifs (`beacon`, `trivyhub`, `sonarqube`).

### Pods privileged non audités régulièrement
SonarQube init (sysctl) tourne en mode privileged.
Trivy Operator alerte déjà sur les CVE critiques/hautes — vérifier activement ces rapports.

### Falco retiré (détection runtime)
Falco a été retiré du cluster (2026-09) : son plugin `container` crashait de façon
récurrente (SIGSEGV, incompatibilité avec certaines versions de containerd), et le
désactiver empêchait le chargement des règles de détection standard — plus aucune
détection réelle n'aurait été en place. Aucun outil de détection runtime par syscall
n'est actuellement déployé. À réévaluer (nouvelle version de Falco, ou alternative)
si ce type de détection est requis.

---

## Suivi

Voir `docs/architecture.md` pour l'état complet du cluster.
Voir `docs/disaster-recovery.md` pour les procédures de restauration.
