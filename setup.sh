#!/bin/bash
#
#  Arch Setup
# --------------- -  *
#  author: Satoshi Soma (https://amekusa.com)
# ============================================

EXEC="$(realpath "$0")"
BASE="$(dirname "$EXEC")"
CONF="$BASE/setup"
ASSETS="$BASE/assets"
BACKUP="$BASE/backup"
PATCHES="$BASE/patches"

LABEL="arch-setup"

OPT_TASKS=()
OPT_UPGRADE=true
OPT_PROMPT=false
OPT_LIST=false

git submodule init
git submodule update

. "$BASE/shlib/util.sh"
. "$BASE/shlib/io.sh"

. "$BASE/lib/util.sh"
. "$BASE/lib/task.sh"

_help() {
	cat << EOF
Usage:
  setup.sh [options]
  setup.sh [options] <task1> <task2> ...

Options:
  -h, --help   : Show this text
  -l, --list   : List task names
  -p, --prompt : Run in prompt mode
  --no-upgrade : Skip system upgrade

EOF
}

# commandline args
while true; do
	case "$1" in
	-h|--help)
		_help; exit
		;;
	-l|--list)
		OPT_LIST=true
		;;
	-p|--prompt)
		OPT_PROMPT=true
		;;
	--no-upgrade)
		OPT_UPGRADE=false
		;;
	-*)
		echo "invalid option '$1'";
		echo
		_help; exit
		;;
 	*)
		OPT_TASKS+=("$1")
		;;
	esac
	shift || break
done

# configuration
. "$CONF.conf"
if [ -f "$CONF.local" ]; then . "$CONF.local"
else
	cat <<- EOF > "$CONF.local"
	##
	#  setup.local
	# ----------------- -
	#  Edit this file so it suits your needs.
	#  After save it, run setup.sh again
	# ========================================

	EOF
	cat "$CONF.conf" >> "$CONF.local"

	[ -n "$EDITOR" ] || EDITOR="$(_fb-cmd nano micro nvim vim vi)" || _err "editor not found"
	"$EDITOR" "$CONF.local"
	exit
fi

if ! $OPT_LIST; then
	# only root user is allowed
	_chk-user root

	# upgrade the system first
	if $OPT_UPGRADE; then
		_install archlinux-keyring
		pacman --noconfirm --needed -Syu
	fi
fi


# ---- tasks -------- *

# hosts
if task HOSTS; then
	cat <<- EOF > /etc/hosts
	127.0.0.1  localhost
	::1        localhost
	EOF
ksat; fi

# hostname
if [ -n "$HOSTNAME" ] && task HOSTNAME -d HOSTS; then
	_var HOSTNAME
	echo "$HOSTNAME" > /etc/hostname || x
	echo "127.0.1.1  $HOSTNAME" >> /etc/hosts || x
	_show /etc/hosts
ksat; fi

# locale
if [ -n "$LOCALE" ] && task LOCALE; then
	_var LOCALE
	_uncomment "$LOCALE" /etc/locale.gen || x
	locale-gen || x
	_save-var LANG "$LOCALE" /etc/locale.conf || x
ksat; fi

# timezone
if [ -n "$TIMEZONE" ] && task TIMEZONE; then
	_var TIMEZONE
	_symlink "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime || x
	hwclock --systohc --utc || x
ksat; fi

# keymap
if [ -n "$KEYMAP" ] && task KEYMAP; then
	_var KEYMAP
	loadkeys "$KEYMAP" || x
	_save-var KEYMAP "$KEYMAP" /etc/vconsole.conf || x
ksat; fi

# reflector
if $REFLECTOR && task REFLECTOR; then
	_install reflector || x
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
	_show "$file"
	_backup "/etc/pacman.d/mirrorlist" || x
	reflector "@$file" || x
	systemctl enable reflector.timer || x
ksat; fi

# bootloader
if [ -n "$BOOTLOADER" ] && task BOOTLOADER; then
	disk="$(_fb "$DISK" $(_disk))" || x "disk not found"
	case "$BOOTLOADER" in
	grub)
		_install grub || x
		grub-install --recheck "$disk" || x "cmd failed: grub-install"
		grub-mkconfig -o /boot/grub/grub.cfg || x "cmd failed: grub-mkconfig"
		;;
	*)
		x "invalid $(_var BOOTLOADER)"
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
	_var ADMIN
	shell="$(_require $ADMIN_SHELL)" || x
	if _user-exists "$ADMIN"; then
		usermod -G "$ADMIN_GROUPS" -s "$shell" "$ADMIN" || x "cannot change shell for user: $ADMIN"
	else
		useradd -m -G "$ADMIN_GROUPS" -s "$shell" "$ADMIN" || x "cannot add user: $ADMIN"
		until passwd "$ADMIN"; do
			echo
			echo "input password for user: $ADMIN"
		done
	fi
