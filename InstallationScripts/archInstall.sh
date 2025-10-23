#!/bin/bash

set -euo pipefail

cat InstallerAsciiArt/Greeting.txt

echo ""
echo ""

#===========choosing disk===============
echo "******************************"
lsblk -d -o NAME,SIZE,TYPE | grep 'disk'
echo "******************************"

read -p "Enter the correct disk: " userInput





if test -f /sys/firmware/efi/efivars; then # Test if file exists
   
    echo "File exists, so we are in UEFI"

    #configs for formating
    DISK=/dev/$userInput
    EFI_SIZE="550MiB"
    ROOT_SIZE="100%"

    #========warning=about=data=loss========
    echo ">>> This will destroy all data on $DISK!"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

    # === CREATE PARTITIONS ===
    echo ">>> Wiping existing partition table..."
    parted --script "$DISK" mklabel gpt

    echo ">>> Creating EFI system partition..."
    parted --script "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
    parted --script "$DISK" set 1 esp on

    echo ">>> Creating root partition..."
    parted --script "$DISK" mkpart primary ext4 "$EFI_SIZE" "$ROOT_SIZE"

    # === SHOW RESULT ===
    parted "$DISK" print

    # ===formatting-partitions===
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"

    echo ">>> Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"

    #=====mounting-partitions=====
    mount $ROOT_PART /mnt
    mkdir /mnt/boot
    mount $EFI_PART /mnt/boot

else
    echo "File doesn't exist, so we are in Legacy BIOS"

    #configs for formating
    DISK = /dev/$userInput
    SWAP_SIZE = "2GiB"
    ROOT_SIZE = "100%"

    #========warning=about=data=loss========
    echo "The next step will erase all data on $DISK"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

    #=========create partitions=============
    echo ">>> Creating new MBR partition table..."
    parted --script "$DISK" mklabel msdos

    echo ">>> Creating root partition..."
    parted --script "$DISK" mkpart primary ext4 1MiB "-${SWAP_SIZE}"
    parted --script "$DISK" set 1 boot on

    echo ">>> Creating swap partition..."
    parted --script "$DISK" mkpart primary linux-swap "-${SWAP_SIZE}" 100%

    # === SHOW RESULT ===
    parted "$DISK" print

    
    #===formatting=======
    mkfs.ext4 $DISK
    echo "formatted $DISK"
    
    #===mounting========
    mount $DISK /mnt
    echo "mounted $DISK"
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

locale-genecho "LANG=en_US.UTF-8" > /etc/locale.conf

#======setting-hostname===========
read -p "Please enter the host name: " hostname

echo $hostname > /etc/hostname

echo "127.0.1.1   arch.localdomain $hostname" > /etc/hosts

#====setting-root-password========
read -p "Enter the root password: " rootPwd
echo "root:$rootPwd" | chpasswd

#===== creating user===========
read -p "Enter the name of the user: " username
echo ""
read -p "Enter the password: " userPwd

useradd -m -G wheel -s /bin/bash gon && echo "$username:$userPwd" | chpasswd

#====installing-bootloader========
if test -f /sys/firmware/efi/efivars; then 
    echo "Installing bootloader for UEFI"

    pacman -S grub efibootmgr-
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

else
    echo "Installing bootloader for BIOS"

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
