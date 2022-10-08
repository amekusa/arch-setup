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

# finds the disk device path (e.g. /dev/sda, /dev/vda)
_disk() {
	lsblk -no PATH,TYPE | awk -v e=1 '$2 == "disk" { print $1; e=0; exit } END { exit e }'
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
	echo
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

# always update keyring first
_install archlinux-keyring

# hosts
if task HOSTS; then
	cat <<- EOF > /etc/hosts
	127.0.0.1  localhost
	::1        localhost
	EOF
ksat; fi

# hostname
if [ -n "$HOSTNAME" ] && task HOSTNAME -d HOSTS; then
	_show-var HOSTNAME
	echo "$HOSTNAME" > /etc/hostname || x
	echo "127.0.1.1  $HOSTNAME" >> /etc/hosts || x
	_show-file /etc/hosts
ksat; fi

# locale
if [ -n "$LOCALE" ] && task LOCALE; then
	_show-var LOCALE
	_uncomment "$LOCALE" /etc/locale.gen || x
	locale-gen || x
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

# bootloader
if [ -n "$BOOTLOADER" ] && task BOOTLOADER; then
	disk="$(_fb "$DISK" $(_disk))" || x "disk not found"
	case "$BOOTLOADER" in
	grub)
		_install grub || x "cannot install grub"
		grub-install --recheck "$disk" || x "grub-install failed"
		grub-mkconfig -o /boot/grub/grub.cfg || x "grub-mkconfig failed"
		;;
	*)
		x "invalid BOOTLOADER value"
	esac
ksat; fi

# root user
if task ROOT; then
	until passwd; do
		echo
		echo "input password for root user"
	done
ksat; fi

# admin user
if [ -n "$ADMIN" ] && task ADMIN; then
	_show-var ADMIN
	shell="$(_require $ADMIN_SHELL)" || x "cannot install: $ADMIN_SHELL"
	useradd -m -G wheel -s "$shell" "$ADMIN" || x "cannot add user: $ADMIN"
	until passwd "$ADMIN"; do
		echo
		echo "input password for user: $ADMIN"
	done
ksat; fi

# sudo
if $SUDO && task SUDO; then
	_install sudo || x "cannot install: sudo"
	file="/etc/sudoers"
	case "$SUDO_ALLOW" in
		wheel) _uncomment '%wheel ALL=\(ALL:ALL\) ALL' "$file" || x "failed to write: $file" ;;
		sudo)  _uncomment '%sudo ALL=\(ALL:ALL\) ALL' "$file" || x "failed to write: $file" ;;
		*) x "invalid SUDO_ALLOW value"
	esac
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
		cat "$ASSETS/$file" | _subst "name=$nif" "chcp=$(_yn $NET_DHCP)" "vm=$(_yn $VM)" > "/etc/systemd/network/$file" || x
		_show-file "/etc/systemd/network/$file"
		systemctl enable systemd-networkd.service || x
		systemctl enable systemd-resolved.service || x
		;;
	netctl)
		# TODO
		;;
	*)
		x "invalid NETWORK value"
	esac
ksat; fi

# ssh
if task SSH -d ADMIN; then
	_install openssh || x "cannot install openssh"
	file="/etc/ssh/sshd_config"
	[ -f "$file" ] && _backup "$file" || x "failed to backup: $file"
	cat "$ASSETS/sshd_config" | _subst "admin=$ADMIN" >> "$file" || x "failed to write: $file"
	_show-file "$file"
	systemctl enable sshd.service || x
ksat; fi

# rootkit hunter
if $RKHUNTER && task RKHUNTER; then
	exec="$(_require rkhunter)" || x
	cp "$ASSETS/rkhunter.conf.local" /etc/ || x

	file="/etc/systemd/system/rkhunter.service"
	cat "$ASSETS/rkhunter.service" | _subst "rkhunter=$exec" > "$file" || x "failed to write: $file"
	_show-file "$file"

	if [ -n "$RKH_TIMER" ]; then
		file="/etc/systemd/system/rkhunter.timer"
		cat "$ASSETS/rkhunter.timer" | _subst "timer=$RKH_TIMER" > "$file" || x "failed to write: $file"
		_show-file "$file"
		systemctl enable rkhunter.timer || x
	fi
