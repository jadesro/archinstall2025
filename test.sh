#!/usr/bin/zsh
# Install Arch with LUKS on a QEMU VM
#
# use
# curl -OL https://raw.githubusercontent.com/jadesro/archinstall2025/refs/heads/main/test.sh
# zsh test.sh
# after reboot
# wget -qO- https://omarchy.org/install | bash
#set -x

# BOOT ARCH from ISO

exec > >(tee -i test.log)
exec 2>&1

echo "++++++++++ ARCH INSTALLER +++++++++++\n\n"
echo "\n\n"

read "?Username: " myusername
export MYUSERNAME=$myusername

read -s "?Password: " password1
echo -ne "\n"
read -s "?Reenter password: " password2
echo -ne "\n"
if [[ "$password1"  != "$password2" ]]; then
   echo -ne "Error - No match.  Start over"
   exit
fi
export PASSWORD=$password1

read "?Machine name: " machine
export MACHINE=$machine

echo "Pick which disk to install to:"
echo "lsblk output"
lsblk
echo "Possible disks:"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" | "$3}'
echo -ne "\n"
read "?Disk: " target_disk
export DISK=$target_disk

lsblk

echo "++++++++++ Selected Options +++++++++++\n\n"
echo "DISK is : " ${DISK}
echo "User is : " ${MYUSERNAME}
echo "Host is : " ${MACHINE}

# it is important to setup the time correctly because pacman/pacstrap need
# a correct time stamp to create the keystore
timedatectl set-timezone America/New_York
timedatectl set-ntp true

# Format new disk
# umount -A --recursive /mnt # make sure everything is unmounted before we start
# disk prep
# where DISK is /dev/vda for instance (which is a disk on a QEMU VM)
# export DISK=/dev/vda
sgdisk -Z ${DISK} # zap all on disk
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# create partitions
# sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOS' ${DISK} # partition 1 (BIOS Boot Partition)
# sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFI' ${DISK} # partition 2 (UEFI Boot Partition)
# sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining

sgdisk -n 1::+1M   --typecode=1:ef02 --change-name=1:'BOOT' ${DISK} # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+1GiB --typecode=2:ef00 --change-name=2:'EFI'  ${DISK} # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0    --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining


if [[ ! -d "/sys/firmware/efi" ]]; then # BIOS or EFI?
   # set bit 2 attribute on partition 1 to 2 ==> legacy BIOS bootable
   # if EFI this is not required
   sgdisk -A 1:set:2 ${DISK}
fi
partprobe ${DISK} # reread partition table to ensure it is correct

# Partitioning of the target disk
# See my setup above
# If using a new (blank) drive, create a boot partition which is at least 1G
# if a new disk partition plan is required, use gptdisk 
# gptdisk has two modes: gdisk (GUI) and sgdisk (CLI)

# Format the main partition
# REMEMBER THE PASSWORD!!!
export CRYPT=/dev/vda3
echo -n "$PASSWORD" | cryptsetup -v luksFormat ${CRYPT} -

# Open it as "main"  (main is the parition name and will be used in the following steps)
echo -n "$PASSWORD" | cryptsetup luksOpen ${CRYPT} main -

# Format the main partition with btrfs
# note here we reuse the main "name" from the luksOpen statement
mkfs.btrfs -f -L ROOT /dev/mapper/main

echo "++++++++++ Disk Prep completed +++++++++++\n\n"
lsblk


# mount the paritiions
mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg

umount /mnt

# now that the btrfs subvolume have been created, it's time to mount them
export MOUNTOPTIONS="noatime,compress=zstd,space_cache=v2,discard=async"
# If ssd use:
# export MOUNTOPTIONS="noatime,ssd,compress=zstd,space_cache=v2,discard=async"
mount -o ${MOUNTOPTIONS},subvol=@ /dev/mapper/main /mnt

mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg}
mount -o ${MOUNTOPTIONS},subvol=@home /dev/mapper/main /mnt/home
mount -o ${MOUNTOPTIONS},subvol=@log  /dev/mapper/main /mnt/var/log
mount -o ${MOUNTOPTIONS},subvol=@pkg  /dev/mapper/main /mnt/var/cache/pacman/pkg

# if using a new drive, format the EFI partition
mkfs.fat -F32 -n "EFI" ${DISK}2
mkdir /mnt/boot
mount ${DISK}2 /mnt/boot

echo "++++++++++ Encrypted partition UUID +++++++++++\n\n"
# Remember the UUID of the root partition:
# blkid -s UUID -o value "${CRYPT}"
export ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${CRYPT}")
echo $ENCRYPTED_PARTITION_UUID

echo "++++++++++ All disks/partitions mounted and ready for chroot +++++++++++\n\n"
cat /proc/mounts

echo "++++++++++ Install base package +++++++++++\n\n"
# Install the base packages
pacstrap /mnt base

# Generate the filesystem table
genfstab -U -p /mnt >> /mnt/etc/fstab
# check it
echo "++++++++++ fstab created +++++++++++\n\n"
cat /mnt/etc/fstab

echo "+++++++++ install grub if in BIOS mode ++++++++"
if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot "${DISK}"
fi

# Change into the new system root
echo "++++++++++ Start chroot +++++++++++\n\n"
arch-chroot /mnt /bin/bash -c "KEYMAP='us' /bin/bash" <<EOF


