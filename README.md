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
