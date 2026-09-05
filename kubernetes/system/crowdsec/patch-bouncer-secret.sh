#!/usr/bin/env bash
set -euo pipefail

# Le chart crowdsec-traefik-bouncer (0.1.4) n'a plus de mécanisme pour référencer un
# Secret externe : seule une valeur en clair `bouncer.crowdsec_bouncer_api_key` est
# supportée. On la laisse vide dans les values ArgoCD (satisfait la validation du
# chart) et on patche ensuite l'env var pour pointer vers le SealedSecret
# crowdsec-bouncer-api-key, plutôt que de committer la clé en clair.
#
# À rejouer après chaque sync ArgoCD de l'app crowdsec-traefik-bouncer (le chart
# régénère l'env var à valeur vide sinon). selfHeal ArgoCD ne revert pas ce patch
# car il porte sur un champ (valueFrom) que le chart ne définit jamais lui-même.

export KUBECONFIG="$(git rev-parse --show-toplevel)/ansible/kubeconfig.yml"

kubectl patch deployment crowdsec-traefik-bouncer -n crowdsec --type json -p '[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/env/0",
    "value": {
      "name": "CROWDSEC_BOUNCER_API_KEY",
      "valueFrom": {
        "secretKeyRef": {
          "name": "crowdsec-bouncer-api-key",
          "key": "apiKey"
        }
      }
    }
  }
]'

echo "Patch appliqué : CROWDSEC_BOUNCER_API_KEY référence maintenant le secret."
