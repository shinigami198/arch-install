#!/bin/bash
set -e

# Configuration
COUNTRY="Singapore"
LOG_FILE="/var/log/arch_install.log"
EFI_PARTITION="/dev/nvme0n1p1"
BOOT_DISK="/dev/nvme0n1"
LABEL="Legion -- X"
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
GRUB_CONF="/etc/default/grub"
GRUB_BACKUP_CONF="/etc/default/grub.bak"

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "\e[${color}m${message}\e[0m"
}

# Function to handle errors
error_handler() {
    print_color "31" "Error occurred on line $1"
    exit 1
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# Set up logging
exec > >(tee -i $LOG_FILE)
exec 2>&1

print_color "36" "Starting Arch Linux installation..."

# Gather user inputs at the beginning
read -p "Enter the hostname for this machine: " HOSTNAME

read -p "Do you want to create new partitions? (y/n): " create_partitions
if [[ $create_partitions =~ ^[Yy]$ ]]; then
    read -p "Enter size for EFI partition (e.g., 1G) [default: 1G]: " efi_size
    efi_size=${efi_size:-1G}
    read -p "Enter size for root partition (e.g., 250G): " root_size
    read -p "Enter size for swap partition (e.g., 4G): " swap_size
fi

read -p "Do you have an NVIDIA GPU? (y/n): " has_nvidia
read -p "Do you want to install SDDM (Simple Desktop Display Manager)? (y/n): " install_sddm
if [[ $install_sddm =~ ^[Yy]$ ]]; then
    read -p "Do you want to install Plasma (KDE Desktop Environment)? (y/n): " install_plasma
fi

choose_kernel() {
    while true; do
        echo "Please select a Linux kernel to install:"
        echo "1) linux"
        echo "2) linux-lts"
        echo "3) linux-zen"
        echo -n "Enter your choice [1-3]: "
        read choice
        case $choice in
            1) KERNEL="linux"; break;;
            2) KERNEL="linux-lts"; break;;
            3) KERNEL="linux-zen"; break;;
            *) echo "Invalid choice. Please choose again.";;
        esac
    done
}

# Call the function to choose a kernel
choose_kernel

KERNEL_HEADERS="${KERNEL}-headers"

