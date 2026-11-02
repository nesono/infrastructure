"""Optional port of roles/docker for the current Ubuntu 22.04 hosts."""

from pyinfra import host
from pyinfra.api import DeployError
from pyinfra.facts.server import OsRelease
from pyinfra.operations import apt, files, pip

release = host.get_fact(OsRelease)
if release.get("id") != "ubuntu" or release.get("version_id") != "22.04":
    raise DeployError("This pilot supports Ubuntu 22.04 only (global pip dependencies).")

# Equivalent to Ansible's never/docker_purge tasks: explicitly opt in.
if host.data.get("docker_purge", False):
    apt.packages(
        name="Remove conflicting Docker packages (explicit opt-in)",
        packages=["docker", "docker-engine", "docker.io", "containerd", "runc"],
        present=False,
    )

apt.update(name="Refresh Ubuntu package cache", cache_time=3600)
apt.packages(
    name="Install repository and Python package prerequisites",
    packages=["ca-certificates", "curl", "python3-pip"],
)
files.directory(
    name="Create apt key directory",
    path="/etc/apt/keyrings",
    user="root",
    group="root",
    mode="0755",
)
files.download(
    name="Install Docker repository signing key",
    src="https://download.docker.com/linux/ubuntu/gpg",
    dest="/etc/apt/keyrings/docker.asc",
    user="root",
    group="root",
    mode="0644",
)
files.file(
    name="Remove legacy Docker repository",
    path="/etc/apt/sources.list.d/docker.list",
    present=False,
)
repository = apt.sources_file(
    name="Configure Docker deb822 repository",
    filename="docker",
    uris="https://download.docker.com/linux/ubuntu",
    suites=release["version_codename"],
    components="stable",
    signed_by="/etc/apt/keyrings/docker.asc",
)
# Evaluate after the repository operation executes, rather than branching on
# its result during pyinfra's prepare phase.
apt.update(name="Refresh newly configured Docker repository", _if=repository.did_change)
apt.packages(
    name="Install Docker Engine and Compose",
    packages=["docker-ce", "docker-ce-cli", "containerd.io", "docker-compose-plugin"],
)
pip.packages(
    name="Install Python dependencies used by the Ansible deployment",
    packages=["jsondiff", "pyyaml", "requests", "docker"],
    pip="pip3",
)
