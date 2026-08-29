#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

# Must be run from the repo root (where Makefile lives)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${REPO_ROOT}"

COMPOSE="docker compose --project-directory . -f roles/compose/files/docker-compose.yaml -f dev/docker-compose.override.yaml"

PASS=0
FAIL=0

run_test() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: ${name}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${name}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Mail Stack Smoke Tests ==="
echo ""

# SMTP connectivity
echo "--- SMTP ---"
run_test "SMTP port 1025 reachable" nc -z -w5 localhost 1025
run_test "Submission port 1587 reachable" nc -z -w5 localhost 1587
run_test "SMTPS port 1465 reachable" nc -z -w5 localhost 1465

# SMTP banner
run_test "SMTP banner on port 1025" bash -c \
  "echo QUIT | nc -w5 localhost 1025 | grep -q '220.*ESMTP Postfix'"

# STARTTLS on submission
run_test "STARTTLS offered on submission" bash -c \
  "echo -e 'EHLO test\r\nQUIT\r\n' | nc -w5 localhost 1587 | grep -qi STARTTLS"

# IMAP connectivity
echo ""
echo "--- IMAP ---"
run_test "IMAP port 1143 reachable" nc -z -w5 localhost 1143
run_test "IMAPS port 1993 reachable" nc -z -w5 localhost 1993

# Supervisor services
echo ""
echo "--- Supervisor ---"
run_test "postfix service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status postfix
run_test "rsyslog service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status rsyslog
run_test "opendkim service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status opendkim
run_test "opendmarc service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status opendmarc
run_test "spamass service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status spamass
run_test "spamd service running" ${COMPOSE} exec -T postfix \
  supervisorctl -c /etc/supervisord.conf status spamd

# Milter sockets
echo ""
echo "--- Milter Sockets ---"
run_test "DKIM socket exists" ${COMPOSE} exec -T postfix \
  test -S /var/spool/postfix/private/dkim
run_test "DMARC socket exists" ${COMPOSE} exec -T postfix \
  test -S /var/spool/postfix/private/dmarc
run_test "SpamAssassin socket exists" ${COMPOSE} exec -T postfix \
  test -S /var/spool/postfix/private/spamass

# Dovecot sockets (shared via mail_spool volume)
echo ""
echo "--- Dovecot Sockets ---"
run_test "SASL auth socket exists" ${COMPOSE} exec -T postfix \
  test -S /var/spool/postfix/private/auth
run_test "LMTP socket exists" ${COMPOSE} exec -T postfix \
  test -S /var/spool/postfix/private/dovecot-lmtp

# Relay rejection
echo ""
echo "--- Security ---"
# Use a local sender (dev.local is a hosted domain) so the relay restriction is
# actually exercised at RCPT TO. A sender like evil@example.com is rejected
# earlier at MAIL FROM (example.com publishes a null MX, RFC 7505), which never
# reaches the relay check.
run_test "Rejects unauthenticated relay" bash -c \
  "printf 'EHLO test\r\nMAIL FROM:<postmaster@dev.local>\r\nRCPT TO:<victim@example.org>\r\nQUIT\r\n' | nc -w5 localhost 1025 | grep -q '554\|553\|550\|521\|450'"

# PostfixAdmin web
echo ""
echo "--- PostfixAdmin ---"
run_test "PostfixAdmin HTTP responds" curl -sf -o /dev/null http://localhost:8080/

# DKIM configuration
echo ""
echo "--- DKIM ---"
run_test "OpenDKIM config exists" ${COMPOSE} exec -T postfix \
  test -f /etc/opendkim.conf
run_test "DKIM KeyTable has dev.local" ${COMPOSE} exec -T postfix \
  grep -q dev.local /etc/opendkim/KeyTable

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
