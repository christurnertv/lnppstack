#!/bin/bash

# LNPP Stack: Installs and configures nginx, php5-fpm, and postgres.
# Tested on Ubuntu 12.10 64bit.

# Site Helper Scripts
# -----------------------------------------------------------------------------
# A great feature of this script are the site helpers that get installed into
# /usr/local/bin. They make it easy to create and manage nginx/php sites. They 
# take care of nginx config, php-fpm config, and even monit config. The 
# site-create script supports automatic git repository creation along with the 
# hooks for deploy-on-push site management.

# Basic Config and System Security
# -----------------------------------------------------------------------------
# - Securing PHP. PHP.ini has been modified per security guidelines.
# - site-install-phpsecinfo script is provide for testing configuration.
# - Securing SSH. Root login and password auth are disabled.
# - Fail2Ban is set up to protect SSH.
# - Firewall is set to block everything but SSH, HTTP, and HTTPS.
# - Monit is installed and configured to monitor important services.

# Warranty and License
# -----------------------------------------------------------------------------
# No warranty, use at your own risk!
# Released under MIT license.

# See Github for more info and to contribute!
# -----------------------------------------------------------------------------
# https://github.com/gizmovation/lnppstack

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
