<?php
$CONF['database_type'] = 'pgsql';
$CONF['database_host'] = 'pgsql';
$CONF['database_port'] = '';
$CONF['database_user'] = file_get_contents('/run/secrets/mail_postgres_user');
$CONF['database_password'] = file_get_contents('/run/secrets/mail_postgres_password');
$CONF['database_name'] = 'mailserver';
$CONF['setup_password'] = file_get_contents('/run/secrets/mail_postfixadmin_setup_password');
$CONF['smtp_server'] = 'localhost';
$CONF['smtp_port'] = '25';
$CONF['encrypt'] = 'md5crypt';
$CONF['configured'] = true;
?>
