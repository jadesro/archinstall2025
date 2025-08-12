# Install Arch with LUKS on a QEMU VM
#
set -x

# BOOT ARCH from ISO

echo "++++++++++ ARCH INSTALLER +++++++++++"
echo "\n"

read -r -p "Username: " username
export USERNAME=$username

read -rs -p "Password: " password1
echo -ne "\n"
read -rs -p "Reenter password: " password2
echo -ne "\n"
if [[ "$password1"  != "$password2" ]]; then
   echo -ne "Error - No match.  Start over"
   exit
fi
export PASSWORD=$password1

timedatectl set-timezone America/New_York
timedatectl set-ntp true

# Format new disk
# umount -A --recursive /mnt # make sure everything is unmounted before we start
# disk prep
# where DISK is /dev/vda for instance (which is a disk on a QEMU VM)
export DISK=/dev/vda
sgdisk -Z ${DISK} # zap all on disk
sgdisk -a 2048 -o ${DISK} # new gpt disk 2048 alignment

# create partitions
# sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOS' ${DISK} # partition 1 (BIOS Boot Partition)
# sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFI' ${DISK} # partition 2 (UEFI Boot Partition)
# sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining

sgdisk -n 1::+1M   --typecode=1:ef00 --change-name=1:'BOOT' ${DISK} # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+1GiB --typecode=2:ef00 --change-name=2:'EFI'  ${DISK} # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0    --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining


if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
   # set bit 2 attribute on partition 1 to 2 ==> legacy BIOS bootable
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
echo -n "$PASSWORD" | cryptsetup luksFormat ${CRYPT} -

# Open it as "main"  (main is the parition name and will be used in the following steps)
echo -n "$PASSWORD" | cryptsetup luksOpen ${CRYPT} main -

# Format the main partition with btrfs
# note here we reuse the main "name" from the luksOpen statement
mkfs.btrfs -L ROOT /dev/mapper/main

# mount the paritiions
mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg

umount /mnt

# now that the btrfs subvolume have been created, it's time to mount them
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt

mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg}
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@log  /dev/mapper/main /mnt/var/log
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@pkg  /dev/mapper/main /mnt/var/cache/pacman/pkg

# if using a new drive, format the EFI partition
mkfs.vfat -F32 -n "EFI" ${DISK}1
mkdir /mnt/boot
mount ${DISK}1 /mnt/boot

# Install the base packages
pacstrap -K /mnt base linux linux-firmware

# Generate the filesystem table
genfstab -U -p /mnt >> /mnt/etc/fstab
# check it
cat /mnt/etc/fstab

# Remember the UUID of the root partition:
blkid -s UUID -o value "${CRYPT}"
export ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${CRYPT}")

# Change into the new system root
arch-chroot /mnt /bin/bash -c "KEYMAP='us' /bin/bash" <<EOF



# optional: set the computer clock to the new time
# hwclock --systohc

# Set locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8"

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
timedatectl --no-ask-password set-timezone America/New_York
timedatectl --no-ask-password set-ntp 1

# Set hostname
echo "omarch" >> /etc/hostname

# Set root password
passwd

# Create first user (superuser) and add them to SUDO
useradd -m -g users -G wheel bob
passwd bob
mkdir -p -m 755 /etc/sudoers.d
echo "bob ALL=(ALL) ALL" >> /etc/sudoers.d/bob
chmod 0440 /etc/sudoers.d/bob

# Setup reflector so we can optimise downloads and installation
pacman --noconfirm -S reflector
reflector --country Canada --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist

# install the packages needed for the grub installation - most of the app/packages will be installed later by the Omarchy script

pacman --noconfirm -Syu base-devel linux linux-headers linux-firmware btrfs-progs grub mtools networkmanager network-manager-applet sudo openssh git acpid grub-btrfs wget neovim
pacman --noconfirm -S intel-ucode
# pacman -S man-db man-pages bluez bluez-utils pipewire pipewire-pulse pipewire-jack sof-firmware ttf-firacode-nerd alacritty firefox

# Time to edit the mkinitcpi configuration so we can boot into the new encrypted system
# Open the mkinitcpio.conf file and look for the HOOKS line
# insert "encrypt" before filesystems
# insert "btrfs" to the MODULES list
# if desktop: add usbhid and atkbd to MODULES so that external keyboard will be available at boot in order to enter the decrypt password
#nvim /etc/mkinitcpio.conf
sed -i 's/filesystems/encrypt filesystems/g' /etc/mkinitcpio.conf
mkinitcpio -p linux
# if we get an error (can't write to /boot), we need to remount boot as read/write and rerun the command
#mount -n -o remount,rw /boot
#mkinitcpio -p linux

# at this point I realized that the Windows created boot partition is only 100MB.  The partition was used at over 90% not leaving enough space for
# the mkinitcpio to perform its job.
# I deleted the fallback images as well as all the extra languages installed by MS
# rm /boot/EFI/Microsoft/Boot/xx-XX
# rm /boot/initramfs-linux-fallback.img
#mkinitcpio -p linux
#nvim /etc/mkinitcpio.conf

# Install grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Get the UUID of the boot disk
blkid -s UUID -o value /dev/nvme0n1p5
# Insert it in the grub config and regenerate
# the GRUB_CMDLINE_LINUX_DEFAULT should now have the argument
#"loglevel=3 quiet cryptdevice=UUID=xxxxxxxxxxxx:main root=/dev/mapper/main"
# note the ":main" text after the UUID
sed -i "s%GRUB_CMDLINE_LINUX_DEFAULT=\"%GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${ENCRYPTED_PARTITION_UUID}:main root=/dev/mapper/main %g" /etc/default/grub
# nvim /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg


systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sshd
systemctl enable reflector
systemctl enable reflector.timer
systemctl enable acpid

# reboot - after which we should have a minimally installed Arch Linux working system.
EOF
