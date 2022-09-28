#!/bin/bash

EXEC="$(realpath "$0")"
BASE="$(dirname "$EXEC")"
ASSETS="$BASE/assets"

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


# ---- utils -------- *

_install() {
	pacman --noconfirm --needed -S "$1" &> /dev/null
}

_require() {
	local r
	r="$(which "$1")" && echo "$r" && return
	_install "$1" || return 1
	echo "$(which "$1")"
}


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

# user
if [ -n "$USER" ] && task USER; then
	shell="$(_require $USER_SHELL)" || x "cannot install $USER_SHELL"
	useradd -m -G wheel -s "$shell" "$USER" || x "cannot add user: $USER"
ksat; fi

# network
if [ -n "$NET_MANAGER" ] && task NETWORK; then
	case "$NET_MANAGER" in
	systemd)
		file="$(_if $NET_WIRED ? wired : wireless).network"
		cat "$ASSETS/$file" | _subst "" > "/etc/systemd/network/$file" || x
		systemctl enable systemd-networkd.service || x
		;;
	netctl)
		# TODO
		;;
	*)
		x "invalid NETWORK value"
		;;
	esac
ksat; fi

# ssh
if task SSH; then
	_install openssh || x "cannot install openssh"
	systemctl enable sshd.service || x "cannot enable sshd.service"
ksat; fi

echo
