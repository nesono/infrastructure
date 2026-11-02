# Nesono infrastructure

This repository manages self-hosted services on Hetzner servers running Ubuntu,
using Ansible and Docker Compose. Server instances alternate between the names
`blue` and `green` during migrations; these names identify instances rather
than a permanent server. The current instance is `green`, running Ubuntu
22.04.5 LTS, and is configured in [production/hosts](production/hosts).
The commands below use the current `green_nesono.yml` playbook. Routine changes
are made in this repository and copied to the server by Ansible.

## Current services

The service definitions, image tags, mounts, networks, and secrets are in
[roles/compose/files/docker-compose.yaml](roles/compose/files/docker-compose.yaml).

| Area | Services |
| --- | --- |
| HTTPS and certificates | Nginx, docker-gen, acme-companion |
| Mail | Postfix with integrated spam/signing milters, Dovecot, PostfixAdmin, Roundcube, MySQL, PostgreSQL |
| Cloud | Two Nextcloud instances, each with MariaDB and Redis |
| Websites and Git | WordPress with MySQL, static Nginx sites, Gitea with PostgreSQL |
| Monitoring | Prometheus, Grafana, Loki, Alloy, node_exporter, postfix_exporter |
| Host protection and backups | Fail2ban, Borgmatic |

The `mail_nesono_com` HTTP service requests certificates for the mail hostnames.
Postfix and Dovecot mount the resulting certificates. There is no separate
milter service: the milters run in the custom Postfix image.

## Configuration and persistent data

| Location | Purpose |
| --- | --- |
| `roles/compose/files/` | Version-controlled Compose file and service configuration |
| `roles/compose/templates/dovecot/` | SQL configuration rendered with local secrets |
| `secrets/secret_*.txt` on the Ansible controller | Deployment credentials; excluded from Git |
| `/svc/volumes/docker-compose/docker-compose.yaml` | Deployed Compose file |
| `/svc/volumes/` | Persistent application data and service configuration |
| `/svc/volumes/php/security.ini` | PHP settings shared by PostfixAdmin, Roundcube, and WordPress |
| `/svc/volumes/acme/certs/` | Managed TLS certificates |
| `/var/docker_compose_secrets/` | Secret files mounted into containers under `/run/secrets/` |
| `/usr/local/sbin/backup.sh` | Optional manual cold-backup command installed by Ansible |

Named Compose volumes mostly bind to directories under `/svc/volumes`.
Changing or recreating a container is separate from deleting its persistent
data. The mail store uses UID 3000 and GID 8; keep these consistent with the
custom Postfix image and Dovecot userdb configuration.

Host-local settings also matter: root's crontab, SSH access, host mail
notifications, and the installed operating system are not fully described by
the Compose file. The root crontab is maintained manually, not by this playbook.

## Bootstrap a Hetzner server with installimage

Use Hetzner's Rescue System and
[installimage](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installimage/)
to install the host operating system before provisioning it with Ansible.

1. Log in to Hetzner Robot and activate the Linux Rescue System for the server.
2. Reboot the server into Rescue using Robot's reset controls.
3. Connect as `root@<server-ip>` using the Rescue credentials.
4. Select an Ubuntu image with `installimage` and adapt its configuration for
   the server's disks and hostname.

The RAID-1/Btrfs layout used by this setup is shown below. Replace the drive
paths, hostname, and `IMAGE` path with values for the target server and the
Ubuntu image available in Rescue. Installation erases the selected drives.

```sh
cat > installimage.conf <<'CONFIG'
DRIVE1 /dev/sda
DRIVE2 /dev/sdb
SWRAID 1
SWRAIDLEVEL 1
HOSTNAME green.<example.com>
PART   btrfs.raid    btrfs    all
SUBVOL btrfs.raid    @        /
SUBVOL btrfs.raid    @var     /var
SUBVOL btrfs.raid    @svc     /svc
SUBVOL btrfs.raid    @tmp     /tmp
IMAGE <full-path-to-ubuntu-image.tar.gz>
CONFIG
```

