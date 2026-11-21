#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"

mkdir -p "${SECRETS_DIR}"

write_secret() {
  local name="$1" value="$2"
  local path="${SECRETS_DIR}/secret_${name}.txt"
  if [[ ! -f "${path}" ]]; then
    printf '%s' "${value}" > "${path}"
    echo "Created: secret_${name}.txt"
  fi
}

# Database credentials
write_secret "mysql_mail_user" "dev_user"
write_secret "mysql_mail_password" "dev_password"
write_secret "mysql_mail_root_password" "dev_root_password"
write_secret "roundcube_db_user" "dev_user"
write_secret "roundcube_db_password" "dev_password"
write_secret "gitea_db_user" "dev_user"
write_secret "gitea_db_password" "dev_password"
write_secret "mariadb_cloud_nesono_root_password" "dev_root_password"
write_secret "mariadb_cloud_nesono_user" "dev_user"
write_secret "mariadb_cloud_nesono_password" "dev_password"
write_secret "mariadb_cloud_noerpel_root_password" "dev_root_password"
write_secret "mariadb_cloud_noerpel_user" "dev_user"
write_secret "mariadb_cloud_noerpel_password" "dev_password"
write_secret "mysql_wordpress_noerpel_user" "dev_user"
write_secret "mysql_wordpress_noerpel_password" "dev_password"
write_secret "mysql_wordpress_noerpel_root_password" "dev_root_password"

# Service credentials
write_secret "postfixadmin_setup_password" "dev_setup_password"
write_secret "gitea_mailer_user" "robot@dev.local"
write_secret "gitea_mailer_password" "dev_password"
write_secret "robot_mail_user" "robot@dev.local"
write_secret "robot_mail_password" "dev_password"
write_secret "borgmatic_passphrase" "dev_borg_passphrase"
write_secret "nextcloud_nesono_admin_user" "admin"
write_secret "nextcloud_nesono_admin_password" "dev_password"
write_secret "nextcloud_noerpel_admin_user" "admin"
write_secret "nextcloud_noerpel_admin_password" "dev_password"
write_secret "grafana_admin_user" "admin"
write_secret "grafana_admin_password" "dev_password"

# DKIM key - generate a real RSA key (OpenDKIM needs a valid key)
DKIM_PATH="${SECRETS_DIR}/secret_opendkim_key.txt"
if [[ ! -f "${DKIM_PATH}" ]]; then
  openssl genrsa 2048 2>/dev/null > "${DKIM_PATH}"
  echo "Created: secret_opendkim_key.txt (RSA 2048)"
fi

echo "All secrets ready in ${SECRETS_DIR}"
