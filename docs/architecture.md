# Architecture

## Serveurs

| Rôle | IP | Auth SSH |
|------|-----|----------|
| master (control plane) | 76.13.44.160 | clé SSH |
| worker | 217.65.146.24 | mot de passe → clé SSH après bootstrap |

## Stack

- **OS** : Ubuntu 24.04 LTS
- **Kubernetes** : k3s (traefik intégré désactivé, on le déploie manuellement via Helm)
- **Ingress** : Traefik v3 (namespace `traefik`)
- **Provisioning** : Ansible

## Ordre de déploiement

```
1. ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/01-bootstrap.yml
   → sécurise les deux serveurs, déploie la clé SSH sur le worker

2. ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/02-k3s.yml
   → installe k3s master, puis joint le worker
   → récupère kubeconfig.yml à la racine (gitignored)

3. bash kubernetes/system/traefik/install.sh
   → installe Traefik via Helm dans le namespace traefik
```

## Fichiers sensibles

- `kubeconfig.yml` — gitignored, généré après le step 2
- `ansible/inventory/group_vars/all/vault.yml` — gitignored, chiffrer avec ansible-vault
- `.vault_pass` — gitignored, mot de passe ansible-vault local