echo "Arch chroot started"
echo "DISK is : " ${DISK}
echo "User is : " ${MYUSERNAME}
echo "Host is : " ${MACHINE}
echo "Crypt is: " ${CRYPT}
echo "UUID is : " ${$ENCRYPTED_PARTITION_UUID}

# optional: set the computer clock to the new time
# hwclock --systohc

# Set locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
echo "KEYMAP=us" >> /etc/vconsole.conf
localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8"

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
timedatectl --no-ask-password set-timezone America/New_York
timedatectl --no-ask-password set-ntp 1

# Set hostname
echo $MACHINE > /etc/hostname

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create first user (superuser) and add them to SUDO
echo "Creating User $MYUSERNAME"
useradd -m -g users -G wheel -s /bin/bash $MYUSERNAME
echo "$MYUSERNAME:$PASSWORD" | chpasswd
mkdir -p -m 755 /etc/sudoers.d
echo "$MYUSERNAME ALL=(ALL) ALL" >> /etc/sudoers.d/$MYUSERNAME
chmod 0440 /etc/sudoers.d/$MYUSERNAME
echo "########################################################################"
cat /etc/passwd
echo "########################################################################"


# Setup reflector so we can optimise downloads and installation
pacman -Syu
pacman --noconfirm --needed -S reflector rsync
# reflector --country US --protocol http,https,rsync --download-timeout 2 -a 12 --sort rate --save /etc/pacman.d/mirrorlist
# reflector --country Canada --ipv4 --age 12 --download-timeout=3 --threads 3 --fastest 10 --sort rate --save /etc/pacman.d/mirrorlist
reflector --country Canada --ipv4 --age 48 --download-timeout=3 --threads 3 --fastest 10 --score 5 --sort rate --save /etc/pacman.d/mirrorlist
cat /etc/pacman.d/mirrorlist

# install the packages needed for the grub installation - most of the app/packages will be installed later by the Omarchy script

pacman --noconfirm -Syu base-devel linux linux-headers linux-firmware btrfs-progs grub mtools networkmanager network-manager-applet sudo openssh git acpid grub-btrfs wget

# Install efibootmgr if EFI configuration
if [[ -d "/sys/firmware/efi" ]]; then
   echo "++++++++++ EFI Boot Manager +++++++++++\n\n"
   pacman --noconfirm -S efibootmgr
fi

pacman --noconfirm -S intel-ucode
# pacman --noconfirm -S amd-ucode
pacman --noconfirm -S man-db man-pages bluez bluez-utils pipewire pipewire-pulse pipewire-jack sof-firmware ttf-firacode-nerd alacritty

# Time to edit the mkinitcpi configuration so we can boot into the new encrypted system
# Open the mkinitcpio.conf file and look for the HOOKS line
# insert "encrypt" before filesystems
# insert "btrfs" to the MODULES list
# if desktop: add usbhid and atkbd to MODULES so that external keyboard will be available at boot in order to enter the decrypt password
#nvim /etc/mkinitcpio.conf
sed -i 's/filesystems fsck/encrypt filesystems fsck/g' /etc/mkinitcpio.conf
sed -i 's/MODULES=()/MODULES=(btrfs atkbd)/g' /etc/mkinitcpio.conf
mkinitcpio -p linux
echo "++++++++++ mkinitcpio.conf +++++++++++\n\n"
cat /etc/mkinitcpio.conf

# Install grub 
if [[ -d "/sys/firmware/efi" ]]; then
   echo "++++++++++ GRUB EFI Install +++++++++++\n\n"
   grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
#else
#   echo "++++++++++ GRUB BIOS Install +++++++++++\n\n"
#   grub-install --boot-directory=/mnt/boot "${DISK}"
#fi

# Insert it in the grub config and regenerate
# the GRUB_CMDLINE_LINUX_DEFAULT should now have the argument
#"loglevel=3 quiet cryptdevice=UUID=xxxxxxxxxxxx:main root=/dev/mapper/main"
# note the ":main" text after the UUID

# parexport ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${CRYPT}")
#sed -i "s%GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet%GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet splash cryptdevice=UUID=${ENCRYPTED_PARTITION_UUID}:main root=/dev/mapper/main%g" /etc/default/grub
sed -i "s%GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet%GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=${ENCRYPTED_PARTITION_UUID}:main%g" /etc/default/grub
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
#  mkinitcpio -p linux
# if we get an error (can't write to /boot), we need to remount boot as read/write and rerun the command
#mount -n -o remount,rw /boot
#mkinitcpio -p linux
grub-mkconfig -o /boot/grub/grub.cfg
echo "++++++++++ GRUB mkconfig  +++++++++++\n\n"
cat /boot/grub/grub.cfg

## Install grub if EFI configuration
#if [[ -d "/sys/firmware/efi" ]]; then
#   # grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
#   grub-install --efi-directory=/boot ${DISK}
#fi
##

# at this point I realized that the Windows created boot partition is only 100MB.  The partition was used at over 90% not leaving enough space for
# the mkinitcpio to perform its job.
# I deleted the fallback images as well as all the extra languages installed by MS
# rm /boot/EFI/Microsoft/Boot/xx-XX
# rm /boot/initramfs-linux-fallback.img
#mkinitcpio -p linux
#nvim /etc/mkinitcpio.conf


systemctl enable NetworkManager
# systemctl enable bluetooth
systemctl enable sshd
systemctl enable reflector
systemctl enable reflector.timer
# systemctl enable acpid

# reboot - after which we should have a minimally installed Arch Linux working system.
EOF
