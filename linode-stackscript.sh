#!/bin/bash

#<udf name="USERNAME" label="User to Create">
#<udf name="PASSWORD" label="User Password">
#<udf name="HOSTNAME" label="Hostname">
#<udf name="DOMAIN" label="Domain Name">
#<udf name="ADMINEMAIL" label="Admin Email">
#<udf name="SSHPORT" label="SSH Port" default="123">
#<udf name="SSHKEY" label="SSH RSA Key">
#<udf name="PRIVATEIP" label="Private IP Address" default="192.168.">
#<udf name="NETMASK" label="Private IP Netmask" default="255.255.128.0">

export linode=true

# download the install script from github
wget https://raw.github.com/gizmovation/lnppstack/master/install-stack.sh -O /tmp/install-stack.sh
chmod +x /tmp/install-stack.sh

# execute the install script
./tmp/install-stack.sh

# cleanup
rm -rf /tmp/*
