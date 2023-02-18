# [Arch Setup](https://github.com/amekusa/arch-setup/)
Arch Linux setup script written by [amekusa](https://github.com/amekusa/)

**Arch Setup** is just a plain bash script.  
No dependencies. No fancy technologies are involved. But it's very carefully coded.

The config file is another bash script with just a bunch of variables. Most of them have good default values so you have to edit only a few of them.

The setup script supports:
- bootloader (grub)
- locale, keymap and timezone
- VirtualBox guest additions
- user (groups, default shell, ssh, git, sudo)
- ssh server
- network manager (systemd-networkd, NetworkManager)
- etckeeper
- rkhunter (+ systemd timer)
- reflector (+ systemd timer)
- paccache (+ systemd timer)
- AUR helper (yay)
- X11 and XKeyMap
- GNOME desktop

Also supports **patching the annoying warnings of egrep, fgrep, and rkhunter** (2022-10-23).

The script is supposed to be ran in `chroot` where the basic packages have already been installed with `pacstrap`. If your Arch is not ready, follow the instructions below.


## Commandline Usage

```
Usage:
  setup.sh [options]
  setup.sh [options] <task1> <task2> ...

Options:
  -h, --help   : Show this text
  -l, --list   : List task names
  -p, --prompt : Run in prompt mode
  --no-upgrade : Skip system upgrade
```


## Getting Started
Insert the latest Arch Linux live CD and boot it.

### Set the correct keymap for the console
The default keymap is `us`.
Unless you are using a US keyboard, you should set the correct keymap for the current console with `loadkeys` command.

```sh
# Japanese
loadkeys jp106
```

### Partitioning the disk

```sh
lsblk
```

```sh
cgdisk /dev/sda
```

The `sda` part may vary. Check the output of `lsblk` command and type the correct identifier.

In `cgdisk`, edit the partition table as you like. Do not forget to save it.

Here is an example:

Part. # | Size | Partition Type | Name | Mount Point
-------:|-----:|---------------:|:-----|:-----------
4 | 1007.0 KiB | BIOS boot partition (ef02) | BIOS | -
1 | 128 MB | Linux filesystem (8300) | Boot | /boot
2 | 2 GB | Linux swap (8200) | Swap | -
3 | the rest | Linux filesystem (8300) | Root | /

### Create filesystems

```sh
# boot partition
mkfs.ext4 /dev/sda1
# root partition
mkfs.ext4 /dev/sda3
```

Create `ext4` filesystem on each `Linux filesystem (8300)` partition you've created.

### Activate swap

```sh
mkswap /dev/sda2
swapon /dev/sda2
```

### Mount the partitions
Mount the root partition to `/mnt`.

```sh
mount /dev/sda3 /mnt
```

Mount the boot partition to `/mnt/boot`.

```sh
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
```

### Install Arch
Install the base Arch Linux system with `pacstrap` command.

```sh
pacstrap /mnt base base-devel linux linux-firmware nano git
```

### Generate `fstab`
`fstab` is necessary for the system to mount the partitions automatically on start up.  

```sh
genfstab -U /mnt >> /mnt/etc/fstab
```

### Enter the base system

```sh
arch-chroot /mnt /bin/bash
```

Now you can access `/mnt` as `/`.

That's it. Your part is done. The setup script will handle the rest.  
Proceed to the next section.


## Using the script

### Clone this repository

```sh
cd
git clone https://github.com/amekusa/arch-setup.git
cd arch-setup
```

### Run the script and edit your config file

```sh
./setup.sh
```

At the first time you run `setup.sh`, it generates a config file: `setup.local` and opens it with `nano`.
Edit some of the variables so they suit your needs. Do not forget to save it with `Ctrl+O`.

### Run the script again

```sh
./setup.sh
```

This time, the script actually runs all the setup operations necessary for your Arch environment.

The operations are separated with "tasks."
If something went wrong along the process, the script immediately stops and shows which task failed.

Completed tasks are saved to `.tasks` file, and the next time you run the script, they will be skipped respectively.

### Exit `chroot`, unmount, and reboot
If the script finished without any errors, setup is done.

```sh
exit
umount -R /mnt
reboot now
```

That's it. Enjoy.

---

If you like this, give me a :star:.  
Pull requests are welcomed as well.

	© 2022 Satoshi Soma  
	https://amekusa.com
	https://github.com/amekusa
