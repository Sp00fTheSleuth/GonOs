# 

#!/bin/bash
set -euo pipefail

cat InstallerAsciiArt/Greeting.txt || true
echo -e "\n\n"

lsblk -d -o NAME,SIZE,TYPE | grep disk
read -p "Enter disk (e.g., sda): " userInput
disk="/dev/$userInput"

efi_size="550MiB"
swap_size="2GiB"

if [ -d /sys/firmware/efi/efivars ]; then
    echo "UEFI detected"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || exit 1

    parted --script "$disk" mklabel gpt
    parted --script "$disk" mkpart ESP fat32 1MiB "$efi_size"
    parted --script "$disk" set 1 esp on
    parted --script "$disk" mkpart primary ext4 "$efi_size" 100%

    EFI_PART="${disk}1"
    ROOT_PART="${disk}2"

    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"

    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
else
    echo "Legacy BIOS detected"
    read -rp "Type 'YES' to continue: " confirm
    [[ "$confirm" == "YES" ]] || exit 1

    echo ">>> Creating new MBR partition table..."
    parted --script "$disk" mklabel msdos

    echo ">>> Creating root partition..."
    parted --script "$disk" mkpart primary ext4 1MiB -${swap_size}
    parted --script "$disk" set 1 boot on

    echo ">>> Creating swap partition..."
    parted --script "$disk" mkpart primary linux-swap -${swap_size} 100%

    ROOT_PART="${disk}1"
    SWAP_PART="${disk}2"

    mkfs.ext4 -F "$ROOT_PART"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"

    mount "$ROOT_PART" /mnt

fi

pacstrap /mnt base linux linux-firmware vim networkmanager
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail

ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

read -p "Hostname: " hostname
echo "\$hostname" > /etc/hostname
echo "127.0.1.1   \$hostname.localdomain \$hostname" >> /etc/hosts

read -p "Root password: " rootPwd
echo "root:\$rootPwd" | chpasswd

read -p "Username: " username
read -p "User password: " userPwd
useradd -m -G wheel -s /bin/bash "\$username"
echo "\$username:\$userPwd" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

if [ -d /sys/firmware/efi/efivars ]; then
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
pacman -Syu --noconfirm nano fastfetch

EOF

umount -R /mnt
reboot
