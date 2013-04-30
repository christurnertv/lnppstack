# LNPP Stack Scripts

Scripts to simplify installing, configuring, and maintaining nginx, php-fpm, and postgres on ubuntu.
Tested on ubuntu 12.10.

## Linode

You can use these scripts to setup your linode VPS. If you find these scripts useful, please use our referral link below.

[http://www.linode.com/](http://www.linode.com/?r=bed2c06e157de72a8f97d0c7035069800c9b342b)

## Install Scripts

To download and use initial install scripts, use the following commands (as root):

```bash
wget https://raw.github.com/gizmovation/lnppscripts/master/install-stack.sh
chmod u+x install-stack.sh
./install-stack.sh
```

## Helper Scripts

Helper scripts get installed to /usr/local/bin.

```bash
# create a site
site-create example.com

# install phpsecinfo in current directory
site-install-phpsecinfo

# delete a site
site-delete example.com

# disable a site
site-disable example.com

# enable a disabled site
site-enable example.com

# update helper scripts
sudo lnpp-helpers update
```

## Warranty

None, use at your own risk!

## License

[MIT](http://opensource.org/licenses/MIT) 
