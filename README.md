# Nesono Infrastructure Readme

This repository is used to provision my personal servers.
I am using a docker compose setup, since Kubernetes hasn't worked for me out of the box
and Docker compose seemed like a simple alternative that still provides infra
as code (IaC) for my server setup.

All services are defined in one yaml, which is addressed as the `stack` in
Docker compose on the server host.

For http, I am using the `nginx-proxy` setup, in combination with a `docker-gen`
container and the `nginx-proxy-acme` container that handles the letsencrypt certificates.

Note, that I am using a documentation http container for the email setup, that
also has the side effect of fetching the TLS certs, that are then used by the
email server (dovecot and postfix). Hence, the email containers depend on the http
container.

## Fresh installation (after FreeBSD Migration)

Start the Hetzner Rescue system

* Login into [hetzner your server|<https://hetzner.your-server.de>]
* Go to Rescue tab, select Linux 64-bit
* Enable Rescue system
* Remember Credentials
* Go to Reset tab and send `Ctrl-Alt-Del` to server
* Login with rescue credentials as `root@<your.ip.address>`

Create a config file for installimage

```bash
cat <<-ENDOFFILE > installimage.conf
DRIVE1 /dev/sda
DRIVE2 /dev/sdb
SWRAID 1
SWRAIDLEVEL 1
HOSTNAME green.nesono.com
PART   btrfs.raid    btrfs    all
SUBVOL btrfs.raid    @        /
SUBVOL btrfs.raid    @var     /var
SUBVOL btrfs.raid    @svc     /svc
SUBVOL btrfs.raid    @tmp     /tmp
IMAGE /root/.oldroot/nfs/install/../images/Ubuntu-2004-focal-64-minimal.tar.gz
ENDOFFILE
```

Install the image

```bash
installimage -a -c installimage.conf
```

## Create secret files

The following secrets are neccessary during deployment and ansible will try to
fill those based on the task in `roles/compose/tasks/main.yaml`. Make sure you
create the files with the correct content - **the files shall never be added to
any revision control of course!**

Examples of the used files (see the full listing in the file mentioned above):

* `secret_mysql_mail_root_password.txt`
* `secret_mysql_mail_password.txt`
* `secret_mysql_mail_user.txt`
* `secret_postfixadmin_setup_password.txt`
* `secret_opendkim_key.txt`
* `roundcube_db_password.txt`
* `roundcube_db_user.txt`

The files contents can be found in 1Password with the prefix `green:...`.

## Node Provisioning

Install ansible and ansible-lint on your host
(e.g. `sudo pacman -S ansible ansible-lint` or `pip3 install ansible`).

Then run the following command to provision the node.

```bash
ansible-playbook --tags never,all -i production/hosts green_nesono.yml
```

## Setup Postfixadmin

### Restore from Backup

Get the MySQL backup

```bash
jexec db_delado_co mysqldump mailserver --single-transaction > mysqldump.sql
gzip mysqldump.sql
```

You can put this file into the directory `/svc/volumes/mysql_mail_init_db` on
the server. We are mounting this directory into the MySQL Docker container for
automatic initialization.

In our case, we had to fix some database table definitions /
configurations, mostly the default values for timestamps.

### Install Postfixadmin

After running Ansible, you will need os go through the installation process as follows.

#### Generate Postfixadmin Setup Password

1. Visit postfixadmin.nesono.com
2. Fill in the new password in `Generate setup_password` (twice)
3. Press `Generate setup_password hash`
4. Copy the password hash
5. Paste the password hash into the setup password secret file
   `roles/compose/files/secret_mail_postfixadmin_setup_password.txt`
6. Take down the swarm with `docker stack rm services`
7. Run ansible again `ansible-playbook --tags compose -i production/hosts green_nesono.yml`

#### Log in With Setup Password

1. Visit postfixadmin.nesono.com
2. Enter Setup Password
3. Check if hosting environment is ok
4. Setup Superadmin Account

### Copy the Mail data

First rsync of the old mails to the new instance.

```bash
rsync -avz --delete blue:/usr/jails/mail.nesono.com/var/spool/postfix/virtual/ /svc/volumes/mail
```

Once the new mail server works, you can run a final rsync as above.
Keep the old instance disabled and switch DNS entries to the new instance.

Make sure all mail data has the right permissions

```bash
chown -R 1000:8 /svc/volumes/mail
chmod -R u+w /svc/volumes/mail
```

Convenience command to run them all together

```bash
rsync -avz --delete blue:/usr/jails/mail.nesono.com/var/spool/postfix/virtual/ /svc/volumes/mail && \
  chown -R 1000:8 /svc/volumes/mail && \
  chmod -R u+w /svc/volumes/mail
```

## Create DKIM Selector and Key

Create a DKIM txt and key file using the following command.

```bash
opendkim-genkey -t -s 2023-01-04 -d nesono.com,issing.link,...
```

The command above will create two files:
1. `2023-01-04.private` with the private key
2. `2023-01-04.txt` containing the DNS record

You will need to add a DNS record for every domain, using the data in `2023-01-04.txt`. In our example these are
1. `2023-01-04._domainkey.nesono.com`
2. `2023-01-04._domainkey.issing.link`
3. `...`

The file `2023-01-04.txt` contains the DNS TXT record. Here is my example:

```
2023-01-04._domainkey	IN	TXT	( "v=DKIM1; h=sha256; k=rsa; t=y; "
	  "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxW3loYuv7Owf9CSurIKRgtNw0GYQg7RGH41mOgb9VP5vpQNL/V3dtgo8qjkZ7afY81RFyZ48ZSKspGOfBzumJTAECsxeCjmdvpcMTWxwyNZ3uxjkb6JYwfLxh7IYbcu/+Cdcpfdxl2nQ4jx8P6zQZUbLvDKHp2DWic4KJhVdMcWXARYzwRxVZMT4PBB3OJq3aa5h4yUIOqJ+1s"
	  "Vx8Co5N6f6OnVG89zAxTBTx568VVEzhPtpG8TU6JLiCJj1K/0xLmmOu7jJFicdw56dZiZc9vUJ9QiC/Q9m5yclMQAvEeGVQok1Sig1+gqkO18x6f6TJrN2jXzPJHliI1PHR/8ulQIDAQAB" )  ; ----- DKIM key 2023-01-04 for nesono.com
```

You will need to create a TXT record for your domain (`nesono.com` in my example) that points to the host
`2023-01-04._domainkey` and has the value (change the multi-string to a single string - Cloudflare 
will handle the rest): 
```
v=DKIM1; h=sha256; k=rsa; t=y; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxW3loYuv7Owf9CSurIKRgtNw0GYQg7RGH41mOgb9VP5vpQNL/V3dtgo8qjkZ7afY81RFyZ48ZSKspGOfBzumJTAECsxeCjmdvpcMTWxwyNZ3uxjkb6JYwfLxh7IYbcu/+Cdcpfdxl2nQ4jx8P6zQZUbLvDKHp2DWic4KJhVdMcWXARYzwRxVZMT4PBB3OJq3aa5h4yUIOqJ+1sVx8Co5N6f6OnVG89zAxTBTx568VVEzhPtpG8TU6JLiCJj1K/0xLmmOu7jJFicdw56dZiZc9vUJ9QiC/Q9m5yclMQAvEeGVQok1Sig1+gqkO18x6f6TJrN2jXzPJHliI1PHR/8ulQIDAQAB
```

**Note**: I had to move the DNS handling from [Hover](https://www.hover.com) to [Cloudflare](https://www.cloudflare.com),
since Hover did not support the long (>255 characters) TXT record values.  

## Adding SPF Record

Add the following DNS record to your DNS configuration.

* Type: `TXT`
* Name: `@`
* Content: `v=spf1 mx ~all`

## Testing Your Mail Server Spam Tools

Open [Mail-Tester](https://www.mail-tester.com) and check your score. It will show you any issues with 
SPF, DKIM, DMARC, SPAMASSASSIN, Pyzor, etc. 

## Adding a New Mail Domain

1. Add DNS records
   1. TXT `selector._domainkey` `...`
   2. TXT `@` `v=spf1 mx ip4:5.9.123.102 ~all`
   3. TXT `_dmarc` `v=DMARC1;p=reject;pct=100;rua=mailto:dmarc@nesono.com`
2. Add to Postfixadmin (tba)

## Useful Commands

### Testing SMTP Connection w/ STARTTLS

```bash
openssl s_client -starttls smtp -connect smtp.nesono.com:25
```

### Testing SMTP Connection w/o STARTTLS

```bash
openssl s_client -connect smtp.nesono.com:465
```

### Testing IMAP Connection w/o STARTTLS

```bash
openssl s_client -connect imap.nesono.com:993
```

### Testing IMAP Connection w/ STARTTLS

```bash
openssl s_client -starttls imap -connect imap.nesono.com:143
```

### Making ss Available in Container

Install the `iproute2` package:

```bash
apt install iproute2
```

### Make lsof Available in Container

Install the `lsof` package

```bash
apt install lsof
```

### Activating edited Docker compose changes

```bash
ansible-playbook --tags compose -i production/hosts green_nesono.yml
```

### Forcing a Docker Compose Refresh (on the server)

```bash
cd /var/run/docker_compose/services/stack
docker stack deploy --compose-file docker_compose.yml stack
```
### Test the HTTP service

```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```

### Testing opendkim DNS entry

```bash
opendkim-testkey -d nesono.com -s 2023-01-04 -vvv
```

### Testing DNS entries broadly

Using the webservice [DnsViz](https://dnsviz.net)
### Testing dmarc DNS entry

```bash
opendmarc-check nesono.com
```

### Testing Sending Mails With and Without Authentication

Without Auth

```bash
smtp-cli/smtp-cli --server=smtp.nesono.com:25 --verbose --mail-from=jochen@issing.link --to=jochen.issing@issing.link --subject="Invalid $(date)" --body-plain="Invalid $(date), not authenticated!"
```

With Auth

```bash
smtp-cli/smtp-cli --server=smtp.nesono.com:25 --user=jochen@issing.link --verbose --mail-from=jochen@issing.link --to=jochen.issing@issing.link --subject="Valid $(date)" --body-plain="Valid $(date), not authenticated!"
```

### Postfix Mail Queue Commands

Print the queue

```bash
postqueue -p
```

Delete all messages in the queue

```bash
postsuper -d ALL
```


### Reset docker

```bash
systemctl restart docker.socket docker.service
```

### Accessing MySql via Terminal

For instance the mail MySQL server.

```bash
docker exec -ti stack_mysql_mail.1.frfbmnx9pefgfyc2c8n62b43h mysql -p
```

Getting the list of all virtual accounts from the mail server.

```bash
docker exec -ti <container_id> mysql -p -N -B mailserver -e "SELECT username FROM mailbox;"
```
### Check what ports are open in the container (no need for ss to be installed in the container)

```bash
sudo nsenter -t $(docker inspect -f '{{.State.Pid}}' <container_name_or_id>) -n ss -tunap
```

Note: you can run pretty much any host command within the namespace of the container using above command line.

### Testing managesieve login

First, start the connection to the mailserver
```bash
gnutls-cli --starttls -p 4190 mail2.nesono.com
```

This should give you something similar to this output:

```bash
Processed 127 CA certificate(s).
Resolving 'mail2.nesono.com:4190'...
Connecting to '5.9.123.102:4190'...

- Simple Client Mode:

"IMPLEMENTATION" "Dovecot Pigeonhole"
"SIEVE" "fileinto reject envelope encoded-character vacation subaddress comparator-i;ascii-numeric relational regex imap4flags copy include variables body enotify environment mailbox date index ihave duplicate mime foreverypart extracttext"
"NOTIFY" "mailto"
"SASL" ""
"STARTTLS"
"VERSION" "1.0"
OK "Dovecot ready."
```

Then, initiate StartTLS

```bash
STARTTLS
```

And then press `Ctrl-D`, to let gnutls handle the STARTTLS process.
This should give you something similar to this

```bash
> OK "Begin TLS negotiation now."
*** Starting TLS handshake
- Certificate type: X.509
- Got a certificate list of 3 certificates.
- Certificate[0] info:
 - subject `CN=mail2.nesono.com', issuer `CN=R3,O=Let's Encrypt,C=US', serial 0x0415dd4a6e6a2ce9a7931fa2113ed8db9f1b, RSA key 4096 bits, signed using RSA-SHA256, activated `2022-11-29 18:56:08 UTC', expires `2023-02-27 18:56:07 UTC', pin-sha256="2uuU14K+QM4SIUb+oUUSTNCeBVuS8Vb6zmhymbWyxfA="
	Public Key ID:
		sha1:2f592ea0a8bfa8b9f7da21106730c1f68e0398ed
		sha256:daeb94d782be40ce122146fea145124cd09e055b92f156face687299b5b2c5f0
	Public Key PIN:
		pin-sha256:2uuU14K+QM4SIUb+oUUSTNCeBVuS8Vb6zmhymbWyxfA=

- Certificate[1] info:
 - subject `CN=R3,O=Let's Encrypt,C=US', issuer `CN=ISRG Root X1,O=Internet Security Research Group,C=US', serial 0x00912b084acf0c18a753f6d62e25a75f5a, RSA key 2048 bits, signed using RSA-SHA256, activated `2020-09-04 00:00:00 UTC', expires `2025-09-15 16:00:00 UTC', pin-sha256="jQJTbIh0grw0/1TkHSumWb+Fs0Ggogr621gT3PvPKG0="
- Certificate[2] info:
 - subject `CN=ISRG Root X1,O=Internet Security Research Group,C=US', issuer `CN=DST Root CA X3,O=Digital Signature Trust Co.', serial 0x4001772137d4e942b8ee76aa3c640ab7, RSA key 4096 bits, signed using RSA-SHA256, activated `2021-01-20 19:14:03 UTC', expires `2024-09-30 18:14:03 UTC', pin-sha256="C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M="
- Status: The certificate is trusted.
- Description: (TLS1.3-X.509)-(ECDHE-SECP256R1)-(RSA-PSS-RSAE-SHA256)-(AES-256-GCM)
- Session ID: D6:77:98:BC:6B:5A:76:5C:89:37:3B:AC:DD:45:36:CB:FA:80:F5:F5:EF:FE:E6:85:78:37:23:CD:99:0D:58:04
- Options:
"IMPLEMENTATION" "Dovecot Pigeonhole"
"SIEVE" "fileinto reject envelope encoded-character vacation subaddress comparator-i;ascii-numeric relational regex imap4flags copy include variables body enotify environment mailbox date index ihave duplicate mime foreverypart extracttext"
"NOTIFY" "mailto"
"SASL" "PLAIN LOGIN"
"VERSION" "1.0"
OK "TLS negotiation successful."
```

Then, authenticate

```bash
AUTHENTICATE "PLAIN" "<base64_encoded_username_password>"
```

Which takes your username and password encoded with base64, using [this tool](http://pigeonhole.dovecot.org/utilities/sieve-auth-command.pl).

## Further Reading

* [Enabling SASL authentication for Postfix](https://www.postfix.org/SASL_README.html)
* [Set up Managesieve with Dovecot](https://wiki.dovecot.org/Pigeonhole/ManageSieve/Troubleshooting)
* [Part 4: How to Set up SPF and DKIM with Postfix on Ubuntu Server](https://www.linuxbabe.com/mail-server/setting-up-dkim-and-spf)
* [Set Up OpenDMARC with Postfix on Ubuntu to Block Spam/Email Spoofing](https://www.linuxbabe.com/mail-server/opendmarc-postfix-ubuntu)
* [Postfix Relay and Access Control](https://www.postfix.org/SMTPD_ACCESS_README.html)