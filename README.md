# Nesono Infrastructure Readme

This repository is used to provision my personal servers

## Node Provisioning

Run the following command to deploy to production

```bash
ansible-playbook -i production/hosts green_nesono.yml
```


## K0s Prerequisites

Install ansible and ansible-lint (e.g. `sudo pacman -S ansible ansible-lint`).
You can use ssh port forwarding for convenience.
```bash
ssh -N -L localhost:6443:localhost:6443 green
```

## Traefik Ingress Controller and MetalLB configuration

Make sure you have the following snippet in your clipboad to modify your `k0s.yaml` to include the following information:
```yaml
  extensions:
    helm:
      repositories:
      - name: traefik
        url: https://helm.traefik.io/traefik
      - name: bitnami
        url: https://charts.bitnami.com/bitnami
      charts:
      - name: traefik
        chartname: traefik/traefik
        version: "10.3.2"
        namespace: default
      - name: metallb
        chartname: bitnami/metallb
        version: "2.5.4"
        namespace: default
        values: |2
          configInline:
            address-pools:
            - name: generic-cluster-pool
              protocol: layer2
              addresses:
              - 5.9.198.112/29
```

## Install k0s

The installation routine has been taken from the manual install here:
[install|https://docs.k0sproject.io/v1.23.1+k0s.1/install/]

```bash
curl -sSLf https://get.k0s.sh | sudo sh
sudo mkdir -p /etc/k0s
sudo k0s config create > /etc/k0s/k0s.yaml
```

Edit the configuration file to contain the Traefik and MetalLB configuration from below.

```bash
nano /etc/k0s/k0s.yaml
sudo k0s install controller --single -c /etc/k0s/k0s.yaml
sudo k0s start
```

## Enable Remote Access

Copy the configuration from the server:

```bash
scp green:/var/lib/k0s/pki/admin.conf ~/admin.conf
export KUBECONFIG=~/admin.conf
```

## Install Cert-Manager

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
```

Apply the nesono kubernetes configuration with `kubectl apply -f the.issing.link.yml`

# Useful Commands

Test the HTTP service
```bash
curl -kivL -H 'Host: the.issing.link' 'http://5.9.198.114'
```
