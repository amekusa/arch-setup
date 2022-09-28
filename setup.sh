#!/bin/bash

EXEC="$(realpath "$0")"
BASE="$(dirname "$EXEC")"

. "$BASE/lib/util"
. "$BASE/lib/task"

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


# ---- tasks -------- *

# locale
if [ -n "$LOCALE" ] && task LOCALE; then
	# uncomment desired locale in /etc/locale.gen
	_uncomment "$LOCALE" /etc/locale.gen || x
	# generate locale
	locale-gen || x
	# locale config
	_save-var LANG "$LOCALE" /etc/locale.conf || x
ksat; fi

# timezone
if [ -n "$TIMEZONE" ] && task TIMEZONE; then
	ln -s "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || x
	hwclock --systohc --utc || x
ksat; fi

# keymap
if [ -n "$KEYMAP" ] && task KEYMAP; then
	_save-var KEYMAP "$KEYMAP" /etc/vconsole.conf || x
ksat; fi

# hosts
if task HOSTS; then
	cat <<- EOF > /etc/hosts
	127.0.0.1  localhost
	::1        localhost
	EOF
ksat; fi

# hostname
if [ -n "$HOSTNAME" ] && task HOSTNAME; then
	echo "$HOSTNAME" > /etc/hostname || x
	echo "127.0.1.1  $HOSTNAME" >> /etc/hosts || x
ksat; fi

# network
if [ -n "$NETWORK_MAN" ] && task NETWORK; then
	case "$NETWORK_MAN" in
	systemd)
		;;
	netctl)
		;;
	*)
		x "invalid NETWORK value"
		;;
	esac
ksat; fi
