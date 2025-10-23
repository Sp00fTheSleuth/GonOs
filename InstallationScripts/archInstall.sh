#!/bin/bash

set -euo pipefail

echo ""
echo ""

cat InstallerAsciiArt/Greeting.txt

echo ""
echo ""

echo "These are the available disks:"
echo ""

#===========choosing disk===============
echo "******************************"
lsblk -d -o NAME,SIZE,TYPE | grep 'disk'
echo "******************************"

echo ""

read -p "Enter the correct disk: " userInput

disk="/dev/$userInput"
efi_size="550MiB"
swap_size="2GiB"

ROOT_PART="${disk}1"
SWAP_PART="${disk}2"



if [ -d /sys/firmware/efi/efivars ]; then # Test if file exists
   
    echo ""
    echo "File exists, so we are in UEFI"

    #configs for formating
    root_size="100%"

    echo ""
    echo ""

    #========warning=about=data=loss========
    echo ">>> This will destroy all data on $disk!"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

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
    EFI_PART="${disk}1"
    ROOT_PART="${disk}2"

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
    #========warning=about=data=loss========
    echo "The next step will erase all data on $disk"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

    echo ""
    #=========create partitions=============
    echo ">>> Creating new MBR partition table..."
    parted --script "$disk" mklabel msdos

    echo ""
    echo ">>> Creating root partition..."
    parted --script "$disk" mkpart primary ext4 1MiB 10GiB
    parted --script "$disk" set 1 boot on

    echo ""
    echo ">>> Creating swap partition..."
    parted --script "$disk" mkpart primary linux-swap 10GiB 100%

    # === SHOW RESULT ===
    parted "$disk" print

    
    #===formatting-and-mounting=======
    mkfs.ext4 -F "$ROOT_PART"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"

    mount "$ROOT_PART" /mnt
fi

#====installing-base-system======
pacstrap /mnt base linux linux-firmware vim networkmanager

#====generating-fstab======
genfstab -U /mnt >> /mnt/etc/fstab

#====chroot into the system======
arch-chroot /mnt

#====configure locales============
ln -sf /usr/share/zoneinfo/Region/City /etc/localtim
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etch/locale.gen

locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

#======setting-hostname===========
read -p "Please enter the host name: " hostname

echo $hostname > /etc/hostname

echo "127.0.1.1   arch.localdomain $hostname" > /etc/hosts

#====setting-root-password========
echo ""
echo ""
read -p "Enter the root password: " rootPwd
echo "root:$rootPwd" | chpasswd

echo ""
echo ""
#===== creating user===========
read -p "Enter the name of the user: " username
echo ""
read -p "Enter the password: " userPwd

useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$userPwd" | chpasswd

#====installing-bootloader========
if test -f /sys/firmware/efi/efivars; then 
    echo ""
    echo "Installing bootloader for UEFI"
    echo ""

    pacman -S grub efibootmgr-
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

else
    echo ""
    echo "Installing bootloader for BIOS"
    echo ""

    pacman -S grub
    grub-install --target=i386-pc /dev/sda
    grub-mkconfig -o /boot/grub/grub.cfg
fi

#====enabling-Network-Manager==========
systemctl enable NetworkManager

#===installing-more-packages===========
sudo pacman -Syu --needed nano fastfetch

#===exit-and-reboot=====
exit
umount -R /mnt
reboot
