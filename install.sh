#!/bin/bash
#
# VARIABLES
#
IREDMAIL_VERSION=0.9.7

if [ $UID != 0 ]
then
	echo "[ERROR] Should be root user!"
	return 1 
fi

if [ ! -f 'config' ]
then
	echo "[ERROR]: config file should exists!"
	exit 2
fi

# 1) System upgrade
apt-get update
apt-get --yes dist-upgrade

# 2) iRedMail install
apt-get install bzip2

tar xjf src/iRedMail-$IREDMAIL_VERSION.tar.bz2 -C tmp/
cp config tmp/iRedMail-$IREDMAIL_VERSION/
cd tmp/iRedMail-$IREDMAIL_VERSION

export AUTO_USE_EXISTING_CONFIG_FILE=y
export AUTO_INSTALL_WITHOUT_CONFIRM=y
export AUTO_CLEANUP_REMOVE_SENDMAIL=y
export AUTO_CLEANUP_REMOVE_MOD_PYTHON=y
export AUTO_CLEANUP_REPLACE_FIREWALL_RULES=y
export AUTO_CLEANUP_RESTART_IPTABLES=y
export AUTO_CLEANUP_REPLACE_MYSQL_CONFIG=y
export AUTO_CLEANUP_RESTART_POSTFIX=n
bash ./iRedMail.sh

# 3) Customize maildir path
MAILDIR_HASHED=`grep MAILDIR_HASHED config | cut -d= -f2`
MAILDIR_PREPEND_DOMAIN=`grep MAILDIR_PREPEND_DOMAIN config | cut -d= -f2`
MAILDIR_APPEND_TIMESTAMP=`grep MAILDIR_APPEND_TIMESTAMP config | cut -d= -f2`

echo "" >> /opt/www/iredadmin/settings.py
echo "MAILDIR_HASHED = $MAILDIR_HASHED" >> /opt/www/iredadmin/settings.py 
echo "MAILDIR_PREPEND_DOMAIN = $MAILDIR_PREPEND_DOMAIN" >> /opt/www/iredadmin/settings.py
echo "MAILDIR_APPEND_TIMESTAMP = $MAILDIR_APPEND_TIMESTAMP" >> /opt/www/iredadmin/settings.py

# 4) LetsEnccrypyt
apt-get update
apt-get install --yes software-properties-common
add-apt-repository --yes ppa:certbot/certbot
apt-get update
apt-get install --yes python-certbot-nginx

MASTER_DOMAIN=`echo "SELECT domain FROM domain;" | mysql --defaults-file=/root/.my.cnf-vmail --database=vmail -s`
LETSENCRYPT_SUBDOMAINS=`grep LETSENCRYPT_SUBDOMAINS config | cut -d= -f2`
LETSENCRYPT_EMAIL=`grep LETSENCRYPT_EMAIL config | cut -d= -f2`
MAIN_DOMAIN=`hostname -f`
CERTBOT="certbot --agree-tos --eff-email -m $LETSENCRYPT_EMAIL certonly --webroot -w /var/www/html/ -d $MAIN_DOMAIN"

for sub in $LETSENCRYPT_SUBDOMAINS
do
    CERTBOT="$CERTBOT -d $sub.$MASTER_DOMAIN"
done
echo $CERTBOT
tmp=`$CERTBOT`

if [ $? != 0 ]
then
    echo "[ERROR]: certbot fails\n"
    exit 3
fi

mv /etc/ssl/certs/iRedMail.crt /etc/ssl/certs/iRedMail.crt.old
ln -s /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem /etc/ssl/certs/iRedMail.crt
mv /etc/ssl/private/iRedMail.key /etc/ssl/private/iRedMail.key.old
ln -s /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem /etc/ssl/private/iRedMail.key

# 5) automatic updates
apt-get install --yes unattended-upgrades
perl -pi -e 's|\/\/\s+"\$\{distro_id}:\$\{distro_codename}-updates";|    "\$\{distro_id}:\$\{distro_codename}-updates";|' /etc/apt/apt.conf.d/50unattended-upgrades
echo 'APT::Periodic::AutocleanInterval "7";' >> /etc/apt/apt.conf.d/20auto-upgrades