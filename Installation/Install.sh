#!/bin/bash
set -euo pipefail

[[ -f AsciiArt/Greeting.txt ]] && cat AsciiArt/Greeting.txt || echo -e "\n\nWelcome\n\n"

echo "These are the available disks:"
echo "******************************"
lsblk -d -o NAME,SIZE,TYPE | grep 'disk'
echo "******************************"
read -r -p "Enter the correct disk (e.g. sda or nvme0n1): " userInput
echo "******************************"

read -r -p "Please enter the host name: " hostname
echo ""
read -s -r -p "Enter the root password: " rootPwd
echo -e "\n"
read -r -p "Enter the name of the user: " username
read -s -r -p "Enter the password for $username: " userPwd
echo -e "\n"
read -r -p "Enter your timezone (e.g. Europe/Vienna): " timezone
echo ""

disk="/dev/$userInput"
efi_size="550MiB"
swap_size="2GiB"

if [[ "$disk" == *nvme* ]]; then
    EFI_PART="${disk}p1"
    ROOT_PART="${disk}p2"
    SWAP_PART="${disk}p3"
else
    EFI_PART="${disk}1"
    ROOT_PART="${disk}2"
    SWAP_PART="${disk}3"
fi

echo "!!! The next step will erase all data on $disk !!!"
read -r -p "Type 'YES' to continue: " confirm
[[ "$confirm" == "YES" ]] || { echo "Aborted."; exit 1; }

if [ -d /sys/firmware/efi/efivars ]; then
    root_size="100%"

    parted --script "$disk" mklabel gpt
    parted --script "$disk" mkpart ESP fat32 1MiB "$efi_size"
    parted --script "$disk" set 1 esp on
    parted --script "$disk" mkpart primary ext4 "$efi_size" "$root_size"

    parted "$disk" print

    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"

    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi

else
    parted --script "$disk" mklabel msdos
    parted --script "$disk" mkpart primary ext4 1MiB 5GiB
    parted --script "$disk" set 1 boot on
    parted --script "$disk" mkpart primary linux-swap 5GiB 100%

    parted "$disk" print

    if [[ "$disk" == *nvme* ]]; then
        ROOT_PART="${disk}p1"
        SWAP_PART="${disk}p2"
    else
        ROOT_PART="${disk}1"
        SWAP_PART="${disk}2"
    fi

    mkfs.ext4 -F "$ROOT_PART"
    mkswap "$SWAP_PART"
    swapon "$SWAP_PART"

    mount "$ROOT_PART" /mnt
fi

pacstrap /mnt base linux linux-firmware vim networkmanager nano sudo

genfstab -U /mnt >> /mnt/etc/fstab

[[ -f hyprland.conf ]] && cp -f hyprland.conf /mnt/root/hyprland.conf || true

export hostname username userPwd rootPwd disk timezone EFI_PART ROOT_PART SWAP_PART

arch-chroot /mnt /bin/bash -e <<EOFCHROOT
set -euo pipefail

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "$hostname" > /etc/hostname
echo "127.0.1.1   $hostname.localdomain $hostname" > /etc/hosts

echo "root:$rootPwd" | chpasswd

useradd -m -G wheel -s /bin/bash "$username"
echo "$username:$userPwd" | chpasswd

echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

pacman -Syu --noconfirm
pacman -S --noconfirm mesa wayland vulkan-radeon seatd hyprland xdg-desktop-portal-hyprland sddm waybar kitty fastfetch wofi swaybg swaylock swayidle pipewire pipewire-pulse

if [ -d /sys/firmware/efi/efivars ]; then
    pacman -S --noconfirm grub efibootmgr
    mkdir -p /boot/efi
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "$disk"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

if [ -f /root/hyprland.conf ]; then
    mkdir -p /home/$username/.config/hypr
    mv /root/hyprland.conf /home/$username/.config/hypr/hyprland.conf
    chown -R $username:$username /home/$username/.config
fi

systemctl enable seatd.service
systemctl enable NetworkManager
systemctl enable sddm.service

EOFCHROOT

umount -R /mnt || true
swapoff --all || true

echo "Installation of base system finished!"
echo "The computer will now shutdown."
sleep 3
shutdown now

