#!/bin/bash

print_color "32" "Installing GRUB for EFI..."
if ! mountpoint -q /mnt/boot/efi; then
    mkdir -p /mnt/boot/efi
    mount $EFI_PARTITION /mnt/boot/efi
fi
arch-chroot /mnt pacman -S --noconfirm efibootmgr
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="$LABEL"

if [ $? -eq 0 ]; then
    print_color "32" "GRUB installed successfully."
    arch-chroot /mnt pacman -S --noconfirm --needed os-prober
    echo "Enabling os-prober in GRUB configuration..."
    arch-chroot /mnt sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
    echo "Generating GRUB configuration..."
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    if [ $? -eq 0 ]; then
        print_color "32" "GRUB configuration generated successfully."
    else
        print_color "31" "Failed to generate GRUB configuration."
        exit 1
    fi
else
    print_color "31" "Failed to install GRUB."
    exit 1
fi

# Update package database
arch-chroot /mnt pacman -Syy --noconfirm --needed

# Backup and modify mkinitcpio.conf
print_color "33" "Backing up $MKINITCPIO_CONF to $MKINITCPIO_CONF.bak"
if ! cp "$MKINITCPIO_CONF" "$MKINITCPIO_CONF.bak"; then
    print_color "31" "Failed to back up mkinitcpio.conf."
    exit 1
fi

if ! grep -q "btrfs" "$MKINITCPIO_CONF"; then
    print_color "33" "Adding btrfs module to mkinitcpio.conf"
    arch-chroot /mnt sed -i 's/^MODULES=(/MODULES=(btrfs /' "$MKINITCPIO_CONF"
fi
arch-chroot /mnt sed -i 's/ fsck//' "$MKINITCPIO_CONF"

print_color "32" "Modifying GRUB configuration to enable Plymouth..."
if ! arch-chroot /mnt pacman -S --noconfirm plymouth; then
    print_color "31" "Failed to install Plymouth."
    exit 1
fi
arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& quiet splash/' /etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
