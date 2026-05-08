-- PostfixAdmin schema (minimal subset needed for Postfix + Dovecot)
-- Full schema is normally created by PostfixAdmin on first web access.
-- This seeds the DB so headless testing works without the web UI.

CREATE TABLE IF NOT EXISTS `domain` (
  `domain` varchar(255) NOT NULL,
  `description` varchar(255) NOT NULL DEFAULT '',
  `aliases` int NOT NULL DEFAULT 0,
  `mailboxes` int NOT NULL DEFAULT 0,
  `maxquota` bigint NOT NULL DEFAULT 0,
  `quota` bigint NOT NULL DEFAULT 0,
  `transport` varchar(255) NOT NULL DEFAULT '',
  `backupmx` tinyint(1) NOT NULL DEFAULT 0,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mailbox` (
  `username` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL DEFAULT '',
  `maildir` varchar(255) NOT NULL,
  `quota` bigint NOT NULL DEFAULT 0,
  `local_part` varchar(255) NOT NULL,
  `domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `phone` varchar(30) NOT NULL DEFAULT '',
  `email_other` varchar(255) NOT NULL DEFAULT '',
  `token` varchar(255) NOT NULL DEFAULT '',
  `token_validity` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  PRIMARY KEY (`username`),
  KEY `domain` (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `alias` (
  `address` varchar(255) NOT NULL,
  `goto` text NOT NULL,
  `domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`address`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `alias_domain` (
  `alias_domain` varchar(255) NOT NULL,
  `target_domain` varchar(255) NOT NULL,
  `created` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `modified` datetime NOT NULL DEFAULT '2000-01-01 00:00:00',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`alias_domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `quota2` (
  `username` varchar(255) NOT NULL,
  `bytes` bigint NOT NULL DEFAULT 0,
  `messages` int NOT NULL DEFAULT 0,
  PRIMARY KEY (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed data: test domain and mailbox
-- Password is MD5-CRYPT hash of 'dev_password'
-- Generated with: doveadm pw -s MD5-CRYPT -p dev_password

INSERT INTO `domain` (`domain`, `description`, `aliases`, `mailboxes`, `maxquota`, `active`)
VALUES ('dev.local', 'Development domain', 100, 100, 10485760, 1);

INSERT INTO `mailbox` (`username`, `password`, `name`, `maildir`, `quota`, `local_part`, `domain`, `active`)
VALUES ('test@dev.local', '$1$devlocal$6bnwNpwgqIq2EMp9XrVYy1', 'Test User', 'dev.local/test@dev.local/', 10485760, 'test', 'dev.local', 1);

INSERT INTO `alias` (`address`, `goto`, `domain`, `active`)
VALUES ('test@dev.local', 'test@dev.local', 'dev.local', 1);
