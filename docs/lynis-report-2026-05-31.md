# Rapport Lynis — Audit hardening
**Date : 31 mai 2026**
**Version Lynis : 3.0.9**

---

## Scores

| Node | Score | Tests | Warnings | Suggestions |
|------|-------|-------|---------|------------|
| Node | Score initial | Score final | Suggestions initiales | Suggestions restantes |
|------|-------------|-------------|----------------------|----------------------|
| Master | 60/100 | **69/100** (+9) | 50 | 34 |
| Worker | 62/100 | **71/100** (+9) | 48 | 32 |

Aucun warning critique — uniquement des suggestions d'amélioration.

---

## Suggestions par catégorie

### 🔴 SSH — Priorité haute

| ID | Suggestion | Action |
|----|-----------|--------|
| SSH-7408 | `PermitRootLogin` → passer à `prohibit-password` | Clé SSH uniquement |
| SSH-7408 | `MaxAuthTries` → réduire de 6 à 3 | Limite brute-force |
| SSH-7408 | `MaxSessions` → réduire de 10 à 2 | Limite connexions |
| SSH-7408 | `LogLevel` → passer à `VERBOSE` | Meilleure traçabilité |
| SSH-7408 | `X11Forwarding` → désactiver | Inutile sur serveur |
| SSH-7408 | `AllowAgentForwarding` → désactiver | Inutile sur serveur |
| SSH-7408 | `AllowTcpForwarding` → désactiver | Inutile sur serveur |
| SSH-7408 | `GatewayPorts` → désactiver | Inutile sur serveur |
| SSH-7408 | `TCPKeepAlive` → désactiver | Remplacé par ClientAliveInterval |
| SSH-7408 | `ClientAliveCountMax` → réduire de 3 à 2 | Timeout sessions |
| SSH-7408 | `Port` → changer le port 22 | Réduire le scan automatique |

---

### 🟠 Authentification — Priorité moyenne

| ID | Suggestion |
|----|-----------|
| AUTH-9229 | Configurer les rounds PAM pour le hachage des mots de passe |
| AUTH-9230 | Configurer les rounds de hachage dans `/etc/login.defs` |
| AUTH-9262 | Installer un module PAM pour la force des mots de passe (pam_cracklib) |
| AUTH-9282 | Définir une date d'expiration pour les comptes avec mot de passe |
| AUTH-9284 | Supprimer ou désactiver les comptes verrouillés inutiles |
| AUTH-9286 | Configurer un âge minimum et maximum pour les mots de passe |
| AUTH-9328 | Durcir le umask par défaut → `027` dans `/etc/login.defs` |

---

### 🟠 Kernel / Système — Priorité moyenne

| ID | Suggestion |
|----|-----------|
| KRNL-5820 | Désactiver les core dumps dans `/etc/security/limits.conf` |
| KRNL-6000 | Ajuster certaines valeurs sysctl (différentes du profil de scan) |
| NETW-3200 | Désactiver les protocoles inutilisés : `dccp`, `sctp`, `rds` |
| USB-1000 | Désactiver les drivers USB storage si non utilisés |

---

### 🟡 Packages — Priorité normale

| ID | Suggestion |
|----|-----------|
| PKGS-7346 | Purger les anciens packages supprimés (11 trouvés) |
| PKGS-7370 | Installer `debsums` pour vérifier l'intégrité des packages |
| PKGS-7394 | Installer `apt-show-versions` pour la gestion des patches |
| DEB-0280 | Installer `libpam-tmpdir` pour les sessions PAM |
| DEB-0810 | Installer `apt-listbugs` pour les bugs critiques avant installation |
| DEB-0811 | Installer `apt-listchanges` pour les changelogs APT |
| DEB-0880 | Installer fail2ban *(déjà remplacé par CrowdSec)* |

---

### 🟡 Logging / Audit — Priorité normale

| ID | Suggestion |
|----|-----------|
| LOGG-2154 | Activer le logging vers un hôte externe *(Loki couvre ce besoin)* |
| LOGG-2190 | Vérifier les fichiers supprimés encore en usage |
| ACCT-9622 | Activer le process accounting |
| ACCT-9626 | Activer sysstat pour la collecte des statistiques système |
| ACCT-9628 | Activer auditd *(Falco couvre partiellement ce besoin)* |

---

### 🟡 Divers — Faible priorité

| ID | Suggestion |
|----|-----------|
| BOOT-5122 | Protéger GRUB par un mot de passe (accès console Hostinger) |
| BOOT-5264 | Durcir les services systemd via `systemd-analyze security` |
| FILE-6310 | Séparer `/home`, `/tmp`, `/var` sur des partitions dédiées |
| FILE-7524 | Corriger des permissions de fichiers |
| FINT-4350 | Installer un outil d'intégrité de fichiers *(Falco surveille les accès)* |
| HRDN-7230 | Installer un scanner malware *(Falco + CrowdSec couvrent ce besoin)* |
| BANN-7126 | Ajouter un banner légal dans `/etc/issue` |
| BANN-7130 | Ajouter un banner légal dans `/etc/issue.net` |

---

## Ce qui est déjà couvert

| Suggestion Lynis | Solution en place |
|-----------------|------------------|
| fail2ban | CrowdSec actif |
| Malware scanner | Falco runtime security |
| File integrity tool | Falco surveille les accès fichiers sensibles |
| External logging | Loki centralise les logs |
| Audit daemon | Falco syscall monitoring |

---

## Actions recommandées (par ordre de priorité)

1. **SSH hardening** via playbook Ansible — impact fort, risque faible
2. **Protocoles kernel inutiles** (dccp, sctp, rds) — 3 lignes sysctl
3. **Core dumps désactivés** — 1 ligne `/etc/security/limits.conf`
4. **Purger les anciens packages** — `apt autoremove --purge`
5. **umask 027** — modification `/etc/login.defs`
