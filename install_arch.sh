# Example
# Install ARCH on the nvme disk while keeping the existing Windows partitions intact
# Boot partition will be shared with Windows and is at nvme0n1p1
# Target partition for Arch is nvme0n1p5
#

# BOOT ARCH from ISO
# The default locale and console keyboard layout are fine
# I use Ethernet but if needed use iwctl to connect to a WiFi network

timedatectl set-timezone America/New_York
timedatectl set-ntp true

# Partitioning of the target disk
# See my setup above
# If using a new (blank) drive, create a boot partition which is at least 1G

# Format the main partition
cryptsetup luksFormat /dev/nvme0n1p5

# Open it as "main"  (main is the parition name and will be used in the following steps)
cryptsetup luksOpen /dev/nvme0n1p5 main

# Format the main partition with btrfs
# note here we reuse the main "name" from the luksOpen statement
mkfs.btrfs /dev/mapper/main

# mount the paritiions
mount /dev/mapper/main /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home

# the next subvolumes are created in some examples of use
# btrfs subvolume create @log
# btrfs subvolume create @pkg

cd -
umount /mnt

# now that the btrfs subvolume have been created, it's time to mount them
mkdir /mnt/home
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home

# if using a new drive, format the EFI partition
# mkfs.fat -F32 /dev/nvme0n1p1
# mkdir /mnt/boot
# mount /dev/nvme0n1p1 /mnt/boot

# Install the base packages
pacstrap -K /mnt base linux linux-firmware

# Generate the filesystem table
genfstab -U -p /mnt >> /mnt/etc/fstab
# check it
cat /mnt/etc/fstab

# Change into the new system root
arch-chroot /mnt


ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
pacman -Suy neovim
nvim /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
echo "t480arch" >> /etc/hostname
hostname
host
passwd
useradd -m -g users -G wheel bob
passwd bob
mkdir -m 755 /etc/sudoers.d
echo "bob ALL=(ALL) ALL" >> /etc/sudoers.d/bob
chmod 0440 /etc/sudoers.d/bob
pacman -S sudo
pacman -S reflector
sudo reflector --country Canada --protocol http,https --sort rate --save /etc/pacman.d/mirrorlist
pacman -Syu base-devel linux linux-headers linux-firmware btrfs-progs grub efibootmgr mtools networkmanager openssh git acpid grub-btrfs
pacman -S man-db man-pages bluez bluez-utils pipewire pipewire-pulse pipewire-jack sof-firmware ttf-firacode-nerd alacritty firefox
nvim /etc/mkinitcpio.conf
mount -n -o remount,rw /boot
# at this point I realized that the Windows created boot partition is only 100MB.  The partition was used at over 90% not leaving enough space for
# the mkinitcpio to perform its job.
# I deleted the fallback images as well as all the extra languages installed by MS
# rm /boot/EFI/Microsoft/Boot/xx-XX
rm /boot/initramfs-linux-fallback.img
mkinitcpio -p linux
pacman -S intel-ucode
nvim /etc/mkinitcpio.conf
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
nvim /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sshd
systemctl enable reflector
systemctl enable reflector.timer
systemctl enable acpid

# reboot - after which we should have a minimally installed Arch Linux working system.
