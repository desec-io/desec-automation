# Automated Deployment of deSEC Services

## Install Frontend Nameservers and Manage VPN Keys

Follow these steps to install desec-ns on a number of hosts reachable via an anycast network.

### Install ansible on your local host

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

### Install or Update Frontend Servers

To install or update frontend servers, the following information must be supplied:

1. `DESECSTACK_DOMAIN` of the deSEC stack you want to connect to.
1. `DESEC_NS_IPV6_ADDRESS`: IPv6 address the frontend will be reachable under.
1. `DESEC_NS_IPV6_SUBNET`: subnet of `DESEC_NS_IPV6_ADDRESS`, in CIDR notation.

Additionally, the following information may be provided:

1. `DESEC_NS_NAME`: full DNS name under which the name server will be reached.
1. `DESEC_NS_SIGNALING_DOMAIN_ZONE_PRIVATE_KEY_B64`: base64 encoded private key for signing signaling records.
    Specify to enable desec-ns to provide Signaling Records. If provided, `DESEC_NS_NAME` must be given.
1. `DESEC_NS_LMDB_BACKUP`: full qualified path of created LMDB backup (see above). Specify to enable faster
    synchronization of zone data of desec-ns with desec-stack.

Note that these information may be different for different name server names!

```shell script
ansible-playbook playbooks/frontend.yml -i hosts --limit "frontends_a" \
  -e DESECSTACK_DOMAIN=io \
  -e DESEC_NS_IPV6_ADDRESS="2607:f740:e633:deec::2" \
  -e DESEC_NS_IPV6_SUBNET="2607:f740:e633:deec::/80" \
  -e DESEC_NS_SIGNALING_DOMAIN_ZONE_PRIVATE_KEY_B64=$KEY \
  -e DESEC_NS_NAME=ns1.desec.io \
  -e DESEC_NS_LMDB_BACKUP=lmdb-backup/ns3.sandbox.dedyn.io/desec-ns/lmdb-backup/backup/20201030:161412_dump.tar.gz
```

```shell script
ansible-playbook playbooks/frontend.yml -i hosts --limit "fontends_c" \
  -e DESECSTACK_DOMAIN=io \
  -e DESEC_NS_IPV6_ADDRESS="2607:f740:e00a:deec::2" \
  -e DESEC_NS_IPV6_SUBNET="2607:f740:e00a:deec::/80" \
  -e DESEC_NS_SIGNALING_DOMAIN_ZONE_PRIVATE_KEY_B64=$KEY \
  -e DESEC_NS_NAME=ns2.desec.org \
  -e DESEC_NS_LMDB_BACKUP=lmdb-backup/ns3.sandbox.dedyn.io/desec-ns/lmdb-backup/backup/20201030:161412_dump.tar.gz
```

### Prepare And Deploy VPN PKI

Use the 

- `backuppki` playbook to create a backup of the current PKI (if applicable),
- `newpki` playbook to create a new PKI on your local system,
- `deploypki` playbook to deploy the new PKI onto the frontend NS, 
- `startfrontends` playbook to spin up freshly installed frontends, and/or
- `restartvpn` playbook to reconnect the VPN for already running frontends.

In case something goes wrong, use the `restorepki` playbook to revert to the old PKI.


### Start/restart Frontends

After setting up everything with the instructions above, start/restart the frontends using

```shell script
ansible-playbook playbooks/startfrontends.yml -i hosts
```

### TODO

Ansible playbooks in here can be improved a lot:

- Installation currently for frontend_c
- No configuration of automated updates included yet
- Organization of playbooks can be improved
- Not all playbooks are genuinely idempotent


## Debugging

To run a command (query) against all frontends, the following statement can be used. (Requires zsh.)

```
for NS in $(cat hosts | grep -vE '^$|\[|digga')
(echo -n "$NS: "; dig CDNSKEY _dsboot.desec.io._signal.ns2.desec.org @$NS +short; echo)
```
