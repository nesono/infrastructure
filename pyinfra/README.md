# pyinfra Docker role pilot

This is an optional port of `roles/docker/tasks/main.yml`. Existing Ansible
playbooks still run as before. Start with a disposable **Ubuntu 22.04** host;
the pilot deliberately rejects other releases because it preserves the original
role's global pip installation, which newer Ubuntu releases restrict.

Install on the controller with Python 3.10 or newer, from the repository root:

```sh
python3 -m venv /tmp/infrastructure-pyinfra
/tmp/infrastructure-pyinfra/bin/pip install -r pyinfra/requirements.txt
```

Review `pyinfra/inventory.example.py`, replace its example host, and use your SSH
key or agent. For a non-root SSH account, add `--sudo` to the commands below.
The Ansible INI inventory is not read by this deployment.

```sh
# Prepare and inspect changes without applying them.
/tmp/infrastructure-pyinfra/bin/pyinfra pyinfra/inventory.example.py pyinfra/docker.py --dry
# Apply only the Docker role.
/tmp/infrastructure-pyinfra/bin/pyinfra pyinfra/inventory.example.py pyinfra/docker.py
# Repeat to check convergence.
/tmp/infrastructure-pyinfra/bin/pyinfra pyinfra/inventory.example.py pyinfra/docker.py
```

## Mapping and deliberate differences

| Ansible task | pyinfra equivalent |
| --- | --- |
| Remove old Docker packages (`never`, `docker_purge`) | `apt.packages(present=False)`, only with `--data docker_purge=true` |
| `lsb_release -cs` | `OsRelease` fact, using `VERSION_CODENAME` |
| Install `python3-debian` for Ansible's repository module | Omitted: pyinfra writes deb822 without this library |
| Remove `docker.list` | `files.file(present=False)` |
| Configure Docker deb822 repository | `apt.sources_file` and a readable key in `/etc/apt/keyrings/docker.asc` |
| Install Docker Engine and Compose packages | `apt.packages`, same four packages |
| Install Python dependencies | `pip.packages`, same four packages, explicitly using `pip3` |

The pilot installs its own curl, CA certificate and pip prerequisites rather
than requiring the `common` role. It caches the initial apt refresh for one hour
and forces a refresh when the Docker repository changes. Package versions are
left unpinned, as in Ansible; installed packages are not upgraded automatically.
The downloaded signing key is retained on subsequent runs; key rotation requires
an explicit update. Migrating from Ansible replaces its `docker.sources` signing
key reference with the separate ASCII key file.

Docker package installation can start or restart Docker through package scripts.
This role does not copy `daemon.json`, deploy Compose services, or run the Compose
role's handlers. It is not a replacement for the complete provisioning playbook.

## Disposable integration check

With Docker available, run `tests/pyinfra/docker-role.sh` from the repository root
with the controller virtual environment activated. It provisions a fresh Ubuntu
22.04 container, verifies packages and repository configuration, then requires a
second run to report no changes. The container is removed on exit. This checks
configuration and convergence, not a running Docker daemon or production service
health. No production hosts or secrets are needed.

For a fair speed comparison, time the Ansible Docker role and this deployment on
equivalent disposable VMs, both for first installation and a converged run. The
container check does not provide a performance benchmark.
