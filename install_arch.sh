# Example
# Install ARCH on the nvme disk while keeping the existing Windows partitions intact
# Target partition for Arch is nvme0n1p5
#
cryptsetup luksOpen /dev/nvme0n1p5 main
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@ /dev/mapper/main /mnt
mount -o noatime,ssd,compress=zstd,space_cache=v2,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt
