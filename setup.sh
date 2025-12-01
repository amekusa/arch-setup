#!/bin/bash
# --- Arch Setup ---
# @author Satoshi Soma (github.com/amekusa)
# ============================================

BASE="$(dirname "$(realpath "$0")")"

ASSETS="$BASE/assets"
BACKUP="$BASE/backup"
PATCHES="$BASE/patches"

git submodule init
git submodule update

. "$BASE/ush/load" util
. "$BASE/ush/load" io
. "$BASE/ush/load" task

. "$BASE/lib/util.sh"


# === PARSE ARGS ===
_help() {
	cat <<- EOF
	Usage:
	  setup.sh [options]
	  setup.sh [options] <task1> <task2> ...

	Options:
	  -h, --help   : Show this text
	  -l, --list   : List task names
	  -p, --prompt : Run in prompt mode
	  -r, --reset  : Reset tasks
	  -F, --force  : Force run tasks

	EOF
}

TASK_OPTS=()
while [ $# -gt 0 ]; do
	case "$1" in
	-h|--help)
		_help; exit
		;;
 	*)
		TASK_OPTS+=("$1")
		;;
	esac
	shift
done


# === CONFIG ===
. "$BASE/default.conf"
if [ -f "$BASE/user.conf" ]; then
	. "$BASE/user.conf"
else
	cat <<- EOF > "$BASE/user.conf"
	#  --- user.conf ---
	#  Edit this file so it suits your needs.
	#  After save it, run setup.sh again
	# ========================================

	EOF
	cat "$BASE/default.conf" >> "$BASE/user.conf"
	[ -n "$EDITOR" ] || EDITOR="$(_fb-cmd -f nano nvim vim vi '')" || _die "editor not found"
	"$EDITOR" "$BASE/user.conf"
	exit
fi


# === TASKS ===
_task-system -s "$BASE/tasks" "${TASK_OPTS[@]}"

# system update
if _task UPDATE; then
	_install archlinux-keyring
	pacman --noconfirm --needed -Syu
fi

# hosts
if _task HOSTS; then
	_backup "/etc/hosts" || _fail
	cat <<- EOF > "/etc/hosts"
	127.0.0.1  localhost
	::1        localhost
	EOF
fi

# hostname
if [ -n "$HOST" ] && _task HOSTNAME -d HOSTS; then
	_var HOST
	_backup "/etc/hostname" || _fail
	echo "$HOST" > "/etc/hostname" || _fail
	echo "127.0.1.1  $HOST" >> "/etc/hosts" || _fail
	_show "/etc/hosts"
fi

# locale
if [ -n "$LOCALE" ] && _task LOCALE; then
	_var LOCALE
	_uncomment "$LOCALE" "/etc/locale.gen" || _fail
	locale-gen || _fail
	_save-var LANG "$LOCALE" "/etc/locale.conf" || _fail
fi

# timezone
if [ -n "$TIMEZONE" ] && _task TIMEZONE; then
	_var TIMEZONE
	_symlink "/usr/share/zoneinfo/$TIMEZONE" "/etc/localtime" || _fail
	hwclock --systohc --utc || _fail
fi

# keymap
if [ -n "$KEYMAP" ] && _task KEYMAP; then
	_var KEYMAP
	loadkeys "$KEYMAP" || _fail
	_save-var KEYMAP "$KEYMAP" "/etc/vconsole.conf" || _fail
fi

# reflector
if $REFLECTOR && _task REFLECTOR; then
	_install reflector || _fail
	file="/etc/xdg/reflector/reflector.conf"
	[ -f "$file" ] || _fail "file not found: $file"
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
	_backup "/etc/pacman.d/mirrorlist" || _fail
	reflector "@$file" || _fail
	_sys-enable reflector.timer || _fail
fi

# bootloader
if [ -n "$BOOTLOADER" ] && _task BOOTLOADER; then
	disk="$(_fb "$DISK" $(_disk))" || _fail "disk not found"
	case "$BOOTLOADER" in
	grub)
		_install grub || _fail
		grub-install --recheck "$disk" || _fail "cmd failed: grub-install"
		grub-mkconfig -o "/boot/grub/grub.cfg" || _fail "cmd failed: grub-mkconfig"
		;;
	*)
		_fail "invalid $(_var BOOTLOADER)"
		;;
	esac
fi

# root user
if _task ROOT; then
	until passwd; do
		echo
		echo "input password for root user"
	done
fi

# admin user
if [ -n "$ADMIN" ] && _task ADMIN; then
	_var ADMIN
	shell="$(_require $ADMIN_SHELL)" || _fail
	if _user-exists "$ADMIN"; then
		usermod -G "$ADMIN_GROUPS" -s "$shell" "$ADMIN" || _fail "cannot change shell for user: $ADMIN"
	else
		useradd -m -G "$ADMIN_GROUPS" -s "$shell" "$ADMIN" || _fail "cannot add user: $ADMIN"
		until passwd "$ADMIN"; do
			echo
			echo "input password for user: $ADMIN"
		done
	fi
