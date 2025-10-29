#!/bin/bash

set -euo pipefail

echo ""
echo ""

cat AsciiArt/Greeting.txt

echo ""
echo ""

echo "These are the available disks:"
echo ""

#===========choosing disk===============
echo "******************************"
lsblk -d -o NAME,SIZE,TYPE | grep 'disk'

echo ""
read -p "Enter the correct disk: " userInput
echo ""
echo "******************************"

echo ""
echo "******************************"
#======setting-hostname===========
read -p "Please enter the host name: " hostname

echo $hostname > /etc/hostname

#====setting-root-password========
echo ""
read -p "Enter the root password: " rootPwd
echo "******************************"
echo ""

echo "******************************"
#===== creating user===========
read -p "Enter the name of the user: " username
echo ""
read -p "Enter the password: " userPwd
echo "******************************"

disk="/dev/$userInput"
efi_size="550MiB"
swap_size="2GiB"


SWAP_PART="${disk}2"
echo ""

echo "******************************"
#========warning=about=data=loss========
echo "!!! The next step will erase all data on $disk !!!"
read -rp "Type 'YES' to continue: " confirm
echo "******************************"
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }





if [ -d /sys/firmware/efi/efivars ]; then # Test if file exists
   
    echo ""
    echo "File exists, so we are in UEFI"

    #configs for formating
    root_size="100%"

    echo ""
    # === CREATE PARTITIONS ===
    echo ">>> Wiping existing partition table..."
    parted --script "$disk" mklabel gpt

    echo ""
    echo ">>> Creating EFI system partition..."
    parted --script "$disk" mkpart ESP fat32 1MiB "$efi_size"
    parted --script "$disk" set 1 esp on

    echo ""
    echo ">>> Creating root partition..."
    parted --script "$disk" mkpart primary ext4 "$efi_size" "$root_size"

    echo ""
    # === SHOW RESULT ===
    parted "$disk" print
    # ===formatting-partitions===
    if [[ "$disk" == *"nvme"* ]]; then # this creates the variables based on if its an nvme or not.
        EFI_PART="${disk}p1"
        ROOT_PART="${disk}p2"
    else
        EFI_PART="${disk}1"
        ROOT_PART="${disk}2"
    fi

    echo ""
    echo ">>> Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"

    #=====mounting-partitions=====
    mount $ROOT_PART /mnt
    mkdir /mnt/boot
    mount $EFI_PART /mnt/boot

else
    echo ""
    echo "File doesn't exist, so we are in Legacy BIOS"

    echo ""

    echo ""
    #=========create partitions=============
    echo ">>> Creating new MBR partition table..."
    parted --script "$disk" mklabel msdos

    echo ""
    echo ">>> Creating root partition..."
    parted --script "$disk" mkpart primary ext4 1MiB 5GiB
    parted --script "$disk" set 1 boot on

    echo ""
    echo ">>> Creating swap partition..."
    parted --script "$disk" mkpart primary linux-swap 5GiB 100%

    # === SHOW RESULT ===
    parted "$disk" print

    
    #===formatting-and-mounting=======
    mkfs.ext4 -F "$ROOT_PART"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"

    mount "$ROOT_PART" /mnt
fi

#====installing-base-system======
pacstrap /mnt base linux linux-firmware vim networkmanager nano sudo 


#====generating-fstab======
genfstab -U /mnt >> /mnt/etc/fstab

#====configure system inside chroot======
echo ">>> Configuring system inside chroot..."

# Set timezone, locale, hostname, users, and bootloader
arch-chroot /mnt /bin/bash -e <<EOFCHROOT

#=== TIMEZONE & CLOCK ===
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc

#=== LOCALES ===
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

#=== HOSTNAME ===
echo "$hostname" > /etc/hostname
echo "127.0.1.1   $hostname.localdomain $hostname" > /etc/hosts

#=== ROOT PASSWORD ===
echo "root:$rootPwd" | chpasswd

#=== USER SETUP ===
useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$userPwd" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

#====installing additional packages======
sudo pacman -S --noconfirm mesa wayland vulkan-radeon seatd
sudo pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland
sudo pacman -S --noconfirm sddm waybar kitty fastfetch
sudo pacman -S --noconfirm wofi swaybg swaylock swayidle pipewire pipewire-pulse


#=== BOOTLOADER INSTALLATION ===
if [ -d /sys/firmware/efi/efivars ]; then
    echo ">>> Installing bootloader for UEFI..."
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    echo ">>> Installing bootloader for BIOS..."
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$disk"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

#=====copy-configs=====
mkdir -p /mnt/home/$username/.config/hypr
cp -f /root/GonOs/ConfigFiles/hypr/hyprland.conf /mnt/home/$username/.config/hypr/hyprland.conf
chown -R $username:$username /mnt/home/$username/.config

#====enable-services
systemctl enable seatd.service

systemctl enable NetworkManager

systemctl enable sddm.service



EOFCHROOT

echo ""
echo ""
echo ""
echo ""
echo ""


echo "Installation of base system finished!"
echo ""
echo "The computer will now shutdown."

sleep 3

umount -R /mnt

shutdown now

# echo ""

# #======ask-if-shutdown-or-reboot=========
# read -p "Do you want to shutdown or reboot: " rebootOrShutdown

# if $rebootOrShutdown == "reboot"; then 
#     reboot
# fi

# if $rebootOrShutdown == "shutdown"; then
#     shutdown now
# fi