ksat; fi

# sudo
if $SUDO && task SUDO; then
	_install sudo || x
	file="/etc/sudoers"
	case "$SUDO_ALLOW" in
		wheel)      line='%wheel ALL=(ALL:ALL) ALL' ;;
		wheel-nopw) line='%wheel ALL=(ALL:ALL) NOPASSWD: ALL' ;;
		sudo)       line='%sudo ALL=(ALL:ALL) ALL' ;;
		sudo-nopw)  line='%sudo ALL=(ALL:ALL) NOPASSWD: ALL' ;;
		*) x "invalid $(_var SUDO_ALLOW)"
	esac
	echo "$line" | _section "$LABEL" "$file" || x "failed to write: $file"
ksat; fi

# network
if [ -n "$NET_MANAGER" ] && task NETWORK; then
	_var NET_MANAGER
	case "$NET_MANAGER" in
	systemd)
		if $NET_WIRED; then
			file="wired.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "en"))" || x "network interface not found"
		else
			file="wireless.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "wl"))" || x "network interface not found"
		fi
		cat "$ASSETS/$file" | _subst "name=$nif" "dhcp=$(_yn $NET_DHCP)" "vm=$(_yn $VM)" > "/etc/systemd/network/$file" || x
		_show "/etc/systemd/network/$file"
		systemctl enable systemd-networkd.service || x
		systemctl enable systemd-resolved.service || x
		;;
	netctl)
		# TODO
		;;
	nm|networkmanager|NetworkManager)
		_install networkmanager || x
		systemctl enable NetworkManager.service || x
		systemctl enable systemd-resolved.service || x
		;;
	*)
		x "invalid $(_var NETWORK)"
	esac
ksat; fi

# ssh authorized keys
if [ -n "$SSH_AUTH_KEYS" ] && task SSH_AUTH_KEYS -d ADMIN; then
	_install openssh || x
	dir="/home/$ADMIN/.ssh"
	file="$dir/authorized_keys"
	_dir  "$dir"  -m 700 -o "$ADMIN:$ADMIN" || x
	_file "$file" -m 600 -o "$ADMIN:$ADMIN" || x
	echo "fetching auth keys from: $SSH_AUTH_KEYS ..."
	curl "$SSH_AUTH_KEYS" > "$file" || x
ksat; fi

# ssh server
if $SSHD && task SSHD -d ADMIN; then
	_install openssh || x
	file="/etc/ssh/sshd_config"
	_backup "$file" || x
	cat "$ASSETS/sshd_config" | _subst \
		"admin=$ADMIN" \
		"keepAliveTcp=$(_yn $SSHD_KEEPALIVE_TCP)" \
		"keepAliveIntvl=$SSHD_KEEPALIVE_INTVL" \
		"keepAliveCount=$SSHD_KEEPALIVE_COUNT" |
		_section "$LABEL" "$file" || x "failed to write: $file"

	_show "$file"
	systemctl enable sshd.service || x
ksat; fi

# rootkit hunter
if $RKHUNTER && task RKHUNTER; then
	exec="$(_require rkhunter)" || x
	cp "$ASSETS/rkhunter.conf.local" /etc/ || x

	file="/etc/systemd/system/rkhunter.service"
	cat "$ASSETS/rkhunter.service" | _subst "rkhunter=$exec" > "$file" || x "failed to write: $file"
	_show "$file"

	if [ -n "$RKH_TIMER" ]; then
		file="/etc/systemd/system/rkhunter.timer"
		cat "$ASSETS/rkhunter.timer" | _subst "timer=$RKH_TIMER" > "$file" || x "failed to write: $file"
		_show "$file"
		systemctl enable rkhunter.timer || x
	fi
ksat; fi

# paccache
if $PACCACHE && task PACCACHE; then
	_install pacman-contrib || x
	systemctl enable paccache.timer || x
ksat; fi

# git
if [ -n "$GIT_EMAIL" ] && [ -n "$GIT_NAME" ] && task GIT -d ADMIN; then
	_install git || x
	_var GIT_EMAIL
	_var GIT_NAME

	file="$HOME/.gitconfig"
	cat "$ASSETS/user.gitconfig" | _subst "email=$GIT_EMAIL" "name=$GIT_NAME" > "$file" || x "failed to write: $file"
	_show "$file"

	copy="/home/$ADMIN/.gitconfig"
	cp "$file" "$copy" || x "failed to copy: $file -> $copy"
	chown $ADMIN:$ADMIN "$copy" || x "cmd failed: chown"
