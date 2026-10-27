#!/usr/bin/env python3
"""Check the embedded PHP runtime and ini settings of the three web images."""
from pathlib import Path
import subprocess

import yaml

ROLE = Path(__file__).resolve().parents[2] / "roles/compose"
services = yaml.safe_load((ROLE / "files/docker-compose.yaml").read_text())["services"]
for service in ("postfixadmin", "wordpress_noerpel", "roundcube"):
    result = subprocess.check_output(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "php",
         "-v", f"{ROLE / 'files/php/security.ini'}:/usr/local/etc/php/conf.d/zz-security.ini:ro",
         "-v", f"{ROLE / 'files/php/check-runtime.php'}:/check-runtime.php:ro",
         services[service]["image"], "/check-runtime.php"],
        text=True, timeout=180,
    )
    print(f"{service}: {result.strip()}", flush=True)
