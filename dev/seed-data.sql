-- Dev test data for the mail stack smoke tests.
--
-- IMPORTANT: this file seeds DATA only, never schema. PostfixAdmin creates and
-- migrates the full schema itself on first boot (its version detection breaks if
-- it finds pre-existing tables), so this runs *after* postfixadmin is healthy —
-- see the `dev-seed` target in the Makefile.
--
-- All inserts are idempotent so `make dev-seed` can be re-run safely.
--
-- Password is MD5-CRYPT hash of 'dev_password'
-- Generated with: doveadm pw -s MD5-CRYPT -p dev_password

INSERT INTO `domain`
  (`domain`, `description`, `aliases`, `mailboxes`, `maxquota`, `quota`, `transport`, `backupmx`, `active`)
VALUES
  ('dev.local', 'Development domain', 100, 100, 10485760, 0, 'virtual', 0, 1)
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);

INSERT INTO `mailbox`
  (`username`, `password`, `name`, `maildir`, `quota`, `local_part`, `domain`,
   `phone`, `email_other`, `token`, `smtp_active`, `active`)
VALUES
  ('test@dev.local', '$1$devlocal$6bnwNpwgqIq2EMp9XrVYy1', 'Test User',
   'dev.local/test@dev.local/', 10485760, 'test', 'dev.local',
   '', '', '', 1, 1)
ON DUPLICATE KEY UPDATE `password` = VALUES(`password`);

INSERT INTO `alias`
  (`address`, `goto`, `domain`, `active`)
VALUES
  ('test@dev.local', 'test@dev.local', 'dev.local', 1)
ON DUPLICATE KEY UPDATE `goto` = VALUES(`goto`);
