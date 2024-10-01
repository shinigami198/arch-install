#!/bin/bash

print_color "32" "Installing SDDM..."
if ! arch-chroot /mnt pacman -S --noconfirm sddm; then
    print_color "31" "Failed to install SDDM."
    exit 1
fi
print_color "32" "Enabling SDDM service..."
arch-chroot /mnt systemctl enable sddm
