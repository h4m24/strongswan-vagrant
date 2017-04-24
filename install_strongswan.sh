#!/bin/bash
set -e -o
export DEBIAN_FRONTEND=noninteractive
# install packages
sudo apt-get -qq update
sudo apt-get -qq install strongswan strongswan-plugin-eap-mschapv2 moreutils  -y


# create cert dir
sudo mkdir vpn-certs
 cd vpn-certs

# generate certs CA
sudo ipsec pki --gen --type rsa --size 4096 --outform pem > server-root-key.pem
sudo chmod 600 server-root-key.pem

# create CA
sudo ipsec pki --self --ca --lifetime 3650 \
--in server-root-key.pem \
--type rsa --dn "C=US, O=VPN Server, CN=VPN Server Root CA" \
--outform pem > server-root-ca.pem

# create key for cert
sudo ipsec pki --gen --type rsa --size 4096 --outform pem > vpn-server-key.pem


# create cert
sudo ipsec pki --pub --in vpn-server-key.pem \
--type rsa | ipsec pki --issue --lifetime 1825 \
--cacert server-root-ca.pem \
--cakey server-root-key.pem \
--dn "C=US, O=VPN Server, CN=strongswan.vagrant" \
--san "strongswan.vagrant" \
--flag serverAuth --flag ikeIntermediate \
--outform pem > vpn-server-cert.pem

# copy to ipsec
sudo cp ./vpn-server-cert.pem /etc/ipsec.d/certs/vpn-server-cert.pem
sudo cp ./vpn-server-key.pem /etc/ipsec.d/private/vpn-server-key.pem

# fix perm
sudo chown root /etc/ipsec.d/private/vpn-server-key.pem
sudo chgrp root /etc/ipsec.d/private/vpn-server-key.pem
sudo chmod 600 /etc/ipsec.d/private/vpn-server-key.pem


# truncat conf file
echo '' | sudo tee /etc/ipsec.conf


# add config
sudo cat << EOF > /etc/ipsec.conf
config setup
    charondebug="ike 4, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    ike=aes256-sha1-modp1024,3des-sha1-modp1024!
    esp=aes256-sha1,3des-sha1!
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=@strongswan.vagrant
    leftcert=/etc/ipsec.d/certs/vpn-server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightdns=8.8.8.8,8.8.4.4
    rightsourceip=10.10.10.0/24
    rightsendcert=never
    eap_identity=%identity
EOF


# config auth
sudo cat << EOF >/etc/ipsec.secrets
strongswan.vagrant : RSA "/etc/ipsec.d/private/vpn-server-key.pem"
admin %any% : EAP "admin"

EOF




sudo ipsec reload
