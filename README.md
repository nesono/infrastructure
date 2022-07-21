# Nesono Infrastructure Readme

This repository is used to provision my personal servers

## Fresh installation (after FreeBSD Migration)

Start the Hetzner Rescue system
* Login into https://hetzner.your-server.de
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
- `mail_postgres_root_password`
- `mail_postgres_password`
- `mail_postgres_user`

## Node Provisioning

Install ansible and ansible-lint on your host
(e.g. `sudo pacman -S ansible ansible-lint` or `pip3 install ansible`).

Then run the following command to provision the node:
```bash
ansible-playbook --tags never,all -i production/hosts green_nesono.yml
```

# Useful Commands

Test the HTTP service
```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```
