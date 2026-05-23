#!/bin/bash
set -euo pipefail

NODES=("76.13.44.160" "217.65.146.24")

echo "==> Stopping Wazuh agents on nodes..."
for NODE in "${NODES[@]}"; do
  ssh "root@${NODE}" bash <<'EOF'
systemctl stop wazuh-agent || true
systemctl disable wazuh-agent || true
# Clean agent DBs so next install starts fresh
rm -f /var/ossec/queue/db/0*.db /var/ossec/queue/db/0*.db-shm /var/ossec/queue/db/0*.db-wal
EOF
done

echo "==> Removing Wazuh from cluster..."
kubectl delete namespace wazuh --ignore-not-found
kubectl delete storageclass wazuh-storage --ignore-not-found

echo "==> Wazuh stopped."
echo "    Agent binaries kept on nodes (apt). Data PVCs deleted with namespace."
echo "    Run install.sh to redeploy from scratch."