fi

# sudo
if $SUDO && _task SUDO; then
	_install sudo || _fail
	file="/etc/sudoers"
	case "$SUDO_ALLOW" in
		wheel)      line='%wheel ALL=(ALL:ALL) ALL' ;;
		wheel-nopw) line='%wheel ALL=(ALL:ALL) NOPASSWD: ALL' ;;
		sudo)       line='%sudo ALL=(ALL:ALL) ALL' ;;
		sudo-nopw)  line='%sudo ALL=(ALL:ALL) NOPASSWD: ALL' ;;
		*)          _fail "invalid $(_var SUDO_ALLOW)" ;;
	esac
	echo "$line" | _section "$LABEL" "$file" || _fail "failed to write: $file"
fi

# network
if [ -n "$NET_MANAGER" ] && _task NETWORK; then
	_var NET_MANAGER
	case "$NET_MANAGER" in
	systemd)
		if $NET_WIRED; then
			file="wired.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "en"))" || _fail "network interface not found"
		else
			file="wireless.network"
			nif="$(_fb "$NET_INTERFACE" $(_nif "wl"))" || _fail "network interface not found"
		fi
		cat "$ASSETS/$file" | _subst "name=$nif" "dhcp=$(_yn $NET_DHCP)" "vm=$(_yn $VM)" > "/etc/systemd/network/$file" || _fail
		_show "/etc/systemd/network/$file"
		_sys-enable systemd-networkd.service || _fail
		_sys-enable systemd-resolved.service || _fail
		;;
	netctl)
		# TODO
		;;
	nm|networkmanager|NetworkManager)
		_install networkmanager || _fail
		_sys-enable NetworkManager.service || _fail
		_sys-enable systemd-resolved.service || _fail
		;;
	*)
		_fail "invalid $(_var NET_MANAGER)"
		;;
	esac
fi

# ssh authorized keys
if [ -n "$SSH_AUTH_KEYS" ] && _task SSH_AUTH_KEYS -d ADMIN; then
	_install openssh || _fail
	dir="/home/$ADMIN/.ssh"
	file="$dir/authorized_keys"
	_dir  "$dir"  -m 700 -o "$ADMIN:$ADMIN" || _fail
	_file "$file" -m 600 -o "$ADMIN:$ADMIN" || _fail
	echo "fetching auth keys from: $SSH_AUTH_KEYS ..."
	curl "$SSH_AUTH_KEYS" > "$file" || _fail
fi

# ssh server
if $SSHD && _task SSHD -d ADMIN; then
	_install openssh || _fail
	file="/etc/ssh/sshd_config"
	_backup "$file" || _fail
	cat "$ASSETS/sshd_config" | _subst \
		"admin=$ADMIN" \
		"keepAliveTcp=$(_yn $SSHD_KEEPALIVE_TCP)" \
		"keepAliveIntvl=$SSHD_KEEPALIVE_INTVL" \
		"keepAliveCount=$SSHD_KEEPALIVE_COUNT" |
		_section "$LABEL" "$file" || _fail "failed to write: $file"

	_show "$file"
	_sys-enable sshd.service || _fail
fi

# rootkit hunter
if $RKHUNTER && _task RKHUNTER; then
	exec="$(_require rkhunter)" || _fail
	cp "$ASSETS/rkhunter.conf.local" /etc/ || _fail

	file="/etc/systemd/system/rkhunter.service"
	cat "$ASSETS/rkhunter.service" | _subst "rkhunter=$exec" > "$file" || _fail "failed to write: $file"
	_show "$file"

	if [ -n "$RKH_TIMER" ]; then
		file="/etc/systemd/system/rkhunter.timer"
		cat "$ASSETS/rkhunter.timer" | _subst "timer=$RKH_TIMER" > "$file" || _fail "failed to write: $file"
		_show "$file"
		_sys-enable rkhunter.timer || _fail
	fi
fi

# paccache
if $PACCACHE && _task PACCACHE; then
	_install pacman-contrib || _fail
	_sys-enable paccache.timer || _fail
fi

# git
if [ -n "$GIT_EMAIL" ] && [ -n "$GIT_NAME" ] && _task GIT -d ADMIN; then
	_install git || _fail
	_var GIT_EMAIL
	_var GIT_NAME

	file="$HOME/.gitconfig"
	cat "$ASSETS/user.gitconfig" | _subst "email=$GIT_EMAIL" "name=$GIT_NAME" > "$file" || _fail "failed to write: $file"
	_show "$file"

	copy="/home/$ADMIN/.gitconfig"
	cp "$file" "$copy" || _fail "failed to copy: $file -> $copy"
	chown $ADMIN:$ADMIN "$copy" || _fail "cmd failed: chown"
fi

