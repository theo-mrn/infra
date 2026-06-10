# Sécurité — points ouverts

## Priorité haute

### Backup clé privée Sealed Secrets
La clé privée sealed-secrets réside uniquement sur le nœud master (`/etc/sealed-secrets/`).
Si le master est perdu sans backup de cette clé, tous les SealedSecrets du repo sont irrécupérables.

**Action** : exporter et stocker la clé dans un gestionnaire de secrets hors-cluster (ex. Bitwarden, 1Password).
```bash
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
# Stocker ce fichier HORS du repo git
```

---

## Priorité moyenne

### NetworkPolicies — namespaces infrastructure restants
- **Couverts ✅** : `times-server`, `times-server-staging`, `trivyhub`, `monitoring`
- **Restants** : `falco`, `crowdsec`, `velero`

Les namespaces infra sont volontairement laissés en dernier — risque de casser les communications internes entre composants (ex. Prometheus → node-exporter, Loki scraping).

### Pod Security Standards (PSS)
Aucune politique PSS sur les namespaces. N'importe quel pod peut demander des capabilities élevées.

**Action** : appliquer `baseline` sur les namespaces applicatifs (`times-server`, `trivyhub`, `beacon`).
Les namespaces système (Falco) nécessitent `privileged` — ne pas restreindre.

### Pods privileged non audités régulièrement
Falco et SonarQube init tournent en mode privileged.
Trivy Operator alerte déjà sur les CVE critiques/hautes — vérifier activement ces rapports.

---

## Suivi

Voir `docs/architecture.md` pour l'état complet du cluster.
Voir `docs/disaster-recovery.md` pour les procédures de restauration.
