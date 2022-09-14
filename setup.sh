#!/bin/bash

EXEC="$(realpath "$0")"
BASE="$(dirname "$EXEC")"

# config
CONF="$BASE/conf/setup"
. "$CONF.conf"
if [ -f "$CONF.local" ]; then
	. "$CONF.local"
else
	cp "$CONF.conf" "$CONF.local"
	echo "Generated: $CONF.local"
	exit
fi

# uncomment 'en_US.UTF-8 UTF-8' in /etc/locale.gen
sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /etc/locale.gen

# generate locale
locale-gen

echo "LANG=en_US.UTF-8" >> /etc/locale.conf
[ -z "$KEYMAP" ] || echo "KEYMAP=$KEYMAP" >> /etc/vconsole.conf

# timezone
[ -z "$TIMEZONE" ] || ln -s "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime && hwclock --systohc --utc

# hostname
[ -z "$HOSTNAME" ] || echo "$HOSTNAME" > /etc/hostname

# network manager
case "$NETWORK_MNG" in
systemd)
	
	;;
netctl)
	;;
esac
