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
 sudo ./install.sh -b -t tela
