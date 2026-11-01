#!/usr/bin/env python3
"""Isolated security migration test. Requires Docker, Jinja2 and PyYAML."""
import imaplib
import json
import os
from pathlib import Path
import shutil
import smtplib
import ssl
import subprocess
import tempfile
import time

import jinja2
import yaml

ROOT = Path(__file__).resolve().parents[2]
ROLE = ROOT / "roles/compose"
NAME = f"mail-security-test-{os.getpid()}"


def run(*args, input=None):
    return subprocess.check_output(args, input=input, text=True, stderr=subprocess.STDOUT, timeout=180)


def docker(*args, input=None):
    return run("docker", *args, input=input).strip()


def wait_for(fn):
    deadline = time.monotonic() + 60
    while True:
        try:
            return fn()
        except (subprocess.CalledProcessError, OSError, imaplib.IMAP4.error):
            if time.monotonic() >= deadline:
                raise
            time.sleep(1)


def port(container, target):
    value = json.loads(docker("inspect", container))[0]
    return int(value["NetworkSettings"]["Ports"][target][0]["HostPort"])


compose = yaml.safe_load((ROLE / "files/docker-compose.yaml").read_text())
services = compose["services"]
assert services["dovecot"]["image"] == "dovecot/dovecot:2.4.5-root"
with tempfile.TemporaryDirectory(prefix="mail-security-") as directory:
    temp = Path(directory)
    shutil.copy(ROLE / "files/dovecot/dovecot.conf", temp / "dovecot.conf")
    # Only the fixture exposes LMTP over TCP; production keeps its UNIX socket.
    with (temp / "dovecot.conf").open("a") as f:
        f.write("\nservice lmtp {\n  inet_listener fixture {\n    port = 24\n  }\n}\n")
    env = jinja2.Environment()
    env.filters["to_json"] = json.dumps
    for source in (ROLE / "templates/dovecot").glob("*.j2"):
        rendered = env.from_string(source.read_text()).render(
            mysql_mail_user="fixture", mysql_mail_password="fixture",
            vmail_user_id=3000, mail_group_id=8,
        )
        (temp / source.name.removesuffix(".j2")).write_text(rendered)
    run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(temp / "key.pem"), "-out", str(temp / "fullchain.pem"),
        "-days", "1", "-subj", "/CN=localhost")
    try:
        docker("network", "create", NAME)
        docker("volume", "create", NAME)
        docker("run", "-d", "--name", NAME + "-db", "--network", NAME,
               "--network-alias", "mysql_mail",
               "-e", "MYSQL_ROOT_PASSWORD=fixture", "-e", "MYSQL_DATABASE=mailserver",
               "-e", "MYSQL_USER=fixture", "-e", "MYSQL_PASSWORD=fixture", "mysql:8.4")
        wait_for(lambda: docker("exec", NAME + "-db", "mysql", "-uroot", "-pfixture",
                                "-e", "SELECT 1"))
        password = docker("run", "--rm", "--network", "none", "--entrypoint", "doveadm",
                          services["dovecot"]["image"], "pw", "-s", "MD5-CRYPT", "-p", "fixture")
        sql = f"""
CREATE TABLE mailbox (username VARCHAR(255) PRIMARY KEY, password VARCHAR(255),
maildir VARCHAR(255), quota BIGINT, active INT);
CREATE TABLE quota2 (username VARCHAR(255) PRIMARY KEY,
bytes BIGINT NOT NULL DEFAULT 0, messages BIGINT NOT NULL DEFAULT 0);
INSERT INTO mailbox VALUES ('test@example.test', '{password}',
'test@example.test/', 10485760, 1);
"""
        docker("exec", "-i", NAME + "-db", "mysql", "-uroot", "-pfixture", "mailserver", input=sql)
        docker("run", "-d", "--name", NAME + "-mail", "--network", NAME,
               "-p", "127.0.0.1::993", "-p", "127.0.0.1::24",
               "-v", f"{temp}:/etc/dovecot:ro", "-v", f"{temp}:/etc/dovecot_certs:ro",
               "-v", f"{NAME}:/srv/mail",
               "--entrypoint", "sh", services["dovecot"]["image"],
               "-c", "mkdir -p /var/spool/mail/private; chown 3000:8 /srv/mail; exec dovecot -F")
        context = ssl._create_unverified_context()  # disposable self-signed fixture only

        def login():
            client = imaplib.IMAP4_SSL("127.0.0.1", port(NAME + "-mail", "993/tcp"),
                                      ssl_context=context, timeout=10)
            client.login("test@example.test", "fixture")
            return client

        client = wait_for(login)
        client.logout()
        print("Dovecot: TLS IMAP and SQL password authentication passed", flush=True)

        # Exercise ManageSieve's script compiler via the same on-disk storage.
        docker("exec", NAME + "-mail", "sh", "-c",
               "mkdir -p /srv/mail/test@example.test/sieve; "
               "printf 'require [\"fileinto\"]; fileinto \"Junk\";\n' "
               "> /srv/mail/test@example.test/sieve/fixture.sieve; "
               "ln -s sieve/fixture.sieve /srv/mail/test@example.test/dovecot.sieve; "
               "chown -R 3000:8 /srv/mail/test@example.test")
        docker("exec", NAME + "-mail", "sievec",
               "/srv/mail/test@example.test/sieve/fixture.sieve")
        with smtplib.LMTP("127.0.0.1", port(NAME + "-mail", "24/tcp"), timeout=10) as lmtp:
            rejected = lmtp.sendmail("sender@example.test", ["test@example.test"],
                                     "From: sender@example.test\r\n"
                                     "To: test@example.test\r\nSubject: fixture\r\n\r\nhello\r\n")
            assert not rejected, rejected
        client = login()
        status, count = client.select("Junk")
        assert status == "OK" and count == [b"1"], (status, count)
        client.logout()
        usage = docker("exec", NAME + "-db", "mysql", "-uroot", "-pfixture", "-N",
                       "mailserver", "-e",
                       "SELECT bytes,messages FROM quota2 WHERE username='test@example.test'")
        assert any(line.split()[-1:] == ["1"] for line in usage.splitlines()), usage
        print("Dovecot: LMTP, Sieve filing, UID 3000/GID 8, and SQL quota mirror passed", flush=True)
    except Exception:
        try:
            print(docker("logs", NAME + "-mail"))
        except subprocess.CalledProcessError:
            pass
        raise
    finally:
        for suffix in ("-mail", "-db"):
            subprocess.run(["docker", "rm", "-f", NAME + suffix], capture_output=True, timeout=30)
        subprocess.run(["docker", "volume", "rm", NAME], capture_output=True, timeout=30)
        subprocess.run(["docker", "network", "rm", NAME], capture_output=True, timeout=30)
print("Dovecot migration validation passed.")
