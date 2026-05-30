# Rapport de sécurité — Cluster afflair.app
**Date : 30 mai 2026**  
**Rédigé par : Claude (Anthropic) avec Theo Morin**

---

## 1. Contexte

Migration de Wazuh vers une stack de sécurité moderne plus légère et mieux intégrée à Kubernetes. Hardening complet de la surface d'attaque réseau et des nodes k3s.

---

## 2. Stack de sécurité déployée

### 2.1 Falco — Runtime Security
Falco intercepte les syscalls Linux via eBPF (modern_ebpf) et détecte les comportements suspects en temps réel dans les containers et sur les nodes.

**Déploiement :** DaemonSet sur master et worker via ArgoCD (chart falcosecurity/falco)  
**Alerting :** Falcosidekick → Loki (stockage) + Discord (notifications temps réel, priorité Warning et plus)  
**Dashboard :** Grafana "Falco Security Events" avec statistiques par priorité, top règles, flux de logs  
**Règles custom :** Whitelist des faux positifs légitimes (ArgoCD, systemd-executor)

### 2.2 CrowdSec — Protection réseau
CrowdSec analyse les logs Traefik et système pour détecter les attaques réseau et bloquer les IPs malveillantes.

**Déploiement :** LAPI + 2 agents (un par node) + bouncer Traefik via ArgoCD  
**Collections actives :**
- `crowdsecurity/traefik` — protection HTTP (SQLi, XSS, path traversal, bad user-agent, CVEs...)
- `crowdsecurity/linux` — protection système
- `crowdsecurity/sshd` — brute-force SSH
- `crowdsecurity/http-cve` — 30+ CVEs HTTP critiques

**Bouncer :** Traefik CrowdSec Bouncer actif — les IPs bannies sont bloquées avant d'atteindre les applications

### 2.3 Lynis — Audit hardening
Audit de conformité CIS hebdomadaire des nodes Linux.

**Déploiement :** CronJob Kubernetes, chaque dimanche à 3h  
**Périmètre :** Configuration SSH, permissions fichiers, services, paramètres kernel, conformité CIS

### 2.4 kube-bench — Audit CIS Kubernetes
Audit de conformité CIS Kubernetes Benchmark directement sur les nodes.

**Déploiement :** Playbook Ansible `04-kube-bench.yml`, exécution manuelle  
**Résultats obtenus :** 0 FAIL (16 PASS) sur master et worker après hardening

---

## 3. Hardening CIS Kubernetes (kube-bench)

### Avant
- 8 checks FAIL sur la section node (section 4)

### Corrections apportées (playbook `03-cis-hardening.yml`)

| Check | Correction |
|-------|-----------|
| 4.1.3 / 4.1.4 | Permissions kubeproxy.kubeconfig → 600 root:root |
| 4.1.5 / 4.1.6 | Permissions kubelet.kubeconfig et k3s.yaml → 600 root:root |
| 4.1.7 / 4.1.8 | Permissions certificats CA → 600 root:root |
| 4.2.1 | anonymous-auth=false ajouté aux kubelet-args |
| 4.2.2 | authorization-mode=Webhook ajouté aux kubelet-args |
| 4.2.3 | client-ca-file configuré dans kubelet-args |
| 4.2.6 | protect-kernel-defaults=true dans config k3s + sysctl |
| 4.2.10 | tls-cert-file et tls-private-key-file configurés |

### Après
**16 PASS — 0 FAIL** sur master et worker

---

## 4. Réduction de la surface d'attaque réseau

### 4.1 Ports restreints

| Port | Service | Avant | Après |
|------|---------|-------|-------|
| 22/tcp | SSH | Internet | 3 IPs de gestion uniquement |
| 6443/tcp | API Kubernetes | Internet | 3 IPs de gestion uniquement |
| 10250/tcp | Kubelet | Internet | 3 IPs de gestion uniquement |
| 9100/tcp | Node Exporter | Internet | 3 IPs de gestion uniquement |

**IPs de gestion autorisées :**
- `37.71.179.238` — IP de gestion Theo
- `217.65.146.24` — Worker node
- `76.13.44.160` — Master node

### 4.2 Services supprimés

| Service | Ports | Raison |
|---------|-------|--------|
| coturn | 3478, 5349 | Serveur STUN/TURN inutilisé |
| rpcbind | 111 | Service RPC inutile sur k3s |

### 4.3 État final des ports exposés

**Master (76.13.44.160)**

