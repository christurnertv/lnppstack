#!/bin/bash

function check_root() {
  if [ ! "`whoami`" = "root" ]
  then
    echo "Error: This script must be run as root."
    exit 1
  fi
}

check_root

if [ -z "$1" ];then
  echo "Usage: setup-vhost <username> <hostname> (no www)"
  exit 1
fi

# make sure the user's home directory exists, else exit
if [ ! -d "/home/$1" ]; then
  echo "Error: Home directory for user $1 was not found."
  exit 1
fi

echo "Setting up virtual host."

# create the sites dir if it doesn't exist
if [ ! -d "/home/$1/sites" ]; then
  mkdir "/home/$1/sites"
  chown -R $1:$1 "/home/$1/sites"
fi

# create the site directory and set owner
mkdir "/home/$1/sites/$2"
chown -R $1:$1 "/home/$1/sites/$2"

# create the repos dir if it doesn't exist
if [ ! -d "/home/$1/repos" ]; then
  mkdir "/home/$1/repos"
  chown -R $1:$1 "/home/$1/repos"
fi

# create a git repo for the site
mkdir "/home/$1/repos/$2.git"
cd "/home/$1/repos/$2.git"
git init --bare
chown -R $1:$1 "/home/$1/sites/$2"

# create the post-receive hook for automatic updates
cat > "/home/$1/repos/$2.git/hooks/post-receive" <<END
#!/bin/sh
GIT_WORK_TREE=/home/$1/sites/$2/
export GIT_WORK_TREE
git checkout -f
cd /home/$1/sites/$2/
END
chmod +x "/home/$1/repos/$2.git/hooks/post-receive"

# create the nginx site configuration
cat > "/etc/nginx/sites-available/$2.conf" <<END
# redirect www to non-www
server {
  server_name www.$2;
  return 301 $scheme://$2$request_uri;
}

server {
  server_name $2;
  root /home/$1/sites/$2/public;

  access_log  /var/log/nginx/$2-access.log;
  error_log  /var/log/nginx/$2-error.log;

  include /etc/nginx/includes/location.conf;

  location / {
    try_files \$uri \$uri/ /index.php?\$args;
    #try_files \$uri \$uri/ /index.php?q=$uri&\$args; #wordpress
  }

  # pass all .php files to php-fpm
  location ~ \.php$ {
    try_files \$uri =404;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_param  PHP_VALUE  "open_basedir=\$document_root:/var/log/php/:/var/lib/php/:/home/$1/sites/$2/app/storage/";
    include fastcgi_params;
    fastcgi_index index.php;
    fastcgi_pass unix:/var/run/php5-fpm-$2.sock;
  }

}
END

# create the slowlog dir if it doesn't exist
if [ ! -d "/var/log/php-fpm" ]; then
  mkdir "/var/log/php-fpm"
fi

# create the php-fpm pool configuration
cat > "/etc/php5/fpm/pool.d/$2.conf" <<END
[$2]

user = $1
group = $1

request_slowlog_timeout = 5s
slowlog = /var/log/php-fpm/slowlog-$2.log

listen = /var/run/php5-fpm-$2.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0666
listen.backlog = -1

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500

request_terminate_timeout = 120s
rlimit_files = 131072
rlimit_core = unlimited
catch_workers_output = yes

env[HOSTNAME] = \$HOSTNAME
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
END

# enable the new site
ln -s /etc/nginx/sites-available/$2.conf /etc/nginx/sites-enabled/$2.conf

# restart services
service nginx reload
service php5-fpm restart

echo "Virtual host setup complete."
exit
