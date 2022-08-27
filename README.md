# Nesono Infrastructure Readme

This repository is used to provision my personal servers

## Fresh installation (after FreeBSD Migration)

Start the Hetzner Rescue system

* Login into [hetzner your server|<https://hetzner.your-server.de>]
* Go to Rescue tab, select Linux 64-bit
* Enable Rescue system
* Rememeber Credentials
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
create the files with the correct content - the files shall never be added to
any revisions concrol of course!

Examples of the used files (see the full listing in the file mentioned above):

* `secret_mysql_mail_root_password`
* `secret_mysql_mail_password`
* `secret_mysql_mail_user`
* `secret_postfixadmin_setup_password`

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

In our case, we had to fix some of the data base table definitions /
configurations, mostly the default values for timestamps.

### Install Postfixadmin

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

#### Install Tools

```bash
apt install postgresql-client
apt install mysql-client
apt install pgloader
```

Establish port forwarding with ssh

```bash
ssh -L 3306:10.1.1.3:3306 blue
```

Migrate data

## Useful Commands

Test the HTTP service

```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```

Reset docker

```bash
systemctl restart docker.socket docker.service
```
