# Automated Deployment of deSEC Services

`bootstrap.sh` can be used to install desec-stack and desec-slave on freshly installed servers.

## Install deSEC Stack

**Beware!** This guide contains destructive commands. Use with caution.

**Attention.** This guide does not cover VPN setup.

To prepare installation, get a shell ready and setup the configuration:

```shell script
bash  # start a new shell as it will quit on error  # TODO fix this inconvenience
source bootstrap.sh

IP4_NS1=127.1.0.1
IP4_NS2=127.1.0.2
EMAIL=desec@example.com
TOKEN=kwki6aWtvwX5tV-xQq_oeeKFxks6FtBb
DOMAIN=example.dedyn.io
``` 

The exact installation routine depends on the circumstances, please see below.

### As Root on a Fresh System

Execute the following steps as root. Note that this will install more than a minimum set of dependencies, but also 
include deSEC's staff SSH keys, zsh, and other perks. To avoid the clutter, skip to the non-root instructions.

In above shell, run

```shell script
backend
```

### As User / on a Development System

All commands in this section must be executed in the shell started above. Feel free to skip commands that you do not 
want or do not need.

1. To install deSEC staff SSH keys for root, execute `sudo _keys` (optional).
1. To install zsh and shell-perks, execute `sudo _shell` (optional).
1. To install desec-stack/desec-slave dependencies (Debian/Ubuntu), execute `sudo _host` (required). Note that this will mess
    with APT settings and **your root password**, as well as delete all docker data. 
1. To setup the DNS using a deSEC.io-Account, run `_dns`. (Yes we are nesting a desec-stack in a desec-stack.)
1. To obtain certificates via Let's Encrypt, run `_certs`.
1. To install and configure desec-stack, run `_stack`.

### With Minimal Side Effects

**Caution!** While having fewer side effects, this still stops all your docker container.

To avoid data loss and impact on the system, install the dependencies manually,

```shell script
apt update
apt install -y \
    curl \
    git \
    httpie \
    jq \
    libmysqlclient-dev \
    python3-dev \
    python3-venv \
    docker.io \
    docker-compose \
    certbot \
    acpid
```

Then run `_dns`, `_certs`, `_stack` to configure the DNS, acquire certificates, and install and configure desec-stack. 


## Install Frontend Nameservers and Manage VPN Keys
### Install ansible

```
apt install ansible
ansible-galaxy collection install community.general
```

### Hosts File

This repository contains a file of all deSEC hosts. Make sure it matches your expectations.


### Obtain Current lmdb Backup

To speed up synchronization and keep server load low, it is important to install new frontend nodes with an up-to-date
database. Such database can be obtained from any existing frontend that can be shut down. In this example,
we will use the sandbox frontend to obtain a backup.

```shell script
ansible-playbook playbooks/backuplmdb.yml -i hosts
```

### Prepare Frontend Servers

To deactivate default DNS resolver occupying port 53, install dependencies, update packages, and clone the frontend 
repository, use the install playbook. 
It requires the following information to be supplied:

1. `DESECSTACK_DOMAIN` of the deSEC stack you want to connect to.
1. `DESECNS_IPV6_ADDRESS`: IPv6 address the frontend will be reachable under.
1. `DESECNS_IPV6_SUBNET`: subnet of `DESECNS_IPV6_ADDRESS`, in CIDR notation.
1. `DESEC_LMDB_BACKUP`: full qualified path of created LMDB backup (see above).

```shell script
ansible-playbook playbooks/frontend.yml -i hosts \
  -e DESECSTACK_DOMAIN=io \
  -e DESECNS_IPV6_ADDRESS="2607:f740:e00a:deec::2" \
  -e DESECNS_IPV6_SUBNET="2607:f740:e00a:deec::/80" \
  -e DESEC_LMDB_BACKUP=lmdb-backup/ns3.sandbox.dedyn.io/desec-slave/lmdb-backup/backup/20201030:161412_dump.tar.gz
```

### Prepare And Deploy PKI

Use the 

- `backuppki` playbook to create a backup of the current PKI (if applicable),
- `newpki` playbook to create a new PKI on your local system,
- `deploypki` playbook to deploy the new PKI onto the frontend NS, 
- `startfrontends` playbook to spin up freshly installed frontends, and/or
- `restartvpn` playbook to reconnect the VPN for already running frontends.

In case something goes wrong, use the `restorepki` playbook to revert to the old PKI.


### TODO

Ansible playbooks in here can be improved a lot:

- Installation currently for frontend_c
- No configuration of automated updates included yet
- Organization of playbooks can be improved
- Not all playbooks are genuinely idempotent