# aur helper
if $AUR && [ -n "$AUR_HELPER" ] && _task AUR_HELPER -d ADMIN SUDO GIT; then
	_var AUR_HELPER
	case "$AUR_HELPER" in
	yay)
		sudo -Hu "$ADMIN" bash <<- EOF || _fail "cannot install: yay"
		git clone "https://aur.archlinux.org/yay.git" "\$HOME/yay" &&
		cd "\$HOME/yay" && makepkg -sic --noconfirm --needed
		rm -rf "\$HOME/yay"
		EOF
		;;
	*)
		_fail "invalid $(_var AUR_HELPER)"
		;;
	esac
	cd "$BASE"
fi

# graphical user interface
if $GUI; then

	# x11
	if $GUI_X && _task GUI_X; then
		_install xorg-server xorg-xinit || _fail
		if [ -n "$GUI_X_KEYMAP" ]; then
			keymap=($GUI_X_KEYMAP)
			opts=(XkbLayout XkbModel XkbVariant XkbOptions)
			temp="$(mktemp)" || _fail
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
			cat "$temp" > "$file" || _fail "failed to write: $file"
			_show "$file"
			rm "$temp"
		fi
	fi

	if [ -n "$GUI_DE" ] && _task GUI_DE; then
		case "$GUI_DE" in
		bspwm)

			;;
		i3)
			_fail "i3 is not supported yet"
			;;
		gnome)
			_install gnome || _fail
			;;
		esac
	fi

	# display manager
	if [ -n "$GUI_DM" ] && _task GUI_DM; then
		case "$GUI_DM" in
		lightdm)
			_install lightdm || _fail
			_install lightdm-gtk-greeter || _fail
			_sys-enable lightdm.service || _fail
			;;
		gdm)
			_install gdm || _fail
			_sys-enable gdm.service || _fail
			;;
		esac
	fi

	# install optional GUI packages
	if [ -n "$GUI_PKGS" ] && _task GUI_PKGS; then
		_install "${GUI_PKGS[@]}" || _fail
	fi
fi

# virtual machine
if $VM && _task VM; then
	case "$VM_TYPE" in
	qemu)
		if $GUI; then
			_install mesa || _fail
		fi
		;;
	vbox)
		if $GUI_X
			then _install virtualbox-guest-utils || _fail
			else _install virtualbox-guest-utils-nox || _fail
		fi
		_sys-enable vboxservice.service || _fail
		;;
	esac
fi

# install optional packages
if [ -n "$PKGS" ] && _task PKGS; then
	_install "${PKGS[@]}" || _fail
fi

# install AUR packages
if $AUR && [ -n "$AUR_PKGS" ] && _task AUR_PKGS -d AUR_HELPER; then
	_aur-install "${AUR_PKGS[@]}" || _fail
fi

# patch egrep
if $PATCH_EGREP && _task PATCH_EGREP; then
	if file="$(which egrep)"; then
		_backup "$file" || _fail
		patch "$file" < "$PATCHES/egrep.patch" || _fail "cannot patch: $file"
	fi
fi

# patch fgrep
if $PATCH_FGREP && _task PATCH_FGREP; then
	if file="$(which fgrep)"; then
		_backup "$file" || _fail
		patch "$file" < "$PATCHES/fgrep.patch" || _fail "cannot patch: $file"
	fi
fi

# patch rkhunter
if $PATCH_RKHUNTER && _task PATCH_RKHUNTER -d RKHUNTER; then
	if file="$(which rkhunter)"; then
		ver="$(_ver rkhunter)"
		patch="$PATCHES/rkhunter.$ver.patch"
		if [ -f "$patch" ]; then
			_backup "$file" || _fail
			patch "$file" < "$patch" || _fail "cannot patch: $file"
		fi
	fi
fi

# etckeeper
if $ETCKEEPER && _task ETCKEEPER -d GIT; then
	_install etckeeper || _fail
	file="/etc/.gitignore"
	cp "$ASSETS/etc.gitignore" "$file" || _fail "failed to write: $file"
	etckeeper init || _fail "cmd failed: etckeeper init"
fi

# pacman hooks for rkhunter
if $RKHUNTER && $RKH_HOOKS && _task RKH_HOOKS -d RKHUNTER; then
	dir="/etc/pacman.d/hooks"
	[ -d "$dir" ] || mkdir "$dir" || _fail "cannot create dir: $dir"

	file="$dir/rkhunter-propupd.hook"
	cat "$ASSETS/rkhunter-propupd.hook" | _subst "rkhunter=$(which rkhunter)" > "$file" || _fail "failed to write: $file"
	_show "$file"

	file="$dir/rkhunter-status.hook"
	cp "$ASSETS/rkhunter-status.hook" "$file" || _fail "failed to write: $file"
	_show "$file"
fi

# etckeeper commit
if $ETCKEEPER && _is-task ETCKEEPER DONE; then
	etckeeper unclean && etckeeper commit "[$LABEL] commit @ $(date +%F)"
fi

# rkhunter propupd
if $RKHUNTER && _task RKH_PROPUPD -d RKHUNTER; then
	rkhunter --config-check || _fail "rkhunter: config error"
	rkhunter --propupd --report-warnings-only || _fail "rkhunter: propupd error"
fi


cat <<- EOF

all done.

if you are in chroot, type:
exit; umount -R /mnt

EOF

