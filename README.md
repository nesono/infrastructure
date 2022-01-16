# Nesono Infrastructure Readme

This repository is used to provision my personal servers

# Prerequisites

Install ansible and ansible-lint (e.g. `sudo pacman -S ansible ansible-lint`).
Install the ansible requirements using
```bash
ansible-galaxy install -r requirements.yml
```

# Deployment

Run the following command to deploy to production

```bash
ansible-playbook -i production/hosts green_nesono.yml
```

Copy the file `the.issing.link.yml` to the server and apply it with `kubectl apply -f the.issing.link.yml`

# Useful Commands

Test the HTTP service
```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```
