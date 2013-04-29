#!/bin/bash

###############################################################################
### required inputs specified by linode stackscript or user input
###############################################################################

if ! $linode; then

  if [ ! "`whoami`" = "root" ]
  then
    echo "Error: This script must be run as root."
    exit 1
  fi

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

fi

IPADDRESS=$(ifconfig eth0 | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')

###############################################################################
### basic system setup
###############################################################################

# update system hostname and add to hosts file
echo $HOSTNAME > /etc/hostname
hostname -F /etc/hostname
echo -e "\n127.0.0.1 $HOSTNAME $HOSTNAME.local" >> /etc/hosts
echo -e "$IPADDRESS $HOSTNAME.$DOMAIN" >> /etc/hosts

# set timezone to UTC
ln -s -f /usr/share/zoneinfo/UTC /etc/localtime

# tweak sysctl settings
cat >>/etc/sysctl.conf <<EOF
# Block SYN attacks
net.ipv4.tcp_syncookies = 1
EOF

# run system updates
aptitude update
aptitude -y full-upgrade

# install git
aptitude -y install git-core

# clone the lnpp stack repo
git clone https://github.com/gizmovation/lnppstack.git /tmp/lnppstack

# copy the helpers
cp /tmp/lnppstack/helpers/* /usr/local/bin/
chmod 755 /usr/local/bin/*

###############################################################################
### create new user and make admin
###############################################################################

useradd -m -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers
usermod -a -G adm $USERNAME

###############################################################################
### install and configure postfix for local mail only
###############################################################################

echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string localhost" | debconf-set-selections
echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
aptitude -y install postfix mailutils
/usr/sbin/postconf -e "inet_interfaces = loopback-only"

# configure root alias
echo "root: $ADMINEMAIL" >> /etc/aliases

touch /tmp/restart-postfix

###############################################################################
### configure and secure ssh (disallow root login, and require rsa key auth)
###############################################################################

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

###############################################################################
### install and configure fail2ban to protect ssh
###############################################################################

aptitude -y install fail2ban

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i "s/^ignoreip = .*/ignoreip = 127.0.0.1 $PRIVATEIP/" /etc/fail2ban/jail.local
sed -i "s/^destemail = .*/destemail = $ADMINEMAIL/" /etc/fail2ban/jail.local
sed -i "s/^action = %(action_)s/action = %(action_mwl)s/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh-ddos\]$/,/^\[/s/port[[:blank:]]*=.*/port = $SSHPORT/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh-ddos\]$/,/^\[/s/enabled[[:blank:]]*=.*/enabled = true/" /etc/fail2ban/jail.local
sed -ri "/^\[ssh\]$/,/^\[/s/port[[:blank:]]*=.*/port = $SSHPORT/" /etc/fail2ban/jail.local

# disable email notification for start/stop events
sed -i '/^actionstart/,+7 s.^.#.' /etc/fail2ban/action.d/sendmail*
sed -i '/^actionstop/,+7 s.^.#.' /etc/fail2ban/action.d/sendmail*

touch /tmp/restart-fail2ban

###############################################################################
### install postgresql
###############################################################################

aptitude -y install postgresql

###############################################################################
### install and configure nginx and php
###############################################################################

aptitude -y install nginx php5 php5-cli php5-pgsql php5-curl php5-mcrypt php5-gd php5-imagick php5-fpm

# stop the services
service nginx stop
service php5-fpm stop

# disable and remove default site
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

# remove the default php-fpm pool
rm -f /etc/php5/fpm/pool.d/www.conf

# create a location for site specific log files
if [ ! -d "/var/log/nginx" ]; then
  mkdir /var/log/nginx
fi

cp -f /tmp/lnppstack/nginx/nginx.conf /etc/nginx/nginx.conf

# create a location for php-fpm pool slowlogs
mkdir /var/log/php-fpm

# create a location for nginx configuration includes
mkdir /etc/nginx/includes

cp /tmp/lnppstack/nginx/location.conf /etc/nginx/includes/location.conf

touch /tmp/restart-nginx

# create directories for php
mkdir -p /var/log/php/
mkdir -p /var/lib/php/upload/
mkdir -p /var/lib/php/session/
chown -R www-data /var/log/php/
chown -R www-data /var/lib/php/

# modify php ini settings
phpini=/etc/php5/fpm/php.ini
sed -i 's/^disable_functions =/disable_functions = php_uname, getmyuid, getmypid, passthru, leak, listen, diskfreespace, tmpfile, link, ignore_user_abord, shell_exec, dl, set_time_limit, exec, system, highlight_file, source, show_source, fpaththru, virtual, posix_ctermid, posix_getcwd, posix_getegid, posix_geteuid, posix_getgid, posix_getgrgid, posix_getgrnam, posix_getgroups, posix_getlogin, posix_getpgid, posix_getpgrp, posix_getpid, posix, _getppid, posix_getpwnam, posix_getpwuid, posix_getrlimit, posix_getsid, posix_getuid, posix_isatty, posix_kill, posix_mkfifo, posix_setegid, posix_seteuid, posix_setgid, posix_setpgid, posix_setsid, posix_setuid, posix_times, posix_ttyname, posix_uname, proc_open, proc_close, proc_get_status, proc_nice, proc_terminate, phpinfo/' $phpini
sed -i 's/^display_errors = On/display_errors = Off/' $phpini
sed -i 's/^session.cookie_httponly =/session.cookie_httponly = 1/' $phpini
sed -i 's/^file_uploads = On/file_uploads = Off/' $phpini
sed -i 's/^upload_max_filesize =.*/upload_max_filesize = 2MB/' $phpini
sed -i 's/^post_max_size =.*/post_max_size = 20K/' $phpini
sed -i 's/^max_execution_time =.*/max_execution_time = 30/' $phpini
sed -i 's/^memory_limit = 128M/memory_limit = 8M/' $phpini
sed -i 's/^register_globals = On/register_globals = Off/' $phpini
sed -i 's/^allow_url_fopen = On/allow_url_fopen = Off/' $phpini
sed -i 's/^allow_url_include = On/allow_url_include = Off/' $phpini
sed -i 's/^expose_php = On/expose_php = Off/' $phpini
sed -i 's/^;date.timezone =/date.timezone = UTC/' $phpini
sed -i 's/^session.name = PHPSESSID/session.name = SESSID/' $phpini
sed -i 's/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' $phpini
sed -i 's@;error_log = syslog@error_log = /var/log/php/error.log@' $phpini
sed -i 's@;upload_tmp_dir =@upload_tmp_dir = /var/lib/php/upload@' $phpini
sed -i 's@;session.save_path =.*@session.save_path = /var/lib/php/session@' $phpini

# download and install composer globally
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

touch /tmp/restart-php5-fpm

###############################################################################
### install and configure monit
###############################################################################

aptitude -y install monit

cp -f /tmp/lnppstack/monit/monitrc /etc/monit/monitrc
sed -i "s/\$HOSTNAME/$HOSTNAME/g" /etc/monit/monitrc
sed -i "s/\$ADMINEMAIL/$ADMINEMAIL/g" /etc/monit/monitrc

if [ ! -d "/etc/monit/conf.d/" ]; then
  mkdir -p /etc/monit/conf.d/
fi

cp /tmp/lnppstack/monit/system /etc/monit/conf.d/system
sed -i "s/\$HOSTNAME/$HOSTNAME/g" /etc/monit/conf.d/system

cp /tmp/lnppstack/monit/sshd /etc/monit/conf.d/sshd
sed -i "s/\$SSHPORT/$SSHPORT/g" /etc/monit/conf.d/sshd

cp /tmp/lnppstack/monit/postfix /etc/monit/conf.d/postfix
cp /tmp/lnppstack/monit/postgresql /etc/monit/conf.d/postgresql

touch /tmp/restart-monit

###############################################################################
### install and configure firewall
###############################################################################

sudo aptitude -y install ufw

# set default rules: deny all incoming traffic, allow all outgoing traffic
ufw default deny incoming
ufw default allow outgoing
ufw logging on

# open port for ssh, http, and https
ufw allow $SSHPORT/tcp
ufw allow http/tcp
ufw allow https/tcp

# enable firewall
echo y|ufw enable

###############################################################################
### perform cleanup
###############################################################################

# disable atd scheduler service
stop atd
mv /etc/init/atd.conf /etc/init/atd.conf.noexec

# delete unneeded users from /etc/passwd
deluser irc
deluser games
deluser news
deluser uucp
deluser proxy
deluser list
deluser gnats

aptitude autoclean

# restarts services that have a restart-service_name file in /tmp
for service_name in $(ls /tmp/ | grep restart-* | cut -d- -f2-10); do
  service $service_name restart
  rm -f /tmp/restart-$service_name
done

mail -s "LNPP Stack install for $HOSTNAME" $ADMINEMAIL <<EOT
LNPP Stack installation complete. Your server will need to be rebooted. You can login via ssh using your RSA key. Root login and password authentication for ssh have been disabled.

Once you login, you can start creating and managing sites using the helper scripts available in /usr/local/bin.

For more info, please visit: https://github.com/gizmovation/lnppstack

Enjoy!
EOT

