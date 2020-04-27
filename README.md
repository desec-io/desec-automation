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
    python3.7-dev \
    python3.7-venv \
    docker.io \
    docker-compose \
    certbot \
    acpid
```

Then run `_dns`, `_certs`, `_stack` to configure the DNS, acquire certificates, and install and configure desec-stack. 


