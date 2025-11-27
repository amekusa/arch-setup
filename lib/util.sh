#
#  Utilities for arch-setup
# -------------------------- -  *
#  author: Satoshi Soma (https://amekusa.com)
# ============================================

# installs the given pkg
_install() {
	pacman --noconfirm --needed -S "$@"
}

# installs the given pkg with AUR helper
_aur-install() {
	case "$AUR_HELPER" in
	yay)
		sudo -Hu "$ADMIN" bash -c "yay --noconfirm --needed -S $@"
		;;
	*)
		return 1
	esac
}

# enables the given systemd service
_sys-enable() {
	if systemctl is-enabled --quiet "$1"; then
		echo "'$1' is already enabled"
		return 0
	fi
	systemctl enable "$1"
}

# returns the version number of the given pkg.
# pkgrel ('-N') is not included
_ver() {
	pacman -Qi "$1" | awk -F' : ' '$1 ~ "Version" { print $2 }' | cut -d'-' -f 1
}

# returns full path to the given pkg.
# if it does not exist, installs it
_require() {
	local r
	r="$(which "$1")" && echo "$r" && return
	_install "$1" &> /dev/null || return 1
	echo "$(which "$1")"
}

# checks if the given user exists
_user-exists() {
	id "$1" &> /dev/null
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

_var() {
	local var="$1"
	echo "$var: ${!var}"
}

_show() {
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
	local src="$1"
	[ -e "$src" ] || return 0
	local now="$(date +%F)"
	local dst="$BACKUP/$(basename "$1").$now.backup"
	echo "backup:"
	echo " > src: $src"
	echo " > dst: $dst"
	echo "# backup at:$now src:$src" > "$dst"
	cat "$src" >> "$dst"
}
