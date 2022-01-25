#!/usr/bin/env bash
# safer scripts
# only enable here because the read above seems to fail this setting
set -euo pipefail

# this is a weird workaround for mktemp. Otherwise yq cannot open the files
readonly tmpdir=/root/k0s_install_$$
mkdir -p "$tmpdir"

readonly k0s_config_file='/etc/k0s/k0s.yaml'
readonly tmp_config_file="$tmpdir/k0s.yaml"
readonly tmp_helm_chart="$tmpdir/helm_chart.yaml"
cat <<EOF > $tmp_helm_chart
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
# workaround because yq cannot acces the original file in /etc/
cp $k0s_config_file $tmp_config_file
# workaround because yq has problems with absolute file paths
cd $tmpdir
yq eval-all 'select(fileIndex==0).spec.extensions.helm = select(fileIndex==1).extensions.helm | select(fileIndex==0)' -i $tmp_config_file $tmp_helm_chart

mv ${tmp_config_file} $k0s_config_file
