#!/bin/bash

# Define function to read the yaml variables into the shell script
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s'\(.*\)'$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}


# Load the configuration file
eval $(parse_yaml config.yaml)

echo "Setting keyboard layout..."
loadkeys $keyboard_layout

echo "Connecting to the internet..."
dhcpcd

# Update the system clock
echo "Updating system clock..."
timedatectl set-ntp true

# Partition the disk
echo "Partitioning the disk..."
echo "n
p
1

+$boot_partition_size
t
1
$boot_partition_type
n
p
2

+$root_partition_size
n
p
3

+$swap_partition_size
t
3
82
w" | fdisk $disk

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F32 /dev/${disk}1
mkfs.ext4 /dev/${disk}2
mkswap /dev/${disk}3
swapon /dev/${disk}3

# Mount the partitions
echo "Mounting partitions..."
mount /dev/${disk}2 /mnt
mkdir -p /mnt/boot/efi
mount /dev/${disk}1 /mnt/boot/efi

echo "Installing base system..."
pacstrap /mnt base linux $kernel

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Enter the chroot environment. The real game starts here :)
echo "Changing root..."
arch-chroot /mnt /bin/bash

echo "Setting hostname..."
echo $hostname > /etc/hostname

echo "Setting locale..."
echo LANG=$locale > /etc/locale.conf
echo $locale $charset >> /etc/locale.gen
locale-gen
export LANG=$locale

echo "Setting time zone..."
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

echo "Installing the bootloader..."
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/mnt/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg


echo "Installing network software..."
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager.service


echo "Installing the window manager/desktop environment"
case $desktop_environment in
    "gnome")
        pacman -S --noconfirm gnome
        ;;
    "kde")
        pacman -S --noconfirm plasma-meta kde-applications
        ;;
    "xfce")
        pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
        systemctl enable lightdm.service
        ;;
    *)
        echo "Unknown desktop environment specified in config.yaml"
        ;;
esac

echo "Installing proprietary drivers..."
case $proprietary_drivers in
    "nvidia")
        pacman -S --noconfirm nvidia nvidia-utils
        ;;
    "amd")
        pacman -S --noconfirm xf86-video-amdgpu
        ;;
    *)
        echo "Support for more proprietary drivers arriving soon"
        ;;
esac


echo "Installing additional packages..."
pacman -S --noconfirm ${additional_packages[@]}

echo "Setting root password..."
echo "root:$root_password" | chpasswd

echo "Creating user accounts..."
for i in "${!users[@]}"
do
    user=${users[$i]}
    password=${passwords[$i]}
    groups=${groups[$i]}
    useradd -m -G $groups $user
    echo "$user:$password" | chpasswd
done

echo "Installation complete!"
reboot