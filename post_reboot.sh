# Install zram
sudo pacman -Syu zram-generator

# create file at /etc/systemd/zram-generator.conf
cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# Install Timeshift
yay -S timeshift timeshift-autosnap
sudo timeshift --list-devices

# Create a first snapshot
sudo timeshift --create --comments "[$(date +%Y-%m-%d)] Initial Snapshot" --tags D
# change ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots for ExecStart=/usr/bin/grub-btrfsd --syslog -t
# sudo systemctl edit --full grub-btrfsd
sed -i 's/ExecStart=\/usr\/bin\/grub-btrfsd --syslog \/.snapshots/ExecStart=\/usr\/bin\/grub-btrfsd --syslog -t/' /etc/systemd/system/grub-btrfsd.service

# regenerate the grub config so that the snapshot are visible on boot
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Install Omarchy
sudo pacman -S wget
wget -qO- https://omarchy.org/install | bash

# remove apps that Omarchy installed that we don't want
sudo pacman -Rcns 1password-beta 1password-cli

yay -S --noconfirm --needed \
	pkgfile \
	pika-backup \
	bind \
	uv \
	bind \
	os-prober \
	gvfs-smb \
	ntfs-3g \
	xorg-xhost \  # this is needed to be able to open timeshift GUI
 	timeshift timeshift-autosnap \
	bitwarden bitwarden-cli

 # Install new grub theme
 git clone https://github.com/vinceliuice/grub2-themes.git
 cd grub2-themes
 # this theme installer will update grub and will also intall the grub snapshot view as per above
 s1Kermit1
 udo ./install.sh -b -t tela
