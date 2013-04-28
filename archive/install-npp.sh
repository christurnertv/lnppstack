#!/bin/bash

function check_root() {
  if [ ! "`whoami`" = "root" ]
  then
    echo "Error: This script must be run as root."
    exit 1
  fi
}

check_root

# install postgres
aptitude -y install postgresql

# install nginx and php
aptitude -y install nginx php5 php5-cli php5-pgsql php5-curl php5-mcrypt php5-gd php5-imagick php5-fpm

# stop the services
service nginx stop
service php5-fpm stop

# start nginx configuation

# disable and remove default site
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

# remove the default php-fpm pool
rm -f /etc/php5/fpm/pool.d/www.conf

# create a location for site specific log files
if [ ! -d "/var/log/nginx" ]; then
  mkdir /var/log/nginx
fi

# create a location for nginx configuration includes
mkdir /etc/nginx/includes

# create a location for php-fpm pool slowlogs
mkdir /var/log/php-fpm

# create an include for basic locations
cat > /etc/nginx/includes/location.conf <<END
# Global locations configuration file.
# Designed to be included in any server {} block.

location = /favicon.ico {
  access_log off;
  log_not_found off;
}

location = /robots.txt {
  allow all;
  access_log off;
  log_not_found off;
}

# deny access to hidden files (files starting with .)
location ~ /\. {
  deny all;
  access_log off;
  log_not_found off;
}

# set cache headers for image files and serve directly
location ~* \.(jpg|jpeg|gif|png|ico)$ { 
    log_not_found off;
    expires 1y;
}

# set cache headers for static files and serve directly
location ~* \.(css|js|xml|txt|htm|html)$ {
  expires 1d;
}
END

# create the nginx configuration file
cat > /etc/nginx/nginx.conf <<END
worker_processes 4;
pid /var/run/nginx.pid;

events {
  worker_connections 768;
}

http {

  ##
  # Basic Settings
  ##

  charset                 utf-8;
  ignore_invalid_headers  on;
  max_ranges              0;  # default unlimited (restricts resuming)
  keepalive_timeout       65;
  recursive_error_pages   on;
  sendfile                on;
  server_tokens           off;
  source_charset          utf-8;
  tcp_nopush              on;
  tcp_nodelay             on;
  types_hash_max_size     2048;

  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  index index.php index.html index.htm;

  ##
  # Logging Settings
  ##

  access_log /var/log/nginx/access.log;
  error_log  /var/log/nginx/error.log;

  ##
  # Gzip Settings
  ##

  gzip on;
  gzip_disable "msie6";
  gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

  ##
  # Virtual Host Configs
  ##

  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;

}
END

# end nginx configuation

# start php configuation

mkdir -p /var/log/php/
mkdir -p /var/lib/php/upload/
mkdir -p /var/lib/php/session/
chown -R www-data /var/log/php/
chown -R www-data /var/lib/php/

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

# end php configuation



# start services
service php5-fpm start
service nginx start
service postgresql start

# start monit configuration

cat > /etc/monit/conf.d/php5-fpm <<END
check process php5-fpm with pidfile /var/run/php5-fpm.pid
  group www-data
  start program = "/etc/init.d/php5-fpm start"
  stop program  = "/etc/init.d/php5-fpm stop"
  # add unixsocket monitoring below for each php-fpm pool
  ### INSERTHERE ### DO NOT REMOVE THIS LINE ###
  if 5 restarts within 5 cycles then timeout
END

cat > /etc/monit/conf.d/nginx <<END
check process nginx with pidfile /var/run/nginx.pid
  group www-data
  start program = "/etc/init.d/nginx start"
  stop  program = "/etc/init.d/nginx stop"
  if cpu usage > 95% for 3 cycles then restart
  if failed port 80 protocol HTTP request / within 5 cycles then restart
  if 5 restarts within 5 cycles then timeout
END

cat > /etc/monit/conf.d/postgres <<END
check process postgresql with pidfile /var/run/postgresql/9.1-main.pid
  group postgres
  start program = "/etc/init.d/postgresql start"
  stop  program = "/etc/init.d/postgresql stop"
  if failed host localhost port 5432 type TCP then restart
  if 5 restarts within 5 cycles then timeout
END

service monit restart

# end monit configuration

echo Installation done.
exit
