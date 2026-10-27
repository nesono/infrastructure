# Dovecot 2.4 security migration

Dovecot moves from 2.3 to 2.4.5-root. The root variant preserves standard
listener ports and supports the existing mail UID 3000/GID 8. Its configuration
is migrated together with SQL authentication, TLS, Sieve storage, and metrics.
The removed dict quota backend is replaced by count quota plus quota_clone,
which mirrors usage into the existing PostfixAdmin quota2 table. Limits still
come from mailbox.quota in bytes. Network authentication requires TLS; Postfix
SASL continues through the shared UNIX socket.

## Validate locally

Run from the repository root with Python, Jinja2, PyYAML, OpenSSL, and Docker:

```sh
python3 tests/security/validate_dovecot.py
ansible-playbook -i production/hosts green_nesono.yml --syntax-check
git diff --check
```

The integration test uses disposable Docker containers, a separate database and
mail volume, a self-signed certificate, and loopback-only test ports. It checks
SQL password authentication, TLS IMAP, LMTP delivery, Sieve filing, and the SQL
quota mirror. It removes its test resources.

The migrated configuration passed parsing and startup checks. Full authentication
and delivery tests remain unverified because local Docker became unresponsive.
Run these tests successfully before production deployment.

## Deploy in a maintenance window

This is a mail configuration migration, not an image-only update. Do not
replace the Dovecot image while leaving the 2.3 configuration in place.

1. Take and verify a restorable backup of mail, the mail database, Dovecot
   configuration, and PostfixAdmin state. Save the old Compose file
   and image IDs. Mail index/storage formats can change after upgrading;
   rollback may require restoring the pre-upgrade mail snapshot, not merely
   selecting the old image.
2. Pre-pull the images on the server to reduce downtime:

   ```sh
   docker pull dovecot/dovecot:2.4.5-root
   ```

3. Stop Dovecot before installing its migrated configuration. Incoming delivery
   queues in Postfix during this window; IMAP, Sieve, and SMTP authentication
   are unavailable:

   ```sh
   docker compose -f /svc/volumes/docker-compose/docker-compose.yaml stop dovecot
   ```

4. From this checkout, with the existing Ansible secrets available, deploy:

   ```sh
   ansible-playbook -i production/hosts green_nesono.yml --tags hot_compose
   ```

   SQL templates are included in this tag. Dovecot config parsing runs before
   Compose starts replacements. The existing deployment
   task reconciles the whole Compose stack; inspect unrelated differences
   before executing it. Avoid concurrent cron deployments during the migration.

5. Confirm service health, IMAP login, SMTP authentication, incoming mail,
   Sieve rules, and quota display. Check Dovecot logs for SQL/plugin errors.
6. If validation fails, leave the old Dovecot process stopped until either the
   migration is corrected or the old image and all old configuration files are
   restored together. If 2.4 has modified mail storage, use the backup restoration
   procedure rather than assuming a downgrade is safe.

No production deployment is performed by creating this patch.

## Vendor references

- https://doc.dovecot.org/2.4.5/installation/upgrade/2.3-to-2.4.html
- https://doc.dovecot.org/2.4.5/core/plugins/quota_clone.html
