#!/usr/bin/bash

source functions.sh

if [ "$1" = "system" -o "$1" = "all" -o "$1" = "postfix" -o "$1" = "iptables" -o "$1" = "mysql" -o "$1" = "percona" -o "$1" = "nginx" -o "$1" = "nginx-upstream" -o "$1" = "php" -o "$1" = "cgi" -o "$1" = "domain" -o "$1" = "wordpress" -o "$1" = "friendica" -o "$1" = "red" -o "$1" = "custom" -o "$1" = "upgrade" ]; then
	echo option found
else
    echo 'Usage:' `basename $0` '[option]'
    echo 'Available options:'
    for option in system 'all' postfix iptables mysql 'percona - install mysql first' nginx 'nginx-upstream - not required unless upgrading nginx installed with an older version of this script' php cgi 'domain example.com' 'wordpress example.com' 'friendica example.com' 'red example.com' 'custom - my personal preferences' upgrade
    do
        echo '  -' $option
    done
    exit 1
fi
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
if [ ! -f ./setup-debian.conf ]; then
    cat > ./setup-debian.conf <<END
SSH_PORT=1234 # Change 1234 to the port of your choice
INTERFACE=all # Options are all for a dual stack ipv4/ipv6 server
#                           ipv4 for an ipv4 server
#                           ipv6 for an ipv6 server
#               Defaults to ipv4 only if incorrect
USER=changeme
EMAIL=\$USER@[127.0.0.1] # mail user or an external email address
OPENVZ=yes # Values are yes, no or gnome
DISTRIBUTION=wheezy # Does not do anything yet, left in for jessie
SERVER=nginx # Deprecated, now unused
CPUCORES=detect # Options are detect or n where n = number of cpu cores to be used
MEMORY=128 # values are low, 64, 96, 128, 192, 256, 384, 512, 1024, 2048 - use 2048 if more memory is available
FRIENDICASSL=none # values are none, sslonly & both both is http & https. sslonly & both require a pre-installed signed ssl cert
REDSSL=none # values are none, sslonly & both both is http & https. sslonly & both require a pre-installed signed ssl cert
# SELF SIGNED SSL CERTS ARE NOT SUPPORTED
# to pre-install a signed ssl certificate, copy the crt & key files to /etc/nginx/ssl_keys/
END
fi

if [ -z "`grep 'USER=' ./setup-debian.conf`" ]; then
	sed -i "s/EMAIL=/USER=changeme\\nEMAIL=/" ./setup-debian.conf
fi
if [ -z "`grep 'CPUCORES=' ./setup-debian.conf`" ]; then
    echo CPUCORES=detect \# Options are detect or n where n = number of cpu cores to be used >> ./setup-debian.conf
fi
if [ -z "`grep 'MEMORY=' ./setup-debian.conf`" ]; then
	echo MEMORY=128 \# values are low, 64, 96, 128, 192, 256, 384, 512, 1024, 2048 - use 2048 if more memory is available >> ./setup-debian.conf
fi
if [ -z "`grep 'DISTRIBUTION=' ./setup-debian.conf`" ]; then
    echo DISTRIBUTION=wheezy \# Value is wheezy >> ./setup-debian.conf
fi
if [ -z "`grep 'SERVER=' ./setup-debian.conf`" ]; then
    echo SERVER=nginx \# Deprecated, now unused >> ./setup-debian.conf
fi
if [ -z "`grep 'FRIENDICASSL=' ./setup-debian.conf`" ]; then
    echo FRIENDICASSL=none \# values are none, sslonly \& both both is http \& https. sslonly \& both require a pre-installed signed ssl cert >> ./setup-debian.conf
fi
if [ -z "`grep 'REDSSL=' ./setup-debian.conf`" ]; then
    echo REDSSL=none \# values are none, sslonly \& both both is http \& https. sslonly \& both require a pre-installed signed ssl cert >> ./setup-debian.conf
fi
if [ -z "`grep 'SELF SIGNED' ./setup-debian.conf`" ]; then
    echo \# SELF SIGNED SSL CERTS ARE NOT SUPPORTED >> ./setup-debian.conf
fi
if [ -z "`which "$1" 2>/dev/null`" -a ! "$1" = "domain" -a ! "$1" = "nginx" -a ! "$1" = "nginx-upstream" -a ! "$1" = "percona" ]; then
    apt-get -q -y update
    check_install nano "nano"
fi
if [ ! "$1" = "domain" ]; then
	nano ./setup-debian.conf
fi
[ -r ./setup-debian.conf ] && . ./setup-debian.conf

if [ "$CPUCORES" = "detect" ]; then
	CPUCORES=`grep -c processor //proc/cpuinfo`
fi

if [ "$INTERFACE" = "all" -o "$INTERFACE" = "ipv6" ]; then
    FLAGS=ipv6
else
    FLAGS=ipv4
fi

if [ "$USER" = "changeme" ]; then
	die "User changeme is not allowed"
fi
case "$1" in
all)
    remove_unneeded
    update_upgrade
    install_postfix
    install_percona
    install_nginx
    install_php
#    install_cgi
#    install_iptables $SSH_PORT
    ;;
postfix)
    add_user
    install_postfix
    ;;
iptables)
    install_iptables $SSH_PORT
    ;;
percona)
    install_percona
    ;;
nginx)
    install_nginx
    ;;
nginx-upstream)
    if [ -z "`which "nginx" 2>/dev/null`" ]; then
        print_warn "Nginx has to be installed as this is an upgrade only."
    else
        install_nginx-upstream
    fi
    ;;
php)
    install_php
    ;;
cgi)
    install_cgi
    ;;
domain)
    install_domain $1 $2 $3
    ;;
system)
    remove_unneeded
    update_upgrade
    ;;
custom)
    custom $2
    ;;
wordpress)
    install_wordpress $2
    ;;
friendica)
    install_friendica $1 $2 $3
    ;;
red)
    install_red $1 $2 $3
    ;;
upgrade)
    check_upgrade php5-fpm "php5-mysqlnd"
    if [ -e /etc/postfix/main.cf ]; then
		postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
        postconf -e "smtpd_tls_exclude_ciphers = aNULL, MD5 , DES, ADH, RC4, PSD, SRP, 3DES, eNULL"
		service postfix restart
    fi
    if [ -e /etc/php5/conf.d/lowendscript.ini ]; then
		rm -f /etc/php5/conf.d/lowendscript.ini
    fi
    if [ -e /etc/php5/mods-available/apc.ini ]; then
		apt-get install php5-xcache
    fi
    sed -i "s/ssl_session_cache shared:SSL:10m/ssl_session_cache shared:SSL:50m/" /etc/nginx/nginx.conf
    sed -i "s/ssl_protocols SSLv3 TLSv1 TLSv1.1 TLSv1.2/ssl_protocols TLSv1 TLSv1.1 TLSv1.2/" /etc/nginx/nginx.conf
    if [ -z "`grep '! -d /run/sshd' /etc/crontab`" ];then
            echo "@reboot root if [ ! -d /run/sshd ]; then mkdir /run/sshd;fi" >> /etc/crontab
    fi
    ;;
*)
    echo 'Option not found'
    ;;
esac