After reviewing the configuration, run the installation in the Rescue shell:

```sh
installimage -a -c installimage.conf
```

Once installation finishes, reboot into the installed system. Confirm SSH
access and update `production/hosts` if the server address changed, then use
the Ansible roles below to provision the host, Docker, and Compose services.
Restore the host-local crontab and backup access as part of rebuilding a server.

## Deploy from the local checkout

Run these commands on the Ansible controller, from the repository root:

```sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i production/hosts green_nesono.yml --syntax-check
ansible-playbook -i production/hosts green_nesono.yml --tags hot_compose
```

Use a checkout containing the latest merged changes. Deploying an older PR
branch can revert unrelated service images and settings.

The `hot_compose` tasks copy the Compose file and selected service configuration,
render the Dovecot SQL files, and run `docker compose up --wait --remove-orphans`
on the server. They reconcile the whole Compose project, not just the service
edited in the current change. They also require the local mail database secret
files used by the Dovecot templates.

Deployment does not explicitly pull every image. Pulling updated images under
existing tags is a separate operation, also performed by the host's scheduled
update command.

| Tag | Scope |
| --- | --- |
| `hot_compose` | Routine configuration and Compose deployment |
| `provision` | Initial directories, secret copies, and selected configuration; does not include all deployment tasks |
| `backup_script` | Install or update the manual cold-backup script |
| `compose` | The entire Compose role, including provisioning tasks |

The `common` and `docker` roles configure the host and Docker installation.
Full provisioning includes host-specific filesystem quotas, ownership changes,
and possible service restarts. Review those tasks before using them to provision
the freshly installed server or rebuild the existing installation.

### Secrets

Keep the required `secret_*.txt` files in the controller's `secrets/` directory.
The copy tasks in
[roles/compose/tasks/main.yaml](roles/compose/tasks/main.yaml) define the required
files and their ownership. The Compose file defines their container mounts.

Provisioning copies secrets to `/var/docker_compose_secrets`. Routine
`hot_compose` deployment does not refresh all secret files. Coordinate secret
changes with the relevant configuration and container recreation. Never commit
the secret files or generated SQL configuration containing passwords.

## Operate on the server

Connect using the inventory's SSH account:

```sh
ssh root@5.9.123.102
```

For the interactive commands below, define this shell helper on the server:

```sh
dc() {
  docker compose -f /svc/volumes/docker-compose/docker-compose.yaml "$@"
}
```

Use service names rather than generated container IDs:

```sh
dc ps -a
dc logs --tail 100 postfixadmin
dc exec dovecot doveconf -n
dc exec postfix postqueue -p
```

Postfix, Dovecot, Grafana, and Gitea send logs to the host's syslog. Check
`/var/log/syslog` for those services; container logs alone may not show the
relevant errors. Avoid sharing startup logs or generated configuration without
checking for credentials.

To pull and apply images from the deployed Compose file:

```sh
dc up -d --pull always
```

To restart just one existing service:

```sh
dc restart grafana
```

A restart does not apply a changed image, environment, or mount definition.
Use Compose `up` after deploying those changes. An `up --wait` failure can mean
a startup health check failed; inspect `dc ps -a` and the affected service's
health-check output before assuming the whole deployment failed.

## Host crontab

Inspect and edit the installed schedule on the server:

```sh
sudo crontab -l
sudo crontab -e
timedatectl
```

The host runs in `Europe/Berlin`. Its root crontab was checked on 2026-11-01
and schedules the following jobs in host local time (CET/CEST):

| Schedule | Installed job |
| --- | --- |
| Every five minutes | Background jobs for both Nextcloud instances |
| Sunday 04:05 | Reload Dovecot and Postfix certificates |
| Sunday 05:05 | Pull and apply Compose images |
| Sunday 07:05 | Add missing database indices for both Nextcloud instances |

The installed Nextcloud background jobs and certificate reloads still select
containers using old dot-style name filters. All four filters currently match
zero containers: the Nextcloud and Dovecot names end in `-1`, and Postfix is
named `postfix`. Those four scheduled commands therefore do not perform their
intended work.

