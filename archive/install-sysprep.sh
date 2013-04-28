#!/bin/bash

# Ubuntu 12.10
# This script will configure your system hostname, networking, default user, SSH, postfix, fail2ban, monit, and firewall.

function check_root() {
  if [ ! "`whoami`" = "root" ]
  then
    echo "Error: This script must be run as root."
    exit 1
  fi
}

check_root

echo "User to Create?"
read USERNAME

echo "User Password?"
read PASSWORD

echo "Hostname?"
read HOSTNAME

echo "Domain Name?"
read DOMAIN

echo "Admin Email Address?"
read ADMINEMAIL

echo "SSH Port?"
read SSHPORT

echo "SSH Key?"
read SSHKEY

echo "Private IP 192.168.XXX.XXX?"
read PRIVATEIP

echo "Private IP Netmask?"
read NETMASK

IPADDRESS=$(ifconfig eth0 | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')

# update system hostname and add to hosts file
echo $HOSTNAME > /etc/hostname
hostname -F /etc/hostname
echo -e "\n127.0.0.1 $HOSTNAME $HOSTNAME.local" >> /etc/hosts
echo -e "$IPADDRESS $HOSTNAME.$DOMAIN" >> /etc/hosts

# set timezone to UTC
ln -s -f /usr/share/zoneinfo/UTC /etc/localtime

# run system updates
aptitude update
aptitude -y full-upgrade

# create a new user
useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers
usermod -a -G adm $USERNAME

# install postfix for local mail (only listens on local interface)
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string localhost" | debconf-set-selections
echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
aptitude -y install postfix mailutils
/usr/sbin/postconf -e "inet_interfaces = loopback-only"

# configure root alias
echo "root: $ADMINEMAIL" >> /etc/aliases
echo "$USERNAME: root" >> /etc/aliases

touch /tmp/restart-postfix

# delete unneeded users from /etc/passwd
deluser irc
deluser games
deluser news
deluser uucp
deluser proxy
deluser list
deluser gnats

# modify ssh config
sed -i "s/^Port 22/Port $SSHPORT/" /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin no/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#.*PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config
echo "AllowUsers $USERNAME" >> /etc/ssh/sshd_config #only allow access from $USERNAME

# add ssh keys
USER_HOME="/home/$USERNAME"
sudo -u "$USERNAME" mkdir "$USER_HOME/.ssh"
sudo -u "$USERNAME" touch "$USER_HOME/.ssh/authorized_keys"
sudo -u "$USERNAME" echo "$SSHKEY" >> "$USER_HOME/.ssh/authorized_keys"

# update ssh key permissions
chmod 0600 "$USER_HOME/.ssh/authorized_keys"
chmod 0700 "$USER_HOME/.ssh"

touch /tmp/restart-ssh

# disable atd scheduler service
stop atd
mv /etc/init/atd.conf /etc/init/atd.conf.noexec

# tweak sysctl settings
cat >>/etc/sysctl.conf <<EOF
# Block SYN attacks
net.ipv4.tcp_syncookies = 1
EOF

# install and configure fail2ban
aptitude -y install fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i "s/^ignoreip = .*/ignoreip = 127.0.0.1 $PRIVATEIP/" /etc/fail2ban/jail.local
sed -i "s/^destemail = .*/destemail = $ADMINEMAIL/" /etc/fail2ban/jail.local
sed -i "s/^action = %(action_)s/action = %(action_mwl)s/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh-ddos\]$/,/^\[/s/port[[:blank:]]*=.*/port = $SSHPORT/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh-ddos\]$/,/^\[/s/enabled[[:blank:]]*=.*/enabled = true/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh\]$/,/^\[/s/port[[:blank:]]*=.*/port = $SSHPORT/" /etc/fail2ban/jail.local
touch /tmp/restart-fail2ban

# install git
aptitude -y install git-core

# install monit
aptitude -y install monit

cat > /etc/monit/monitrc <<END
# set polling interval
set daemon 120
  with start delay 240

# default log file
set logfile /var/log/monit.log

# event queue config in case mail server is down
set eventqueue
  basedir /var/monit
  slots 100

# mail server config
set mailserver localhost

# mail format config
set mail-format { from: monit@`hostname -f` }

# default alert email address
set alert $ADMINEMAIL

# additional config files to load
include /etc/monit/conf.d/*
END

if [ ! -d "/etc/monit/conf.d/" ]; then
  mkdir -p /etc/monit/conf.d/
fi

cat > /etc/monit/conf.d/system <<END
check system `hostname -f`
  if loadavg (1min) > 4 then alert
  if loadavg (5min) > 4 then alert
  if memory usage > 90% then alert
  if cpu usage (user) > 70% then alert
  if cpu usage (system) > 30% then alert
  if cpu usage (wait) > 20% then alert
check filesystem rootfs with path /
  if space > 80% then alert
END

cat > /etc/monit/conf.d/ssh <<END
check process sshd with pidfile /var/run/sshd.pid
  start program "/etc/init.d/ssh start"
  stop program "/etc/init.d/ssh stop"
  if failed port $SSHPORT protocol ssh then restart
  if 5 restarts within 5 cycles then timeout
END

cat > /etc/monit/conf.d/postfix <<END
check process postfix with pidfile /var/spool/postfix/pid/master.pid
  start program = "/etc/init.d/postfix start"
  stop program  = "/etc/init.d/postfix stop"
  if cpu > 60% for 2 cycles then alert
  if cpu > 80% for 5 cycles then restart
  if totalmem > 200.0 MB for 5 cycles then restart
  if children > 250 then restart
  if loadavg(5min) greater than 10 for 8 cycles then stop
  if failed host localhost port 25 type tcp protocol smtp with timeout 15 seconds then alert
  if 3 restarts within 5 cycles then timeout
END

touch /tmp/restart-monit

# install ufw firewall
sudo aptitude -y install ufw

# set default rules: deny all incoming traffic, allow all outgoing traffic
ufw default deny incoming
ufw default allow outgoing
ufw logging on

# open port for ssh, http, and https
ufw allow $SSHPORT/tcp
ufw allow http/tcp
ufw allow https/tcp

# cleanup
aptitude autoclean

# restarts services that have a restart-service_name file in /tmp
for service_name in $(ls /tmp/ | grep restart-* | cut -d- -f2-10); do
  service $service_name restart
  rm -f /tmp/restart-$service_name
done

# enable firewall
echo y|ufw enable

echo "Setup complete. Please logout and re-login as the new user you created. Root access via SSH is no longer enabled."
exit
