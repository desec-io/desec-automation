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
we will use fra-1.a.desec.io frontend to obtain a backup.

```shell script
ansible-playbook playbooks/stopbgp.yml -i hosts --limit="fra-1.a.desec.io"
ansible-playbook playbooks/backuplmdb.yml -i hosts --limit="fra-1.a.desec.io"
ansible-playbook playbooks/startbgp.yml -i hosts --limit="fra-1.a.desec.io"
```

### Install or Update Frontend Servers

Copy `hosts/.secrets.yml.dist` to `hosts/secrets.yml` and fill in the values:

1. `DESEC_NS_SIGNALING_DOMAIN_ZONE_PRIVATE_KEY_B64`: base64 encoded private key for signing signaling records.
    Specify to enable desec-ns to provide Signaling Records.
1. `DESEC_NS_COOKIES_SECRET`:

Remaining configuration values can be found in `all.yml` and are specific to the desec.io deployment of this software.
Deployment elsewhere needs adjustment of these values.

### Update Procedure

Be careful to **not** run any of the playbooks below without the `limit` parameter!

1. Shut down BGP for Group 1

    ```shell script
    ansible-playbook playbooks/stopbgp.yml -i hosts --limit="a1 c1"
    ```

1. Update software for Group 1

    ```shell script
    ansible-playbook playbooks/frontend.yml -i hosts --limit "a1 c1"


1. Recreate containers for Group 1

    ```shell script
    ansible-playbook playbooks/startfrontends.yml -i hosts --limit "a1 c1"
    ```

1. Test everything works as expected in Group 1
1. Re-enable BGP for Group 1

    ```shell script
    ansible-playbook playbooks/startbgp.yml -i hosts --limit="a1 c1"
    ```
    
1. Repeat for Group 2 (`--limit="a2 c2"`)

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
