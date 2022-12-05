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

## Useful Commands

Activating edited Docker compose changes

```bash
ansible-playbook --tags compose -i production/hosts green_nesono.yml
```

Test the HTTP service

```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```

Reset docker

```bash
systemctl restart docker.socket docker.service
```

Check what ports are open in the container (no need for ss to be installed in the container)

```bash
sudo nsenter -t $(docker inspect -f '{{.State.Pid}}' <container_name_or_id>) -n ss -tunap
```