| Port | Service | Accès |
|------|---------|-------|
| 22/tcp | SSH | Restreint — 3 IPs |
| 80/tcp | Traefik HTTP | Public — redirect HTTPS |
| 443/tcp | Traefik HTTPS | Public — apps via Authelia |
| 6443/tcp | API Kubernetes | Restreint — 3 IPs |
| 8472/udp | Flannel VXLAN | Public — trafic overlay chiffré |
| 9100/tcp | Node Exporter | Bloqué — UFW deny |
| 9345/tcp | k3s supervisor | Restreint — worker uniquement |
| 10250/tcp | Kubelet | Restreint — 3 IPs |

**Worker (217.65.146.24)**

| Port | Service | Accès |
|------|---------|-------|
| 22/tcp | SSH | Restreint — 3 IPs |
| 80/tcp | Traefik HTTP | Public — redirect HTTPS |
| 443/tcp | Traefik HTTPS | Public — apps via Authelia |
| 8472/udp | Flannel VXLAN | Public — trafic overlay chiffré |
| 9100/tcp | Node Exporter | Restreint — 3 IPs |
| 10250/tcp | Kubelet | Restreint — 3 IPs |

---

## 5. Services exposés via Traefik (port 443)

| Hostname | Namespace | Auth | Type | Notes |
|----------|-----------|------|------|-------|
| auth.cluster.afflair.app | authelia | — | Infrastructure | Point d'entrée SSO |
| argocd.cluster.afflair.app | argocd | Authelia + ArgoCD natif | Infrastructure | Double auth |
| grafana.cluster.afflair.app | monitoring | Authelia | Infrastructure | |
| longhorn.cluster.afflair.app | longhorn-system | Authelia | Infrastructure | Corrigé aujourd'hui — était sans auth |
| traefik.cluster.afflair.app | traefik | Authelia | Infrastructure | |
| sonarqube.cluster.afflair.app | sonarqube | Authelia | Application | |
| beacon.cluster.afflair.app | beacon | Authelia | Application | |
| trivyhub.cluster.afflair.app | trivyhub | Authelia | Application | |
| www.trivyhub.fr | trivyhub-landing | Aucune | Application | Landing page publique — intentionnel |
| api.afflair.app | times-server | Auth JWT applicative | API | Pas de middleware Traefik |
| stag.api.afflair.app | times-server-staging | Auth JWT applicative | API | Staging |

---

## 6. Monitoring et alerting

### 6.1 Stack monitoring (migrée vers ArgoCD)

| Composant | Version | Rôle |
|-----------|---------|------|
| kube-prometheus-stack | 85.x | Prometheus + Grafana + Alertmanager |
| Loki | 7.x | Agrégation de logs |
| Promtail | 6.x | Collecte de logs |

### 6.2 Alertes configurées

**Falco (via Alertmanager → Discord)**

| Alerte | Condition |
|--------|-----------|
| FalcoCriticalEvent | Tout event critical/emergency/alert |
| FalcoHighVolumeWarnings | +20 warnings en 10 minutes |
| FalcoSilenced | Aucun event depuis 15 minutes |

**Alertmanager → Discord**
- Toutes les alertes Kubernetes (CrashLoopBackOff, OOMKill, node down, etc.)
- Watchdog et InfoInhibitor silencés (heartbeats internes)
- repeat_interval : 24h pour éviter le spam

---

## 7. Points restants (TODO)

| Priorité | Action |
|----------|--------|
| Moyenne | Migrer la clé bouncer CrowdSec vers un SealedSecret (actuellement en clair dans le repo) |
| Moyenne | Ajouter des NetworkPolicies sur les namespaces monitoring, times-server, trivyhub, falco, crowdsec |
| Faible | Restreindre le ClusterRole cluster-admin de longhorn-support-bundle et velero-server |

---

## 8. Architecture GitOps

Toute la configuration est versionnée dans le repo Git et gérée par ArgoCD.  
Aucun `kubectl apply` manuel n'est nécessaire pour les opérations courantes.

**Applications ArgoCD actives :**
- `kube-prometheus-stack`, `loki`, `promtail`, `monitoring-extras`
- `falco`, `falco-rules`
- `crowdsec`, `crowdsec-traefik-bouncer`, `crowdsec-secrets`
- `lynis`
- `kube-bench` (supprimé — remplacé par playbook Ansible)

**Playbooks Ansible :**
- `01-bootstrap.yml` — Initialisation OS
- `02-k3s.yml` — Installation k3s
- `03-cis-hardening.yml` — Hardening CIS nodes
- `04-kube-bench.yml` — Audit CIS Kubernetes
- `05-firewall-hardening.yml` — Restriction ports UFW
