#!/bin/bash

# Set the GTK theme to dark
export GTK_THEME=Orchis-Dark:dark

# Calculate 30% wider size for the first Zenity window
original_width=360
original_height=360
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")
geometry="${smaller_width}x${smaller_height}"

extra_disks=""

# Check if NAS is mounted locally (replace with your actual mount point)
nas_mounted=$(mount | grep -q "/mnt/nas"; echo $?)

while true; do
    # Option to choose boot source using Zenity (add NAS option if mounted)
    if [ $nas_mounted -eq 0 ]; then
        boot_source_choice=$(zenity --list --title="Select VM Boot Source" --column="Option" --width="$original_width" --height="$smaller_height" \
            "Boot from connected device" "Boot from file (.vhd, .img, .iso)" "ISO & Drive (Virtual disk or Physical Device)" "Boot from Network Attached Storage (NAS)")
    else
        boot_source_choice=$(zenity --list --title="Select VM Boot Source" --column="Option" --width="$original_width" --height="$smaller_height" \
            "Boot from connected device" "Boot from file (.vhd, .img, .iso)" "ISO & Drive (Virtual disk or Physical Device)")
    fi

    if [ $? -ne 0 ]; then
        exit 1
    fi

    case $boot_source_choice in
        "Boot from connected device")
            drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
            selected_drive=$(zenity --list --title="Select Disk" --column="Drive" --column="Size" --text "Select a disk:" --width="$bigger_width" --height="$smaller_height" $drives)

            if [ $? -ne 0 ]; then
                exit 1
            fi

            # Prompt for extra disks (including NAS option if available)
            add_extra_disk=$(zenity --list --title="Add Extra Disk" --column="Option" --text="Do you want to add an extra disk?" --width="$smaller_width" --height="$smaller_height" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    if [ $nas_mounted -eq 0 ]; then
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Select from NAS" "Done")
                    else
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Done")
                    fi

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(zenity --file-selection --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                        extra_disk=$(zenity --list --title="Select Extra Physical Device" --column="Drive" --column="Size" --text "Select an extra physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select from NAS" ]; then
                        nas_path=$(zenity --file-selection --filename="/mnt/nas/" --title="Select NAS Disk Image (.img, .vhd, .iso)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$nas_path" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$nas_path\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;

        "Boot from file (.vhd, .img, .iso)")
            selected_drive=$(zenity --file-selection --title="Select Virtual Disk (.vhd, .img, .iso)" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                continue
            fi

            # Prompt for extra disks (including NAS option)
            add_extra_disk=$(zenity --list --title="Add Extra Disk" --column="Option" --text="Do you want to add an extra disk?" --width="$smaller_width" --height="$smaller_height" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    if [ $nas_mounted -eq 0 ]; then
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Select from NAS" "Done")
                    else
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Done")
                    fi

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(zenity --file-selection --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                        extra_disk=$(zenity --list --title="Select Extra Physical Device" --column="Drive" --column="Size" --text "Select an extra physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select from NAS" ]; then
                        nas_path=$(zenity --file-selection --filename="/mnt/nas/" --title="Select NAS Disk Image (.img, .vhd, .iso)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$nas_path" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$nas_path\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;

        "ISO & Drive (Virtual disk or Physical Device)")
            iso_path=$(zenity --file-selection --title="Select .ISO file" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ] || [ ! -f "$iso_path" ]; then
                continue
            fi

            selected_drive=$(zenity --list --title="Select Virtual Disk or Physical Device" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                "Select Virtual Disk" "Select Physical Device")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            if [ "$selected_drive" == "Select Virtual Disk" ]; then
                selected_drive=$(zenity --file-selection --title="Select Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                    continue
                fi
            elif [ "$selected_drive" == "Select Physical Device" ]; then
                drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                selected_drive=$(zenity --list --title="Select Physical Device" --column="Drive" --column="Size" --text "Select a physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                if [ $? -ne 0 ]; then
                    exit 1
                fi
            else
                continue
            fi

            # Prompt for extra disks (including NAS option)
            add_extra_disk=$(zenity --list --title="Add Extra Disk" --column="Option" --text="Do you want to add an extra disk?" --width="$smaller_width" --height="$smaller_height" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    if [ $nas_mounted -eq 0 ]; then
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Select from NAS" "Done")
                    else
                        extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                            "Select Virtual Disk" "Select Physical Device" "Done")
                    fi

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(zenity --file-selection --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                        extra_disk=$(zenity --list --title="Select Extra Physical Device" --column="Drive" --column="Size" --text "Select an extra physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select from NAS" ]; then
                        nas_path=$(zenity --file-selection --filename="/mnt/nas/" --title="Select NAS Disk Image (.img, .vhd, .iso)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$nas_path" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$nas_path\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;

        "Boot from Network Attached Storage (NAS)")
            # Check if NAS is mounted
            if [ $nas_mounted -ne 0 ]; then
                zenity --error --text="NAS is not mounted. Please mount it first." --width="$smaller_width" --height="$smaller_height"
                continue
            fi

            # Let user select NAS image
            selected_drive=$(zenity --file-selection --filename="/mnt/nas/" --title="Select NAS Disk Image (.img, .vhd, .iso)" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                continue
            fi

            # Prompt for extra disks (physical or virtual)
            add_extra_disk=$(zenity --list --title="Add Extra Disk" --column="Option" --text="Do you want to add an extra disk?" --width="$smaller_width" --height="$smaller_height" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" --column="Option" --width="$bigger_width" --height="$smaller_height" \
                        "Select Virtual Disk" "Select Physical Device" "Done")

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(zenity --file-selection --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" --width="$smaller_width" --height="$smaller_height")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                        extra_disk=$(zenity --list --title="Select Extra Physical Device" --column="Drive" --column="Size" --text "Select an extra physical device:" --width="$bigger_width" --height="$smaller_height" $drives)

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"

                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(zenity --list --title="Select Boot Mode" --column="Boot Mode" "BIOS" "UEFI" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;

        *)
            continue
            ;;
    esac

    ram_size=$(zenity --entry --title="Enter RAM Size" --text "Enter the amount of RAM for the VM (in MB):" --width="$smaller_width" --height="$smaller_height")

    if [ $? -ne 0 ] || ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
        continue
    fi

    # Print the selected drive, extra disks, boot mode, and RAM size for debugging
    echo -e "\nSelected Drive: $selected_drive"
    echo "Extra Disks: $extra_disks"
    echo "Boot Mode: $boot_mode"
    echo "RAM Size: $ram_size MB"

    # Start QEMU VM with the specified parameters
    qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw -boot order=dc -netdev user,id=net0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0 $extra_disks"

    if [ "$boot_mode" == "UEFI" ]; then
        qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw -bios /usr/share/qemu/OVMF.fd -boot order=dc -netdev user,id=net0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0 $extra_disks"
    fi

    # If ISO was selected (for ISO & Drive option)
    if [ -n "$iso_path" ]; then
        qemu_command=$(echo "$qemu_command" | sed "s/-boot order=dc/-cdrom \"$iso_path\" -boot order=dc/")
    fi

    # Run QEMU command
    eval $qemu_command

    # Combine notifications and prompt in a single Zenity window
    zenity --question --title="QEMU - QuickBoot" --text="QuickBoot another VM?" --width="$smaller_width" --height="$smaller_height"

    if [ $? -ne 0 ]; then
        break
    fi
done

# End of script
