# Points de sécurité restants — Cluster afflair.app
**Dernière mise à jour : 31 mai 2026**

---

## 🟠 Priorité moyenne — Isolation Kubernetes

### 1. NetworkPolicies — namespaces infrastructure restants
- **Namespaces couverts ✅ :** `times-server`, `times-server-staging`, `trivyhub`
- **Namespaces restants :** `monitoring`, `falco`, `crowdsec`, `velero`, `longhorn-system`
- **Note :** Les namespaces infrastructure sont plus complexes — risque de casser les communications internes

### 2. Pods privileged non audités régulièrement
- **Pods concernés :** Falco, Longhorn (instance-manager, engine-image, csi-plugin), SonarQube init
- **Problème :** Mode privileged nécessaire techniquement mais surface d'attaque élevée
- **Risque :** CVE dans ces images = compromission node complète
- **Solution :** Vérifier les rapports Trivy Operator activement, mettre en place des alertes CVE critiques

### 3. Pas de Pod Security Standards (PSS)
- **Problème :** Aucune politique PSS définie sur les namespaces
- **Risque :** N'importe quel pod peut demander des capabilities élevées sans restriction cluster
- **Solution :** Appliquer les profils PSS `restricted` ou `baseline` sur les namespaces applicatifs

---


## ✅ Réglé aujourd'hui (31 mai 2026)

| Élément | Solution |
|---------|---------|
| Clé bouncer CrowdSec en clair | Migré vers SealedSecret |
| `longhorn-support-bundle` cluster-admin | Role dédié lecture seule |
| `velero-server` cluster-admin | Role minimal backup/restore |
| multipath-tools | Supprimé — causait les bugs Longhorn |
| Bug Longhorn mount fantôme | Fix Ansible — umount globalmounts orphelins avant k3s |
| Alertes dégradations ArgoCD | ArgoCD Notifications configuré → Discord (15 apps) |
| Alertes CVE Trivy | ServiceMonitor + PrometheusRules CRITICAL/HIGH |
| Résultats kube-bench | Push vers Loki après chaque audit |
| fail2ban | Supprimé — remplacé par CrowdSec |
| modemmanager, caddy, fwupd, udisks2, apport, pollinate | Supprimés |
| CPUThrottlingHigh spam Discord | Silencé dans Alertmanager |
| Falco CPU throttling | Limit augmentée à 1 CPU |

---

## ✅ Déjà couvert (sessions précédentes)

| Élément | Solution en place |
|---------|------------------|
| SSH exposé | Restreint aux 3 IPs de gestion |
| API Kubernetes (6443) exposée | Restreint aux 3 IPs de gestion |
| Kubelet (10250) exposé | Restreint aux 3 IPs de gestion |
| Node Exporter (9100) exposé | Restreint aux 3 IPs de gestion |
| Services web sans auth | Authelia SSO sur tous les endpoints |
| Longhorn sans auth | IngressRoute + Authelia |
| ArgoCD sans auth Traefik | Middleware Authelia ajouté |
| Runtime security | Falco + alertes Discord temps réel |
| Protection réseau HTTP | CrowdSec + bouncer Traefik (50+ scénarios) |
| Hardening CIS nodes | kube-bench 0 FAIL (16 PASS) |
| Audit hebdomadaire nodes | Lynis chaque dimanche 3h |
| Secrets Kubernetes | Sealed Secrets chiffré |
| TLS | Let's Encrypt sur tous les endpoints |
| Scan CVE images | Trivy Operator en continu |
| coturn supprimé | Ports 3478/5349 fermés |
| rpcbind supprimé | Port 111 fermé |
| wazuh-agent supprimé | Remplacé par Falco/CrowdSec |
