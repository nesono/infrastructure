#!/usr/bin/env bash
# Run from the repository root with pyinfra available on PATH.
set -euo pipefail
container="pyinfra-docker-pilot-$$"
log=$(mktemp)
trap 'docker rm -f "$container" >/dev/null 2>&1 || true; rm -f "$log"' EXIT

docker run --detach --name "$container" ubuntu:22.04 sleep infinity >/dev/null
pyinfra "@docker/$container" pyinfra/docker.py --dry
# A dry run must not install packages or write the repository.
docker exec "$container" sh -ec 'test ! -e /etc/apt/sources.list.d/docker.sources; ! command -v docker'
pyinfra "@docker/$container" pyinfra/docker.py -y

docker exec "$container" sh -ec '
  dpkg-query -W docker-ce docker-ce-cli containerd.io docker-compose-plugin
  pip3 show jsondiff pyyaml requests docker >/dev/null
  test ! -e /etc/apt/sources.list.d/docker.list
  grep -Fx "Suites: jammy" /etc/apt/sources.list.d/docker.sources
  grep -Fx "Signed-By: /etc/apt/keyrings/docker.asc" /etc/apt/sources.list.d/docker.sources
  test "$(stat -c %a /etc/apt/keyrings/docker.asc)" = 644
'
pyinfra "@docker/$container" pyinfra/docker.py -y 2>&1 | tee "$log"
# The CLI summary must show zero changing operations on the second deployment.
awk '
  /Grand total/ {
    found = 1
    if ($(NF-2) != "-" || $(NF-1) != "-" || $NF != $(NF-3)) exit 1
  }
  END { if (!found) exit 1 }
' "$log"
