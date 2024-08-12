#!/bin/bash

# Function to prompt the user for boot mode (BIOS or UEFI)
function prompt_boot_mode() {
    while true; do
        echo "Select Boot Mode:"
        echo "1) BIOS"
        echo "2) UEFI"
        read -p "Enter your choice [1-2]: " boot_mode_choice

        case $boot_mode_choice in
            1)
                boot_mode="BIOS"
                break
                ;;
            2)
                boot_mode="UEFI"
                break
                ;;
            *)
                echo "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
}

while true; do
    echo "Select VM Boot Source:"
    echo "1) Boot from connected device"
    echo "2) Boot from file (.vhd, .img, .iso)"
    echo "3) ISO & Drive (Virtual disk or Physical Device)"
    read -p "Enter your choice [1-3]: " boot_source_choice

    case $boot_source_choice in
        1)
            # Get a list of all drives on the system
            drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
            echo "Available Drives:"
            echo "$drives"
            read -p "Enter the drive you want to boot from: " selected_drive

            prompt_boot_mode
            ;;

        2)
            read -p "Enter the path to the virtual disk file (.vhd, .img, .iso): " selected_drive
            if [ ! -f "$selected_drive" ]; then
                echo "File does not exist. Please try again."
                continue
            fi

            prompt_boot_mode
            ;;

        3)
            read -p "Enter the path to the ISO file: " iso_path
            if [ ! -f "$iso_path" ]; then
                echo "ISO file does not exist. Please try again."
                continue
            fi

            echo "1) Select Virtual Disk"
            echo "2) Select Physical Device"
            read -p "Enter your choice [1-2]: " drive_choice

            if [ "$drive_choice" == "1" ]; then
                read -p "Enter the path to the virtual disk file (.img, .vhd, .vhdx): " selected_drive
                if [ ! -f "$selected_drive" ]; then
                    echo "File does not exist. Please try again."
                    continue
                fi
            elif [ "$drive_choice" == "2" ]; then
                echo "Available Drives:"
                echo "$drives"
                read -p "Enter the drive you want to use: " selected_drive
            else
                echo "Invalid choice."
                continue
            fi

            prompt_boot_mode
            ;;

        *)
            echo "Invalid choice. Please select a valid option."
            continue
            ;;
    esac

    while true; do
        read -p "Enter the amount of RAM for the VM (in MB): " ram_size
        if [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo "Please enter a valid positive integer."
        fi
    done

    echo -e "\nSelected Drive: $selected_drive"
    echo "Boot Mode: $boot_mode"
    echo "RAM Size: $ram_size MB"

    # Start QEMU VM with the specified parameters
    if [ "$boot_mode" == "BIOS" ]; then
        qemu-system-x86_64 -enable-kvm -cpu host -m "${ram_size}M" -drive file="$selected_drive",format=raw -cdrom "$iso_path" -boot order=dc
    elif [ "$boot_mode" == "UEFI" ]; then
        qemu-system-x86_64 -enable-kvm -cpu host -m "${ram_size}M" -drive file="$selected_drive",format=raw -cdrom "$iso_path" -bios /usr/share/qemu/OVMF.fd -boot order=dc
    else
        exit 1
    fi

    read -p "QuickBoot another VM? (y/n): " quickboot_choice
    if [[ "$quickboot_choice" != [yY] ]]; then
        break
    fi
done
