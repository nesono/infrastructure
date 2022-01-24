#!/usr/bin/env bash
# safer scripts
set -euo pipefail

IFS='' read -r -d '' HELM_CONFIG <<"EOF"
extensions:
  helm:
    repositories:
    - name: traefik
      url: https://helm.traefik.io/traefik
    - name: bitnami
      url: https://charts.bitnami.com/bitnami
    charts:
    - name: traefik
      chartname: traefik/traefik
      version: "10.3.2"
      namespace: default
    - name: metallb
      chartname: bitnami/metallb
      version: "2.5.4"
      namespace: default
      values: |2
        configInline:
          address-pools:
          - name: generic-cluster-pool
            protocol: layer2
            addresses:
            - 5.9.198.112/29
EOF
