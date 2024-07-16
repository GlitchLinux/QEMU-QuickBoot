#!/bin/bash

# Calculate 30% wider size for the first Zenity window
original_width=520  # 30% wider than the original width
original_height=365
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")  # Adjusted to 30% wider than the original width
geometry="${smaller_width}x${smaller_height}"

while true; do
    # Option to choose boot source using Zenity
    boot_source_choice=$(zenity --list --title="Select VM Boot Source" --column="Option" --width="$original_width" --height="$smaller_height" \
        "Boot from connected device" "Boot from file (.vhd, .img, .iso)" "ISO & Drive (Virtual disk or Physical Device)")

    # Check if the user canceled the dialog
    if [ $? -ne 0 ]; then
        zenity --error --text="User canceled operation."
        exit 1
    fi

    case $boot_source_choice in
        "Boot from connected device")
            # Get a list of all drives on the system
            drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)

            # Display a numbered list of drives using Zenity and prompt the user to select one
            selected_drive=$(zenity --list --title="Select Disk" --column="Drive" --column="Size" --text "Select a disk:" --width="$bigger_width" --height="$smaller_height" $drives)

            # Check if the user canceled the dialog
            if [ $? -ne 0 ]; then
                zenity --error --text="User canceled operation."
                exit 1
            fi

            boot_mode=""

            # Prompt the user to choose the boot mode (BIOS or UEFI)
            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            # Check if the user canceled the dialog
            if [ $? -ne 0 ]; then
                zenity --error --text="User canceled operation."
                exit 1
            fi
            ;;

        "Boot from file (.vhd, .img, .iso)")
            # Prompt the user to select a virtual disk file (.vhd, .img, .iso)
            selected_drive=$(zenity --file-selection --title="Select Virtual Disk (.vhd, .img, .iso)" --width="$smaller_width" --height="$smaller_height")

            # Check if the user canceled the dialog or the selected file doesn't exist
            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                zenity --error --text="File not found or operation canceled. Please try again."
                continue
            fi

            boot_mode=""

            # Prompt the user to choose the boot mode (BIOS or UEFI)
            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            # Check if the user canceled the dialog
            if [ $? -ne 0 ]; then
                zenity --error --text="User canceled operation."
                exit 1
            fi
            ;;

        "ISO & Drive (Virtual disk or Physical Device)")
            # Prompt the user to select an ISO file for virtual DVD installer media
            iso_path=$(zenity --file-selection --title="Select .ISO file" --width="$smaller_width" --height="$smaller_height")

            # Check if the user canceled the dialog or the selected file doesn't exist
            if [ $? -ne 0 ] || [ ! -f "$iso_path" ]; then
                zenity --error --text="File not found or operation canceled. Please try again."
                continue
            fi

            # Prompt the user to choose a virtual disk file or physical device
            selected_drive=$(zenity --list --title="Select Virtual Disk or Physical Device" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                "Select Virtual Disk" "Select Physical Device")

            # Check if the user canceled the dialog
            if [ $? -ne 0 ]; then
                zenity --error --text="User canceled operation."
                exit 1
            fi

            if [ "$selected_drive" == "Select Virtual Disk" ]; then
                # Prompt the user to select a virtual disk file (.img, .vhd, .vhdx)
                selected_drive=$(zenity --file-selection --title="Select Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                # Check if the user canceled the dialog or the selected file doesn't exist
                if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                    zenity --error --text="File not found or operation canceled. Please try again."
                    continue
                fi
            elif [ "$selected_drive" == "Select Physical Device" ]; then
                # Get a list of all drives on the system
                drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)

                # Display a numbered list of drives using Zenity and prompt the user to select one
                selected_drive=$(zenity --list --title="Select Physical Device" --column="Drive" --column="Size" --text "Select a physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                # Check if the user canceled the dialog
                if [ $? -ne 0 ]; then
                    zenity --error --text="User canceled operation."
                    exit 1
                fi
            else
                zenity --error --text="Invalid choice. Please try again."
                continue
            fi

            # Prompt the user to choose the boot mode (BIOS or UEFI)
            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            # Check if the user canceled the dialog
            if [ $? -ne 0 ]; then
                zenity --error --text="User canceled operation."
                exit 1
            fi
            ;;

        *)
            zenity --error --text="Invalid choice. Please try again."
            continue
            ;;
    esac

    # Prompt the user to specify the amount of RAM for the VM using Zenity
    ram_size=$(zenity --entry --title="Enter RAM Size" --text "Enter the amount of RAM for the VM (in MB):" --width="$smaller_width" --height="$smaller_height")

    # Check if the user canceled the dialog or the entered RAM size is not a positive integer
    if [ $? -ne 0 ] || ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
        zenity --error --text="Invalid RAM size or operation canceled. Please enter a positive integer."
        continue
    fi

    # Print the selected drive, boot mode, and RAM size for debugging
    echo -e "\nSelected Drive: $selected_drive"
    echo "Boot Mode: $boot_mode"
    echo "RAM Size: $ram_size MB"

    # Start QEMU VM with the specified parameters
    if [ "$boot_mode" == "BIOS" ]; then
        qemu-system-x86_64 -enable-kvm -cpu host -m "${ram_size}M" -drive file="$selected_drive",format=raw -cdrom "$iso_path" -boot order=dc
    elif [ "$boot_mode" == "UEFI" ]; then
        qemu-system-x86_64 -enable-kvm -cpu host -m "${ram_size}M" -drive file="$selected_drive",format=raw -cdrom "$iso_path" -bios /usr/share/qemu/OVMF.fd -boot order=dc
    else
        zenity --error --text="Invalid boot mode selected."
        exit 1
    fi

    # Combine notifications and prompt in a single Zenity window
    zenity --question --title="QEMU - QuickBoot" --text="QuickBoot another VM?" --width="$smaller_width" --height="$smaller_height"

    # Check if the user wants to QuickBoot another VM using Zenity
    if [ $? -ne 0 ]; then
        break
    fi
done

# End of script
