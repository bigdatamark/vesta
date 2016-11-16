#!/bin/bash

CHOST='c.vestacp.com'
VERSION='debian'
VESTA='/usr/local/vesta'
os='debian'
release=$(cat /etc/debian_version|grep -o [0-9]|head -n1)
codename="$(cat /etc/os-release |grep VERSION= |cut -f 2 -d \(|cut -f 1 -d \))"
vestacp="http://$CHOST/$VERSION/$release"
servername=$(hostname -f)

apt-get update > /dev/null 2>&1

if [ -f "/etc/roundcube/plugins/password/config.inc.php" ]; then

    # Roundcube Vesta password driver - changing password_vesta_host (in config) to server hostname 
    sed -i "s/localhost/$servername/g" /etc/roundcube/plugins/password/config.inc.php

    # Roundcube log permission fix
    if [ ! -d "/var/log/roundcube" ]; then
        mkdir /var/log/roundcube
    fi
    chown admin:admin /var/log/roundcube

fi


# Added default install "expect" to work for backup sftp
apt-get -y install expect > /dev/null 2>&1


# apparmor rules for bind9 
if [ -f "/etc/bind/named.conf" ]; then
    file="/etc/apparmor.d/local/usr.sbin.named"
    if [ ! -f "$file" ] || [ $( grep -ic "/home/" $file ) -eq 0 ]; then
        aa-complain /usr/sbin/named 2>/dev/null
        echo "/home/** rwm," >> /etc/apparmor.d/local/usr.sbin.named 2>/dev/null
        service apparmor restart >/dev/null 2>&1
    fi
fi


# Debian fix for spamassassin when it's not in startup list 
if [[ $(systemctl list-unit-files | grep spamassassin) =~ "disabled" ]]; then
    systemctl enable spamassassin
fi


# RoundCube tinyMCE fix
tinymceFixArchiveURL=$vestacp/roundcube/roundcube-tinymce.tar.gz
tinymceParentFolder=/usr/share/roundcube/program/js
tinymceFolder=$tinymceParentFolder/tinymce
tinymceBadJS=$tinymceFolder/tiny_mce.js
tinymceFixArchive=$tinymceParentFolder/roundcube-tinymce.tar.gz
if [[ -L "$tinymceFolder" && -d "$tinymceFolder" ]]; then
    if [ -f "$tinymceBadJS" ]; then
        wget $tinymceFixArchiveURL -O $tinymceFixArchive
        if [[ -f "$tinymceFixArchive" && -s "$tinymceFixArchive" ]]; then
            rm $tinymceFolder
            tar -xzf $tinymceFixArchive -C $tinymceParentFolder
            rm $tinymceFixArchive
            chown -R root:root $tinymceFolder
        else
            echo "File roundcube-tinymce.tar.gz is not downloaded, RoundCube tinyMCE fix is not applied"
            rm $tinymceFixArchive
        fi
    fi
fi


# Fixing empty NAT ip
ip=$(ip addr|grep 'inet '|grep global|head -n1|awk '{print $2}'|cut -f1 -d/)
pub_ip=$(curl -s vestacp.com/what-is-my-ip/)
file="$VESTA/data/ips/$ip"
if [ -f "$file" ] && [ $( grep -ic "NAT=''" $file ) -eq 1 ]; then
    if [ ! -z "$pub_ip" ] && [ "$pub_ip" != "$ip" ]; then
        v-change-sys-ip-nat $ip $pub_ip
    fi
fi


file="/etc/exim4/exim4.conf.template"
if [ -f "$file" ]; then
    apt-get -y install libmail-dkim-perl > /dev/null 2>&1
fi


if [ ! -f "/etc/apache2/mods-enabled/remoteip.load" ]; then
    $VESTA/upd/switch_rpath.sh 
fi