t1
# Stuff to do after the first boot into the installed system
# run as sudo bash post_reboot.sh

# Install zram
echo -ne "################################################\n"
echo -ne "############## Install ZRAM  ###################\n"
echo -ne "################################################\n"
sudo pacman -Syu zram-generator

# create file at /etc/systemd/zram-generator.conf
sudo cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

# Install yay
echo -ne "################################################\n"
echo -ne "############### Install yay ####################\n"
echo -ne "################################################\n"
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo pacman -S base-devel
makepkg -si

# Install Timeshift
echo -ne "################################################\n"
echo -ne "############ Install timeshift #################\n"
echo -ne "################################################\n"
yay -S --noconfirm --needed timeshift timeshift-autosnap
sudo timeshift --list-devices

# Create a first snapshot
echo -ne "Create first snapshot"
sudo timeshift --create --comments "[$(date +%Y-%m-%d)] Initial Snapshot" --tags D
# change ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots for ExecStart=/usr/bin/grub-btrfsd --syslog -t
# sudo systemctl edit --full grub-btrfsd
sudo sed -i 's/ExecStart=\/usr\/bin\/grub-btrfsd --syslog \/.snapshots/ExecStart=\/usr\/bin\/grub-btrfsd --syslog -t/' /etc/systemd/system/grub-btrfsd.service

# regenerate the grub config so that the snapshot are visible on boot
echo "Make snapshots visible on next boot"
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Download Omarchy
echo -ne "################################################\n"
echo -ne "############## Download Omarchy ################\n"
echo -ne "################################################\n"
# sudo pacman -S wget
#wget -qO- https://omarchy.org/install
sudo pacman --noconfirm --needed -S git
git clone "https://github.com/basecamp/omarchy.git" ~/.local/share/omarchy >/dev/null

# remove apps that Omarchy installed that we don't want
sudo pacman -Rcns 1password-beta 1password-cli

echo -ne "################################################\n"
echo -ne "########### Install prefered apps ##############\n"
echo -ne "################################################\n"
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
 sudo ./install.sh -b -t tela