# Set password for root user
# Ask for root password
while true; do
    read -s -p "Enter password for root user: " ROOT_PASSWORD
    echo
    read -s -p "Confirm password for root user: " ROOT_PASSWORD_CONFIRM
    echo
    if [[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD_CONFIRM" ]]; then
        break
    else
        print_color "31" "Passwords do not match. Please try again."
    fi
done

# Create a new user
# Ask for username and passwords at the beginning
echo "Setting up new user..."
while true; do
    read -p "Enter the username for the new user: " NEW_USER
    if [[ -z "$NEW_USER" ]]; then
        print_color "31" "Username cannot be empty. Please try again."
    else
        break
    fi
done

# Ask for user password
while true; do
    read -s -p "Enter password for $NEW_USER: " USER_PASSWORD
    echo
    read -s -p "Confirm password for $NEW_USER: " USER_PASSWORD_CONFIRM
    echo
    if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" ]]; then
        break
    else
        print_color "31" "Passwords do not match. Please try again."
    fi
done

# Proceed with the rest of the script using the gathered inputs
loadkeys us
timedatectl set-ntp true
if [ $? -eq 0 ]; then
    print_color "32" "NTP synchronization enabled successfully."
else
    print_color "31" "Failed to enable NTP synchronization."
    exit 1
fi

configure_pacman() {
    print_color "33" "Configuring pacman..."
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
    print_color "33" "Updating pacman database..."
    if ! pacman -Syy; then
        print_color "31" "Failed to update pacman database."
        exit 1
    fi
}

# Call the function to configure pacman
configure_pacman

pacman -S --noconfirm rsync

cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

print_color "33" "Updating mirror list..."
reflector -a 6 -c Singapore -a 6 -l 20 --sort rate --save /etc/pacman.d/mirrorlist

print_color "33" "Installing necessary packages..."
if ! pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc; then
    print_color "31" "Failed to install necessary packages."
    exit 1
fi

umount -R /mnt 2>/dev/null || true

if [[ $create_partitions =~ ^[Yy]$ ]]; then
    # Use gdisk to create the partitions
    print_color "33" "Creating partitions..."
    print_color "36" "Please enter the sizes for each partition."

    # Validate user inputs
    if ! [[ $efi_size =~ ^[0-9]+[GgMm]$ ]] || ! [[ $root_size =~ ^[0-9]+[GgMm]$ ]] || ! [[ $swap_size =~ ^[0-9]+[GgMm]$ ]]; then
        print_color "31" "Invalid size format. Please use the format (e.g., 1G, 250G)."
        exit 1
    fi

    gdisk /dev/nvme0n1 << EOF
o
y
n
1

+${efi_size}
ef00
n
2

+${root_size}
8300
n
3

+${swap_size}
8200
w
y
EOF
else
    print_color "33" "Skipping partition creation. Using existing partitions."
    # You may want to add a prompt here to confirm the existing partition layout
    read -p "Press Enter to continue with the existing partition layout..."
fi

# Format the partitions (moved outside the if statement)
print_color "33" "Formatting partitions..."
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs -f /dev/nvme0n1p2
mkswap /dev/nvme0n1p3

# Mount the partitions and create subvolumes
print_color "33" "Creating and mounting BTRFS subvolumes..."
mount /dev/nvme0n1p2 /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@snapshots

umount -R /mnt

# Updated mount options for better SSD performance
mount -o noatime,compress-force=zstd:3,ssd,space_cache=v2,subvol=@ /dev/nvme0n1p2 /mnt
mount --mkdir -o noatime,compress-force=zstd:3,ssd,space_cache=v2,subvol=@home /dev/nvme0n1p2 /mnt/home
mount --mkdir -o noatime,compress-force=zstd:3,ssd,space_cache=v2,subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount --mkdir -o noatime,compress-force=zstd:3,ssd,space_cache=v2,subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots

swapon /dev/nvme0n1p3

mount --mkdir /dev/nvme0n1p1 /mnt/boot/efi

print_color "33" "Installing base system..."
if ! pacstrap -K -P /mnt base base-devel $KERNEL $KERNEL_HEADERS linux-firmware sof-firmware networkmanager grub efibootmgr os-prober micro git wget bluez pulseaudio alsa-utils pulseaudio-bluetooth; then
    print_color "31" "Failed to install base system."
    exit 1
fi

print_color "33" "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

print_color "32" "Base system installation complete!"
print_color "33" "Please review /mnt/etc/fstab before rebooting."
print_color "36" "You can now chroot into the new system with: arch-chroot /mnt"

# Set timezone and clock
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
arch-chroot /mnt hwclock --systohc --utc

# Generate locale
arch-chroot /mnt sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo KEYMAP=us > /mnt/etc/vconsole.conf
echo $HOSTNAME > /mnt/etc/hostname

# Set the root password
echo "Setting password for root user..."
echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd

# Create the new user
arch-chroot /mnt useradd -m -G wheel,storage,power -s /bin/bash "$NEW_USER"

# Set the user password
echo "$NEW_USER:$USER_PASSWORD" | arch-chroot /mnt chpasswd

print_color "32" "User $NEW_USER has been created and added to the wheel group."

print_color "32" "Configuring sudoers..."
# Configure sudoers
arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
arch-chroot /mnt sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Call the separate scripts if needed
if [[ $has_nvidia =~ ^[Yy]$ ]]; then
    ./nvidia.sh
fi

if [[ $install_sddm =~ ^[Yy]$ ]]; then
    ./SDDM.sh
    if [[ $install_plasma =~ ^[Yy]$ ]]; then
        ./kde.sh
    fi
fi

./grub.sh

# Ensure all changes are written to disk
sync