ksat; fi

# reflector
if $REFLECTOR && task REFLECTOR; then
	_install reflector || x "cannot install: reflector"
	file="/etc/xdg/reflector/reflector.conf"
	[ -f "$file" ] || x "file not found: $file"
	if [ -n "$REF_COUNTRY" ]; then
		sed -ri "/^--country /d" "$file"
		sed -ri "/^# --country /a --country '$REF_COUNTRY'" "$file"
	fi
	if [ -n "$REF_LATEST" ]; then
		sed -ri "s/^--latest .*/--latest $REF_LATEST/" "$file"
	fi
	if [ -n "$REF_SORT" ]; then
		sed -ri "s/^--sort .*/--sort $REF_SORT/" "$file"
	fi
	_show-file "$file"
	systemctl enable reflector.timer || x
ksat; fi

# paccache
if $PACCACHE && task PACCACHE; then
	_install pacman-contrib || x "cannot install: pacman-contrib"
	systemctl enable paccache.timer || x
ksat; fi

# install optional packages
if [ -n "$PKGS" ] && task PKGS; then
	for each in "${PKGS[@]}"; do
		_install "$each" || x "cannot install: $each"
	done
ksat; fi

# git
if [ -n "$GIT_EMAIL" ] && [ -n "$GIT_NAME" ] && task GIT -d ADMIN; then
	_install git || x "cannot install: git"
	_show-var GIT_EMAIL
	_show-var GIT_NAME
	file="$HOME/.gitconfig"
	copy="/home/$ADMIN/.gitconfig"
	cat "$ASSETS/user.gitconfig" | _subst "email=$GIT_EMAIL" "name=$GIT_NAME" > "$file" || x "failed to write: $file"
	_show-file "$file"
	cp "$file" "$copy" || x "failed to copy: $file -> $copy"
	chown $ADMIN:$ADMIN "$copy" || x "cmd failed: chown"
ksat; fi

# aur helper
if [ -n "$AUR_HELPER" ] && task AUR_HELPER -d ADMIN SUDO GIT; then
	_show-var AUR_HELPER
	case "$AUR_HELPER" in
	yay)
		sudo -Hu "$ADMIN" bash <<-CMD
		git clone "https://aur.archlinux.org/yay.git" "$HOME/yay" &&
		cd "$HOME/yay" && makepkg -sic --noconfirm --needed &&
		rm -rf "$HOME/yay"
		CMD || x "cannot install: yay"
		;;
	*)
		x "invalid AUR_HELPER value: $AUR_HELPER"
	esac
	cd "$BASE"
ksat; fi

# etckeeper
if $ETCKEEPER && task ETCKEEPER -d GIT; then
	_install etckeeper || x "cannot install: etckeeper"
	file="/etc/.gitignore"
	cp "$ASSETS/etc.gitignore" "$file" || x "failed to write: $file"
	etckeeper init || x "cmd failed: etckeeper init"
ksat; fi

# pacman hooks for rkhunter
if $RKHUNTER && $RKH_HOOKS && task RKH_HOOKS -d RKHUNTER; then
	dir="/etc/pacman.d/hooks"
	[ -d "$dir" ] || mkdir "$dir" || x "cannot create dir: $dir"

	file="$dir/rkhunter-propupd.hook"
	cat "$ASSETS/rkhunter-propupd.hook" | _subst "rkhunter=$(which rkhunter)" > "$file" || x "failed to write: $file"
	_show-file "$file"

	file="$dir/rkhunter-status.hook"
	cp "$ASSETS/rkhunter-status.hook" "$file" || x "failed to write: $file"
	_show-file "$file"
ksat; fi

# etckeeper commit
if $ETCKEEPER && task-done ETCKEEPER; then
	etckeeper unclean && etckeeper commit "[arch-setup] commit @ $(date +%F)"
fi

# rkhunter propupd
if $RKHUNTER && task RKH_PROPUPD -d RKHUNTER; then
	rkhunter --config-check || x "rkhunter: config error"
	rkhunter --propupd --report-warnings-only || x "rkhunter: propupd error"
ksat; fi

echo
echo "all done."
echo
echo "if you are in arch-chroot, type:"
echo "exit; umount -R /mnt"
echo