The following is a proposed replacement for those seven installed job lines,
keeping their existing schedule but using Compose service names. It also runs
Nextcloud maintenance as `www-data` and disables TTY allocation for cron.
**These replacement commands have not been installed on the server.**

```cron
# Nextcloud background jobs, every five minutes, as the web-server user.
*/5 * * * * docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T --user www-data cloud_nesono_com php -f /var/www/html/cron.php
*/5 * * * * docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T --user www-data cloud_noerpel_com php -f /var/www/html/cron.php

# Reload mail TLS certificates on Sunday.
5 4 * * Sun docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T dovecot doveadm reload
5 4 * * Sun docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T postfix postfix reload

# Pull and apply updated images on Sunday.
5 5 * * Sun docker compose -f /svc/volumes/docker-compose/docker-compose.yaml up -d --pull always

# Nextcloud index maintenance on Sunday.
5 7 * * Sun docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T --user www-data cloud_nesono_com php occ db:add-missing-indices
5 7 * * Sun docker compose -f /svc/volumes/docker-compose/docker-compose.yaml exec -T --user www-data cloud_noerpel_com php occ db:add-missing-indices
```

These lines belong in root's user crontab, so they have no separate username
field. They are not installed by Ansible. The interactive `dc` helper is not
available to cron.

Borgmatic has a separate in-container schedule, described below. Avoid
overlapping image updates, deployments, and cold backups.

## Backups

[Borgmatic configuration](roles/compose/files/borgmatic/config.yaml) backs up
`/svc/volumes`, mounted read-only at `/mnt/source`, to a Hetzner Storage Box over
SSH port 23. The configuration specifies retention and repository checks.
The passphrase and notification credentials come from Docker secrets.

The backup covers the mounted volume tree, subject to its configured
`one_file_system` boundary. It does not include the controller checkout, root's
crontab, or `/var/docker_compose_secrets`. Keep separate recoverable copies of
those settings and credentials.

### Scheduled live backup