ksat; fi

# aur helper
if $AUR && [ -n "$AUR_HELPER" ] && task AUR_HELPER -d ADMIN SUDO GIT; then
	_var AUR_HELPER
	case "$AUR_HELPER" in
	yay)
		sudo -Hu "$ADMIN" bash <<- EOF || x "cannot install: yay"
		git clone "https://aur.archlinux.org/yay.git" "\$HOME/yay" &&
		cd "\$HOME/yay" && makepkg -sic --noconfirm --needed
		rm -rf "\$HOME/yay"
		EOF
		;;
	*)
		x "invalid $(_var AUR_HELPER)"
	esac
	cd "$BASE"
ksat; fi

# graphical user interface
if $GUI; then
	# x11
	if $GUI_X && task GUI_X; then
		_install xorg-server xorg-xinit || x
		if [ -n "$GUI_X_KEYMAP" ]; then
			keymap=($GUI_X_KEYMAP)
			opts=(XkbLayout XkbModel XkbVariant XkbOptions)
			temp="$(mktemp)" || x
			cat <<- EOF > "$temp"
			Section "InputClass"
			        Identifier "system-keyboard"
			        MatchIsKeyboard "on"
			EOF
			for i in "${!keymap[@]}"; do
				echo "        Option \"${opts[$i]}\" \"${keymap[$i]}\"" >> "$temp"
			done
			echo "EndSection" >> "$temp"
			file="/etc/X11/xorg.conf.d/00-keyboard.conf"
			cat "$temp" > "$file" || x "failed to write: $file"
			_show "$file"
			rm "$temp"
		fi
	ksat; fi

	# gnome
	if $GUI_GNOME && task GUI_GNOME; then
		_install gnome || x
		systemctl enable gdm.service || x
	ksat; fi

	# install optional GUI packages
	if [ -n "$GUI_PKGS" ] && task GUI_PKGS; then
		_install "${GUI_PKGS[@]}" || x
	ksat; fi
fi

# virtual machine
if $VM && task VM; then
	case "$VM_TYPE" in
	vbox)
		_install virtualbox-guest-utils || x
		systemctl enable vboxservice.service || x
		;;
	*)
		x "invalid $(_var VM_TYPE)"
	esac
ksat; fi

# install optional packages
if [ -n "$PKGS" ] && task PKGS; then
	_install "${PKGS[@]}" || x
ksat; fi

# install AUR packages
if $AUR && [ -n "$AUR_PKGS" ] && task AUR_PKGS -d AUR_HELPER; then
	_aur-install "${AUR_PKGS[@]}" || x
ksat; fi

# patch egrep
if $PATCH_EGREP && task PATCH_EGREP; then
	if file="$(which egrep)"; then
		_backup "$file" || x
		patch "$file" < "$PATCHES/egrep.patch" || x "cannot patch: $file"
	fi
ksat; fi

# patch fgrep
if $PATCH_FGREP && task PATCH_FGREP; then
	if file="$(which fgrep)"; then
		_backup "$file" || x
		patch "$file" < "$PATCHES/fgrep.patch" || x "cannot patch: $file"
	fi
ksat; fi

# patch rkhunter
if $PATCH_RKHUNTER && task PATCH_RKHUNTER -d RKHUNTER; then
	if file="$(which rkhunter)"; then
		ver="$(_ver rkhunter)"
		patch="$PATCHES/rkhunter.$ver.patch"
		if [ -f "$patch" ]; then
			_backup "$file" || x
			patch "$file" < "$patch" || x "cannot patch: $file"
		fi
	fi
ksat; fi

# etckeeper
if $ETCKEEPER && task ETCKEEPER -d GIT; then
	_install etckeeper || x
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
	_show "$file"

	file="$dir/rkhunter-status.hook"
	cp "$ASSETS/rkhunter-status.hook" "$file" || x "failed to write: $file"
	_show "$file"
ksat; fi

# etckeeper commit
if $ETCKEEPER && is-task ETCKEEPER DONE; then
	etckeeper unclean && etckeeper commit "[$LABEL] commit @ $(date +%F)"
fi

# rkhunter propupd
if $RKHUNTER && task RKH_PROPUPD -d RKHUNTER; then
	rkhunter --config-check || x "rkhunter: config error"
	rkhunter --propupd --report-warnings-only || x "rkhunter: propupd error"
ksat; fi


if ! $OPT_LIST; then
	echo
	echo "all done."
	echo
	echo "if you are in chroot, type:"
	echo "exit; umount -R /mnt"
	echo
fi
