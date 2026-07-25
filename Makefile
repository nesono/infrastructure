COMPOSE = docker compose \
  --project-directory . \
  -f roles/compose/files/docker-compose.yaml \
  -f dev/docker-compose.override.yaml

SERVICES = mysql_mail dovecot postfix postfixadmin

.PHONY: dev-setup dev-up dev-down dev-test dev-seed dev-logs dev-ps

dev-setup:
	@dev/generate-secrets.sh
	@dev/generate-certs.sh

dev-up: dev-setup
	$(COMPOSE) up --wait $(SERVICES)
	@$(MAKE) dev-seed

# Seed test data. Schema is created by PostfixAdmin on first boot, so this must
# run after the stack is up (dev-up calls it). Idempotent — safe to re-run.
dev-seed:
	@echo "Seeding dev test data..."
	@$(COMPOSE) exec -T mysql_mail sh -c \
	  'exec mysql -uroot -p"$$(cat /run/secrets/mysql_mail_root_password)" mailserver' \
	  < dev/seed-data.sql

dev-down:
	$(COMPOSE) down -v

dev-test:
	@dev/tests/smoke-test.sh

dev-logs:
	$(COMPOSE) logs -f $(SERVICES)

dev-ps:
	$(COMPOSE) ps
