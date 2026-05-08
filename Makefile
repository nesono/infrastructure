COMPOSE = docker compose \
  --project-directory . \
  -f roles/compose/files/docker-compose.yaml \
  -f dev/docker-compose.override.yaml

SERVICES = mysql_mail dovecot postfix postfixadmin

.PHONY: dev-setup dev-up dev-down dev-test dev-logs dev-ps

dev-setup:
	@dev/generate-secrets.sh
	@dev/generate-certs.sh

dev-up: dev-setup
	$(COMPOSE) up --wait $(SERVICES)

dev-down:
	$(COMPOSE) down -v

dev-test:
	@dev/tests/smoke-test.sh

dev-logs:
	$(COMPOSE) logs -f $(SERVICES)

dev-ps:
	$(COMPOSE) ps
