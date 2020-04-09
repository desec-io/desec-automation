#!/usr/bin/env bash
set -e

# helper functions
_rand() {
  openssl rand -base64 32
}

# check prerequisites for installing the sandbox
_check() {
  # must run as root
  [[ $(id -u) == 0 ]] || (echo "Must run as root."; exit 1)

  # must have environment variables set up
  [[ -n "${DOMAIN}" ]] || (echo "Please set DOMAIN so we can use desec.\$DOMAIN and {ns1,ns2}.\$DOMAIN as hostnames."; exit 1)
}

# setup SSH keys
_keys() {
  mkdir -p ~/.ssh/
  cat >> ~/.ssh/authorized_keys << EOF
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAsrjWFICTvvODXJcGg0wA7lCutqMO83wNS7AQg4lO5cLu2WIP867OY5tuA6sCyndZ0Yxu4gH5dsc9aMM83Cvi6FurN/gXL8m85XKVJhe/q/lSbdI4/n4/MXg3swZHEhjolFaxxjzmX2ZFbhaGq3+Eg0z2ljlmTbEED11ll0fnwpMNCPtNV1XdT+Y+zBkrRxDuoMIu28Ycj/KTi+4v94ietdF6WUyEZBOCxQhr7zGkDQx/ju1dEKcFhMCIsm9qGp/cooGLnqOM7y8B2mz6mPBOOozTDPEB1QtTEGKoGxa7Sf7C9YAKyWPB5zPKWtWmq8NhVhPdzAxZzi+oCEsGBb2xkw== nils@tp
EOF
  chmod 700 ~/.ssh/
  chmod 600 ~/.ssh/authorized_keys
}

# setup root user: install zsh
_shell() {
  apt update
  apt install -y zsh
  chsh -s "$(command -v zsh)"

  wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh
  rm -rf .oh-my-zsh
  sh install.sh --unattended
  wget -O .oh-my-zsh/themes/agnoster.zsh-theme https://raw.githubusercontent.com/agnoster/agnoster-zsh-theme/master/agnoster.zsh-theme
  cat > .zshrc << EOF
export ZSH="/root/.oh-my-zsh"
ZSH_THEME="agnoster"
plugins=(git)
source \$ZSH/oh-my-zsh.sh
prompt_lab() {
  prompt_segment 'black' 'default' '🧪🧪🧪🧪🧪'
}
AGNOSTER_PROMPT_SEGMENTS=("prompt_lab" "\${AGNOSTER_PROMPT_SEGMENTS[@]}")
AGNOSTER_PROMPT_SEGMENTS[3]=
EOF
}

# setup host
_setup() {
  # install dependencies
  apt update
  apt dist-upgrade -y
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
    acpid \

  # unset root password
  passwd -d -l root

  # TODO disable password authentication in /etc/ssh/sshd_config: PasswordAuthentication no

  # graceful restarts
  systemctl enable acpid && service acpid start

  # unattended upgrades
  echo 'APT::Periodic::RandomSleep "43200";' >> /etc/apt/apt.conf.d/10periodic
  {
    echo 'APT::Periodic::Update-Package-Lists "1";'
    echo 'APT::Periodic::Download-Upgradeable-Packages "1";'
    echo 'APT::Periodic::AutocleanInterval "7";'
    echo 'APT::Periodic::Unattended-Upgrade "1";'
  } >> /etc/apt/apt.conf.d/20auto-upgrades
  {
    echo 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";'
    echo 'Unattended-Upgrade::Automatic-Reboot "true";'
    echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";'
  } >> /etc/apt/apt.conf.d/50unattended-upgrades

  # configure docker
  echo '{"userland-proxy": false}' >> /etc/docker/daemon.json
  # make sure the file resulting from the above command makes sense
  systemctl restart docker
  docker system prune -a
  # make sure Docker starts on reboot (and restarts containers with restart enabled)
  systemctl enable docker
}

