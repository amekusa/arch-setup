#!/bin/bash
#
#  Arch Setup
# --------------- -  *
#  author: Satoshi Soma (https://amekusa.com)
# ============================================

EXEC="$(realpath "$0")"
BASE="$(dirname "$EXEC")"
ASSETS="$BASE/assets"
BACKUP="$BASE/backup"

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

# installs the given pkg
_install() {
	pacman --noconfirm --needed -S "$1" &> /dev/null
}

# returns full path to the given pkg.
# if it does not exist, installs it
_require() {
	local r
	r="$(which "$1")" && echo "$r" && return
	_install "$1" || return 1
	echo "$(which "$1")"
}

# finds a network interface
_nif() {
	local find="$1"
	ip -brief link | awk -v e=1 -v find="$find" '$1 ~ find { print $1; e=0; exit } END { exit e }'
}

# convert the given condition into yes/no
_yn() {
	if "$1"
		then echo "yes"
		else echo "no"
	fi
}

_show-var() {
	local var="$1"
	echo "$var: ${!var}"
}

_show-file() {
	echo "---- file: $1 --------"
	cat "$1"
	echo "==== END file: $1 ===="
}

_symlink() {
	local src="$1"
	local dst="$2"
	echo "symlink:"
	echo " > src: $src"
	echo " > dst: $dst"
	[ -h "$dst" ] && rm "$dst" && echo "removed the old symlink"
	ln -s "$src" "$dst"
}

_backup() {
	local now="$(date +%F)"
	local src="$1"
	local dst="$BACKUP/$(basename "$1").$(date +%F).backup"
	echo "backup:"
	echo " > src: $src"
	echo " > dst: $dst"
	echo "# backup at:$now src:$src" > "$dst"
	cat "$src" >> "$dst"
}

# ---- tasks -------- *

# locale
if [ -n "$LOCALE" ] && task LOCALE; then
	_show-var LOCALE
	# uncomment desired locale in /etc/locale.gen
	_uncomment "$LOCALE" /etc/locale.gen || x
	# generate locale
	locale-gen || x
	# locale config
	_save-var LANG "$LOCALE" /etc/locale.conf || x
ksat; fi

# timezone
if [ -n "$TIMEZONE" ] && task TIMEZONE; then
	_show-var TIMEZONE
	_symlink "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || x
	hwclock --systohc --utc || x
ksat; fi

# keymap
if [ -n "$KEYMAP" ] && task KEYMAP; then
	_show-var KEYMAP
	loadkeys "$KEYMAP" || x
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
	depend HOSTS
	_show-var HOSTNAME
	echo "$HOSTNAME" > /etc/hostname || x
	echo "127.0.1.1  $HOSTNAME" >> /etc/hosts || x
	_show-file /etc/hosts
ksat; fi

# user
if [ -n "$USER" ] && task USER; then
	_show-var USER
	shell="$(_require $USER_SHELL)" || x "cannot install $USER_SHELL"
	useradd -m -G wheel -s "$shell" "$USER" || x "cannot add user: $USER"
	_show-file /etc/passwd
ksat; fi

# network
if [ -n "$NET_MANAGER" ] && task NETWORK; then
	_show-var NET_MANAGER
	case "$NET_MANAGER" in
	systemd)
		if $NET_WIRED; then
			file="wired.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "en|eth"))" || x "network interface not found"
		else
			file="wireless.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "wl"))" || x "network interface not found"
		fi
		cat "$ASSETS/$file" | _subst "NAME=$nif" "DHCP=$(_yn $NET_DHCP)" "VM=$(_yn $VM)" > "/etc/systemd/network/$file" || x
		_show-file "/etc/systemd/network/$file"
		systemctl enable systemd-networkd.service || x
		;;
	netctl)
		# TODO
		;;
	*)
		x "invalid NETWORK value"
	esac
ksat; fi

# ssh
if task SSH; then
	_install openssh || x "cannot install openssh"
	systemctl enable sshd.service || x "cannot enable sshd.service"
ksat; fi

echo
