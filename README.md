# infra

Pipeline GitOps pour l'infrastructure k3s.

## Prérequis locaux

```bash
brew install ansible helm kubectl
pip install sshpass  # pour le worker (auth par mot de passe au premier run)
```

## Démarrage rapide

### 1. Configurer le mot de passe du worker

```bash
ansible-vault edit ansible/inventory/group_vars/all/vault.yml
# → remplacer CHANGE_ME par le vrai mot de passe root du worker
```

### 2. Bootstrap (OS + clé SSH)

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/01-bootstrap.yml \
  --ask-vault-pass
```

Après ce step, le worker accepte ta clé SSH — plus besoin de mot de passe.

### 3. Installer k3s

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/02-k3s.yml
# kubeconfig.yml est généré à la racine du repo
```

### 4. Installer Traefik

```bash
bash kubernetes/system/traefik/install.sh
```

### Vérifier le cluster

```bash
export KUBECONFIG=./kubeconfig.yml
kubectl get nodes
kubectl get pods -n traefik
```

## Structure

```
ansible/
  inventory/        hosts + variables (vault pour secrets)
  playbooks/        01-bootstrap, 02-k3s
  roles/            common, k3s_master, k3s_worker
kubernetes/
  system/traefik/   helm values + install script
  apps/             tes applications (à venir)
docs/               architecture et décisions
```