# setup the DNS
_dns() {
  # TODO add v6
  # TODO Add DS Records
  IP4_BACKEND=$(curl https://checkipv4.dedyn.io/)
  http POST https://desec.io/api/v1/domains/ Authorization:"Token ${TOKEN}" name="$DOMAIN"
  http PUT https://desec.io/api/v1/domains/${DOMAIN}/rrsets/ Authorization:"Token ${TOKEN}" << EOF
[
    {"type": "A",    "ttl":3600, "records": ["$IP4_NS1"], "subname": "ns1"},
    {"type": "A",    "ttl":3600, "records": ["$IP4_NS2"], "subname": "ns2"},
    {"type": "A",    "ttl":3600, "records": ["$IP4_BACKEND"], "subname": "desec"},
    {"type": "A",    "ttl":3600, "records": ["$IP4_BACKEND"], "subname": "dedyn"},
    {"type": "NS",   "ttl":3600, "records": ["ns1.$DOMAIN", "ns2.$DOMAIN"], "subname": "dedyn"},
    {"type": "A",    "ttl":3600, "records": ["$IP4_BACKEND"], "subname": "*.desec"}
]
EOF
}

_stack() {
  # get desec-stack
  git clone https://github.com/desec-io/desec-stack.git
  rm -rf desec-stack/certs
  mv certs desec-stack/
  cd desec-stack || exit

  # set up environment
  touch .env
  cat >> .env << EOF
DESECSTACK_DOMAIN=$DOMAIN
DESECSTACK_NS=ns1.$DOMAIN ns2.$DOMAIN
DESECSTACK_IPV4_REAR_PREFIX16=172.16
DESECSTACK_IPV6_SUBNET=fda8:7213:9e5e:1::/80
DESECSTACK_IPV6_ADDRESS=fda8:7213:9e5e:1::0642:ac10:0080
DESECSTACK_WWW_CERTS=./certs
DESECSTACK_DBMASTER_CERTS=./certs
DESECSTACK_API_ADMIN=$EMAIL
DESECSTACK_API_SEPA_CREDITOR_ID=SANDBOX_SEPA_CREDITOR_ID
DESECSTACK_API_SEPA_CREDITOR_NAME=SANDBOX_SEPA_CREDITOR_NAME
DESECSTACK_API_EMAIL_HOST=
DESECSTACK_API_EMAIL_HOST_USER=
DESECSTACK_API_EMAIL_HOST_PASSWORD=
DESECSTACK_API_EMAIL_PORT=
DESECSTACK_API_SECRETKEY=$(_rand)
DESECSTACK_API_PSL_RESOLVER=9.9.9.9
DESECSTACK_DBAPI_PASSWORD_desec=$(_rand)
DESECSTACK_MINIMUM_TTL_DEFAULT=1
DESECSTACK_DBLORD_PASSWORD_pdns=$(_rand)
DESECSTACK_NSLORD_APIKEY=$(_rand)
DESECSTACK_NSLORD_CARBONSERVER=
DESECSTACK_NSLORD_CARBONOURNAME=
DESECSTACK_NSLORD_DEFAULT_TTL=3600
DESECSTACK_DBMASTER_PASSWORD_pdns=$(_rand)
DESECSTACK_NSMASTER_APIKEY=$(_rand)
DESECSTACK_NSMASTER_CARBONSERVER=37.252.122.50
DESECSTACK_NSMASTER_CARBONOURNAME=$DOMAIN
DESECSTACK_WATCHDOG_SLAVES=ns1.example.org ns2.example.net
DESECSTACK_PROMETHEUS_PASSWORD=$(_rand)
EOF
  docker-compose run openvpn-server openvpn --genkey --secret /dev/stdout > openvpn-server/secrets/ta.key
  docker-compose pull
}

_certs() {
  (
    mkdir -p ~/bin
    cd ~/bin
    curl https://raw.githubusercontent.com/desec-utils/certbot-hook/master/hook.sh > desec_certbot_hook.sh
    chmod +x desec_certbot_hook.sh
    cd
    touch .dedynauth; chmod 600 .dedynauth
    echo DEDYN_TOKEN=${TOKEN} >> .dedynauth
    echo DEDYN_NAME=${DOMAIN} >> .dedynauth
  )
  (
    cd
    certbot \
      --config-dir certbot/config --logs-dir certbot/logs --work-dir certbot/work \
      --manual --text --preferred-challenges dns \
      --manual-auth-hook ~/bin/desec_certbot_hook.sh \
      --manual-cleanup-hook ~/bin/desec_certbot_hook.sh \
      --server https://acme-v02.api.letsencrypt.org/directory \
      --non-interactive --manual-public-ip-logging-ok --agree-tos --email "$EMAIL" \
      -d "*.${DOMAIN}" certonly
  )
  (
    mkdir -p certs
    cd certs
    for SUBNAME in desec www.desec get.desec checkip.dedyn checkipv4.dedyn checkipv6.dedyn dedyn www.dedyn update.dedyn update6.dedyn
    do
        ln -s cer ${SUBNAME}.${DOMAIN}.cer
        ln -s key ${SUBNAME}.${DOMAIN}.key
    done

    cp ~/certbot/config/live/${DOMAIN}/fullchain.pem cer
    cp ~/certbot/config/live/${DOMAIN}/privkey.pem key
  )
}

_frontend() {
  systemctl disable systemd-resolved && service systemd-resolved stop
  (
    git clone https://github.com/desec-io/desec-slave.git
    cd desec-slave || exit
    mkdir openvpn-client/secrets
    docker-compose pull

    cat >> .env << EOF
DESECSLAVE_IPV6_SUBNET=$DESECSLAVE_IPV6_SUBNET
DESECSLAVE_IPV6_ADDRESS=$DESECSLAVE_IPV6_ADDRESS
DESECSLAVE_CARBONSERVER=37.252.122.50
DESECSLAVE_CARBONOURNAME=$DOMAIN-$HOST
DESECSLAVE_NS_APIKEY=$(_rand)
DESECSTACK_VPN_SERVER=$DOMAIN
EOF
    echo scp root@desec.\$DOMAIN:desec-stack/openvpn-server/secrets/ta.key pki/
    echo scp pki/ca.crt pki/ta.key pki/issued/$HOST.crt pki/private/$HOST.key root@\$HOST:desec-slave/openvpn-client/secrets/
  )
}

host() {
  _keys
  _shell
  _setup
}

backend() {
  _check
  [[ -n "${IP4_NS1}" ]] || (echo "Please set IP4_NS1."; exit 1)
  [[ -n "${IP4_NS2}" ]] || (echo "Please set IP4_NS2."; exit 1)
  [[ -n "${EMAIL}" ]] || (echo "Please set EMAIL (for LE cert)."; exit 1)
  [[ -n "${TOKEN}" ]] || (echo "Please set TOKEN to an access token for the deSEC.io account controlling the sandbox domain."; exit 1)
  # TODO add check for VPN keys
  host
  _dns
  _certs
  _stack
}

frontend() {
  [[ -n "${HOST}" ]] || (echo "Please set HOST to my hostname."; exit 1)
  [[ -n "${DESECSLAVE_IPV6_SUBNET}" ]] || (echo "Please set DESECSLAVE_IPV6_SUBNET to fd00:deec::/80."; exit 1)
  [[ -n "${DESECSLAVE_IPV6_ADDRESS}" ]] || (echo "Please set DESECSLAVE_IPV6_SUBNET to fd00:deec::2"; exit 1)

  _check
  host
  _frontend
}

vpn() {
  [[ -d easy-rsa ]] && (echo "VPN already configured? Delete easy-rsa directory to start over."; exit 1)
  [[ -n "${DOMAIN}" ]] || (echo "Set DOMAIN to the stack domain"; exit 1)
  git clone https://github.com/OpenVPN/easy-rsa.git
  ln -s easy-rsa/easyrsa3/easyrsa .
  ./easyrsa init-pki
  ./easyrsa build-ca nopass
}

vpn_stack() {
  [[ -d easy-rsa ]] || (echo "VPN not yet configured? Call $(basename "$0") to get started."; exit 1)
  [[ -n "${DOMAIN}" ]] || (echo "Set DOMAIN to the stack domain"; exit 1)
  ./easyrsa gen-req server nopass
  ./easyrsa sign-req client server  # requires interaction
  echo scp pki/issued/server.crt pki/private/server.key pki/ca.crt root@desec.\$DOMAIN:desec-stack/openvpn-server/secrets/
  echo scp root@desec.\$DOMAIN:desec-stack/openvpn-server/secrets/ta.key pki/
}

vpn_frontend() {
  [[ -d easy-rsa ]] || (echo "VPN not yet configured? Call $(basename "$0") to get started."; exit 1)
  [[ -n "${HOST}" ]] || (echo "Set HOST to the frontend name"; exit 1)
  ./easyrsa gen-req $HOST nopass
  ./easyrsa sign-req client $HOST

  # copy certificates (Consider umask)
  echo scp pki/ta.key pki/ca.crt pki/issued/$HOST.crt pki/private/$HOST.key root@$HOST:desec-slave/openvpn-client/secrets/
}
