# Nesono Infrastructure Readme

This repository is used to provision my personal servers

## Prerequisites

Install ansible and ansible-lint (e.g. `sudo pacman -S ansible ansible-lint`).
You can use ssh port forwarding for convenience.
```bash
ssh -N -L localhost:6443:localhost:6443 green
```

## Install MetalLB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml
```

## Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.48.1/deploy/static/provider/baremetal/deploy.yaml
```

## Install Cert-Manager

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
```

## Deployment

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
