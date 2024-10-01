#!/bin/bash

print_color "32" "Installing NVIDIA drivers and configuring the system..."
if ! arch-chroot /mnt pacman -S --noconfirm --needed nvidia-dkms libglvnd opencl-nvidia nvidia-utils lib32-libglvnd lib32-opencl-nvidia lib32-nvidia-utils nvidia-settings; then
    print_color "31" "Failed to install NVIDIA drivers."
    exit 1
fi
NVIDIA_MODULES=("nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm")

# Modify mkinitcpio.conf to add NVIDIA modules after existing modules
print_color "33" "Adding NVIDIA modules to mkinitcpio.conf"
arch-chroot /mnt sed -i '/^MODULES=/ s/)/'"${NVIDIA_MODULES[*]}"' &/' "$MKINITCPIO_CONF"

arch-chroot /mnt sed -i 's/ kms//' "$MKINITCPIO_CONF"

print_color "33" "Regenerating initramfs after adding NVIDIA modules"
arch-chroot /mnt mkinitcpio -P

print_color "33" "Backing up $GRUB_CONF to $GRUB_BACKUP_CONF"
if ! arch-chroot /mnt cp "$GRUB_CONF" "$GRUB_BACKUP_CONF"; then
    print_color "31" "Failed to back up GRUB configuration."
    exit 1
fi

GRUB_PARAMS="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
if ! grep -q "$GRUB_PARAMS" "$GRUB_CONF"; then
    print_color "33" "Adding parameters to GRUB_CMDLINE_LINUX_DEFAULT"
    arch-chroot /mnt sed -i "s/\(^GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"/\1 $GRUB_PARAMS\"/" "$GRUB_CONF"
fi
