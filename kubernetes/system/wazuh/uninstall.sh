#!/bin/bash
set -euo pipefail

# Removes all Wazuh resources but keeps the PVCs (data preserved)
# To also delete data, add: kubectl delete pvc --all -n wazuh

WAZUH_VERSION="v4.14.1"
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

git clone --depth=1 --branch "${WAZUH_VERSION}" https://github.com/wazuh/wazuh-kubernetes.git "${TMPDIR}/wazuh-kubernetes"

cd "${TMPDIR}/wazuh-kubernetes"

kubectl delete -k envs/local-env/ --ignore-not-found
kubectl delete storageclass wazuh-storage --ignore-not-found

echo "==> Wazuh stopped. PVCs kept intact for next run."
echo "    To delete data: kubectl delete pvc --all -n wazuh"
