# PHP security update

PostfixAdmin moves to 4.0.5-apache and WordPress uses the explicit
6.9-php8.3-apache image. Both pull at deployment. A shared ini file disables
session upload progress in PostfixAdmin, WordPress, and Roundcube.

Before deploying, Ansible checks each image's actual PHP version against
8.2.35 / 8.3.36 / 8.4.27 / 8.5.12 and verifies the ini setting. An old or
unknown runtime fails the deployment check. Application updates alone do not
replace PHP. This addresses CVE-2026-109618 and CVE-2026-109619 and disables
the conditional session-upload-progress path described for CVE-2026-115560.

## Validation

Run with Docker, Python, and PyYAML:

```sh
python3 tests/security/validate_php.py
ansible-playbook -i production/hosts green_nesono.yml --syntax-check
```

PostfixAdmin's new image was verified locally as PHP 8.3.36. Full WordPress
and Roundcube image validation was blocked when local Docker became
unresponsive. The runtime checks must pass on the deployment host.

## Deployment

Back up application state and databases before the PostfixAdmin update.
Review other differences between the checkout and production before running:

```sh
ansible-playbook -i production/hosts green_nesono.yml --tags hot_compose
```

The existing deployment reconciles the entire stack. Confirm PHP versions,
service health, and application logins after recreation. The ini file is
installed under /svc/volumes/docker-compose/php before Compose mounts it.
Production has not been modified by creating this patch.

Reference: https://www.php.net/ (October 21 and October 23, 2026 advisories).