[Borgmatic's crontab](roles/compose/files/borgmatic/crontab.txt) runs daily at
03:00 in the backup container, which is configured with `TZ=UTC`.
This is a live file backup: it does not stop applications or databases.

From the server shell, list archives or run the configured backup:

```sh
dc exec -T borg-backup sh -ec 'export BORG_PASSPHRASE="$(cat "$BORG_PASSPHRASE_FILE")"; exec borgmatic list'
dc exec -T borg-backup sh -ec 'export BORG_PASSPHRASE="$(cat "$BORG_PASSPHRASE_FILE")"; exec borgmatic'
```

For an interactive backup-container shell:

```sh
dc exec borg-backup sh
export BORG_PASSPHRASE="$(cat "$BORG_PASSPHRASE_FILE")"
```

### Manual cold backup

Install or update the script from the controller:

```sh
ansible-playbook -i production/hosts green_nesono.yml --tags backup_script
```

Run it on the server in a persistent terminal such as tmux:

```sh
sudo /usr/local/sbin/backup.sh
```

The script stops currently running services except Borg, stopping applications
before databases. It aborts if a database was forcibly killed, creates an
archive, and restarts the services that were previously running. Websites,
cloud services, and mail access are unavailable throughout the archive creation.

Do not deploy or run service-management commands during the backup, and avoid
the scheduled live backup. Pruning and checks stay with the scheduled job.
Restore database files with compatible database image versions and test the
restore procedure.

If a host crash or SIGKILL prevents cleanup, inspect service state and restart
the intended services with `dc start`. That command also starts services that
were deliberately stopped before the backup, so check before running it.

Storage Box connection details and retention live in the Borgmatic config.
Its SSH key is under `/svc/volumes/borgmatic/keys/`; access to a replacement
Storage Box must be authorized before relying on backups.

## Mail administration

- PostfixAdmin: `https://postfixadmin.nesono.com`
- Roundcube: `https://roundcube.nesono.com`
- IMAP: `imap.nesono.com:993` with TLS, or port 143 with STARTTLS.
- SMTP submission: `smtp.nesono.com:465` with TLS, or port 587 with STARTTLS.
- ManageSieve: `sieve.nesono.com:4190` with STARTTLS.
- Port 25 is also exposed for incoming server-to-server SMTP.

Postfix uses Dovecot's shared UNIX sockets for authentication and LMTP delivery.
Basic container health checks do not prove that mailbox authentication works.

New and changed PostfixAdmin passwords use Argon2id. Legacy MD5-CRYPT hashes
remain supported by `auth_allow_weak_schemes = yes` until the remaining accounts
are migrated. Keep the explicit scheme prefixes on stored hashes; changing the
default does not rehash existing passwords. Disable weak schemes only when no
accounts still require them.

For an initial PostfixAdmin administrator, use its `setup.php` page and the
setup-password hash from `secrets/secret_postfixadmin_setup_password.txt`.
Existing installations do not need to repeat setup on every deployment.

### Connect to the mail database

On the server:

```sh
dc exec mysql_mail sh -c 'MYSQL_PWD="$(cat /run/secrets/mysql_mail_root_password)" exec mysql -u root mailserver'
```

This uses the existing secret without printing it. Exit the MySQL shell with
`exit;`. Take a database backup before manual credential or schema changes.

### Check mail TLS

These commands connect without submitting passwords or sending messages:

```sh
openssl s_client -connect imap.nesono.com:993 -servername imap.nesono.com -verify_return_error
openssl s_client -starttls imap -connect imap.nesono.com:143 -servername imap.nesono.com -verify_return_error
openssl s_client -connect smtp.nesono.com:465 -servername smtp.nesono.com -verify_return_error
openssl s_client -starttls smtp -connect smtp.nesono.com:587 -servername smtp.nesono.com -verify_return_error
```

Certificate reloads can normally use `dc exec dovecot doveadm reload` and
`dc exec postfix postfix reload`. Changes to authentication settings may require
a Dovecot restart if old authentication workers retain their previous state.

### Add a mail domain

Add the domain and mailboxes in PostfixAdmin. Configure its MX, SPF, DKIM, and
DMARC DNS records to match this mail server. The current signing domains,
selector, and key-secret path are defined by `DKIM_DOMAINS`, `DKIM_SELECTOR`,
and `DKIM_KEY_PATH` in the Postfix service. Update the signing configuration
when adding a domain and publish the matching public key; keep the private
key in the secret file.

## Nextcloud

The two services are `cloud_nesono_com` and `cloud_noerpel_com`. Each has separate
database, Redis, application, configuration, and data storage. Use the host
cron jobs above for background processing.

Run `occ` as the container's web-server user:

```sh
dc exec --user www-data cloud_nesono_com php occ status
dc exec --user www-data cloud_noerpel_com php occ status
dc exec --user www-data cloud_nesono_com php occ db:add-missing-indices
```

Follow Nextcloud's supported upgrade sequence when changing image versions.
If an upgrade is incomplete, inspect its logs and `occ status` before deciding
whether `occ upgrade` is needed. Disable maintenance mode only after the upgrade
has completed successfully.

## Monitoring

Grafana uses `http://prometheus:9090` for metrics and `http://loki:3100` for logs
on the private monitoring network. Loki has no published host port. Alloy reads
the host syslog and sends it to Loki.

Prometheus scrapes itself, node_exporter, Dovecot, and postfix_exporter according
to [its configuration](roles/compose/files/prometheus/prometheus.yml).
Grafana's dashboards and data-source definitions are stored in its persistent
volume; they are not provisioned by Ansible. The existing dashboards include
Node Exporter Full, Dovecot, and Postfix.

If a dashboard reports a missing data source, check both the configured UID
and Grafana's plugin status. A `Plugin not registered` error can occur even when
the data-source record exists. Check the host syslog; restarting Grafana resolved
that plugin-loading failure after the recent upgrade without exposing Loki.
