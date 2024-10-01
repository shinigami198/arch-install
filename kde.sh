#!/bin/bash

print_color "32" "Installing Plasma..."
if ! arch-chroot /mnt pacman -S --noconfirm plasma-desktop sddm-kcm plymouth-kcm kcm-fcitx flatpak-kcm; then
    print_color "31" "Failed to install Plasma."
    exit 1
fi

# Install Flatpak and KDE Control Modules
print_color "32" "Installing Flatpak and additional KDE Control Modules..."
if ! arch-chroot /mnt pacman -S --noconfirm alacritty fastfetch dolphin bluez flatpak kde-gtk-config breeze-gtk kdeconnect kdeplasma-addons bluedevil kscreen plasma-firewall plasma-browser-integration plasma-nm plasma-pa plasma-sdk plasma-systemmonitor power-profiles-daemon; then
    print_color "31" "Failed to install Flatpak and KDE Control Modules."
    exit 1
fi
arch-chroot /mnt flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
