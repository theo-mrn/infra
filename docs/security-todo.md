# Points de sécurité restants — Cluster afflair.app
**Date : 30 mai 2026**

---

## 🔴 Priorité haute — Sécurité

### 1. Clé bouncer CrowdSec en clair dans le repo Git
- **Fichier :** `kubernetes/system/argocd/apps/crowdsec.yml`
- **Problème :** La clé API du bouncer Traefik est stockée en clair dans le repo
- **Risque :** Si le repo est compromis ou rendu public, la clé est exposée
- **Solution :** Migrer vers un SealedSecret

### 2. ServiceAccount `longhorn-support-bundle` avec `cluster-admin`
- **Problème :** Droits cluster-admin pour un usage limité (génération de bundles de support)
- **Risque :** Compromission du pod = accès total au cluster
- **Solution :** Créer un Role dédié avec les permissions minimales nécessaires

### 3. ServiceAccount `velero-server` avec `cluster-admin`
- **Problème :** Velero a `cluster-admin` par défaut
- **Risque :** Compromission du pod Velero = accès total au cluster
- **Solution :** Restreindre aux permissions strictement nécessaires pour les backups

---

## 🟠 Priorité moyenne — Isolation Kubernetes

### 4. Aucune NetworkPolicy sur la majorité des namespaces
- **Namespaces concernés :** `monitoring`, `times-server`, `times-server-staging`, `trivyhub`, `falco`, `crowdsec`, `velero`, `longhorn-system`
- **Problème :** Tout pod peut communiquer librement avec n'importe quel autre service
- **Risque :** Un container compromis peut atteindre les bases de données, secrets, APIs internes
- **Solution :** Définir des NetworkPolicies de type "deny all + allow explicit" par namespace

### 5. Pods privileged non audités régulièrement
- **Pods concernés :** Falco, Longhorn (instance-manager, engine-image, csi-plugin), SonarQube init
- **Problème :** Mode privileged nécessaire techniquement mais surface d'attaque élevée
- **Risque :** CVE dans ces images = compromission node complète
- **Solution :** Vérifier les rapports Trivy Operator activement, mettre en place des alertes CVE critiques

### 6. Pas de Pod Security Standards (PSS)
- **Problème :** Aucune politique PSS définie sur les namespaces
- **Risque :** N'importe quel pod peut demander des capabilities élevées sans restriction cluster
- **Solution :** Appliquer les profils PSS `restricted` ou `baseline` sur les namespaces applicatifs

---

## 🟡 Priorité normale — Backup et continuité

### 7. Backup staging non fonctionnel
- **Composant :** dbpilot WAL-G sur `times-server-staging`
- **Problème :** Jobs en erreur depuis plusieurs jours (`No backups found`)
- **Risque :** Aucune sauvegarde de la base de données staging
- **Solution :** Investiguer la configuration WAL-G en staging

### 8. Bug Longhorn — mount fantôme récurrent
- **Problème :** À chaque reboot du worker, les PVCs Longhorn se retrouvent en état de mount orphelin
- **Impact :** Intervention manuelle requise (reboot node ou fsck) pour récupérer les pods
- **Solution :** Ajouter un task Ansible dans `03-cis-hardening.yml` pour nettoyer les globalmounts orphelins avant le démarrage de k3s-agent

---

## 🟡 Priorité normale — Observabilité

### 9. Pas d'alerte sur les CVEs Trivy
- **Problème :** Trivy Operator scanne les images mais aucune alerte n'est configurée
- **Risque :** Des vulnérabilités critiques peuvent passer inaperçues
- **Solution :** Créer des PrometheusRules sur les métriques Trivy pour alerter sur les CVEs CRITICAL

### 10. Résultats kube-bench non centralisés
- **Problème :** Résultats sauvegardés localement (`/tmp/` et `/var/log/`) — pas dans Loki/Grafana
- **Solution :** Ajouter une tâche Ansible pour envoyer les résultats dans Loki ou les archiver dans le repo

### 11. Pas d'alerte sur les dégradations ArgoCD
- **Problème :** Si une Application ArgoCD passe en `OutOfSync` ou `Degraded`, aucune notification n'est envoyée
- **Solution :** Configurer les notifications ArgoCD vers Discord via le chart ArgoCD Notifications

---

## ✅ Déjà couvert

| Élément | Solution en place |
|---------|------------------|
| SSH exposé | Restreint aux 3 IPs de gestion |
| API Kubernetes exposée | Restreint aux 3 IPs de gestion |
| Kubelet exposé | Restreint aux 3 IPs de gestion |
| Services web sans auth | Authelia SSO sur tous les endpoints |
| Longhorn sans auth | Corrigé — IngressRoute + Authelia |
| ArgoCD sans auth Traefik | Corrigé — middleware Authelia ajouté |
| Runtime security | Falco + alertes Discord temps réel |
| Protection réseau HTTP | CrowdSec + bouncer Traefik (50+ scénarios) |
| Hardening CIS nodes | kube-bench 0 FAIL (16 PASS) |
| Audit hebdomadaire nodes | Lynis chaque dimanche 3h |
| Secrets Kubernetes | Sealed Secrets chiffré |
| TLS | Let's Encrypt sur tous les endpoints |
| Scan CVE images | Trivy Operator en continu |
| coturn supprimé | Ports 3478/5349 fermés |
| rpcbind désactivé | Port 111 fermé |
