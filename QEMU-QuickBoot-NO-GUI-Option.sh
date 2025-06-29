#!/bin/bash

# Set the GTK theme to dark
export GTK_THEME=Orchis-Dark:dark

# Calculate window sizes
original_width=380
original_height=360
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")

extra_disks=""

while true; do
    # Option to choose boot source using Zenity
    boot_source_choice=$(zenity --list --title="Select VM Boot Source" --column="Option" --width="$original_width" --height="$smaller_height" \
        "Boot from connected device" "Boot from file (.vhd, .img, .iso)" "ISO & Drive (Virtual disk or Physical Device)")

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

            # Prompt for extra disks
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

        "Boot from file (.vhd, .img, .iso)")
            selected_drive=$(zenity --file-selection --title="Select Virtual Disk (.vhd, .img, .iso)" --width="$smaller_width" --height="$smaller_height")

            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                continue
            fi

            # Prompt for extra disks
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

            # Prompt for extra disks
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

    # Prompt for connection mode (after firmware selection)
    connection_mode=$(zenity --list --title="Select Connection Mode" --column="Option" --text "How do you want to connect to the VM?" --width="$smaller_width" --height="$smaller_height" \
        "GUI Display (default)" "SSH Connect" --hide-header)

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Default to GUI if user presses Enter
    if [ -z "$connection_mode" ]; then
        connection_mode="GUI Display (default)"
    fi

    ram_size=$(zenity --entry --title="Enter RAM Size" --text "Enter the amount of RAM for the VM (in MB):" --width="$smaller_width" --height="$smaller_height")

    if [ $? -ne 0 ] || ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
        continue
    fi

    # Print the selected drive, extra disks, boot mode, and RAM size for debugging
    echo -e "\nSelected Drive: $selected_drive"
    echo "Extra Disks: $extra_disks"
    echo "Boot Mode: $boot_mode"
    echo "Connection Mode: $connection_mode"
    echo "RAM Size: $ram_size MB"

    # Base QEMU command (common for all modes)
    qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw -netdev user,id=net0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0 $extra_disks"

    # Add ISO if selected
    if [ "$boot_source_choice" == "ISO & Drive (Virtual disk or Physical Device)" ]; then
        qemu_command="$qemu_command -cdrom \"$iso_path\" -boot order=dc"
    fi

    # Set boot mode (BIOS/UEFI)
    if [ "$boot_mode" == "UEFI" ]; then
        qemu_command="$qemu_command -bios /usr/share/qemu/OVMF.fd"
    fi

    # Handle connection mode
    if [[ "$connection_mode" == "SSH Connect" ]]; then
        qemu_command="$qemu_command -display none"
        
        # Start QEMU in background
        eval "$qemu_command" &
        QEMU_PID=$!

        # Show control panel
        while true; do
            action=$(zenity --list --title="Headless VM Control" \
                --text="<b>Headless VM is running!</b>\n\nConnect via SSH:\n\n<tt>ssh user@localhost -p 2222</tt>\n\n" \
                --width=400 --height=200 \
                --column="Action" "Stop VM" "Restart VM" "Close" \
                --hide-header)

            case $action in
                "Stop VM")
                    kill $QEMU_PID
                    zenity --info --title="VM Stopped" --text="The VM has been terminated." --width=300
                    break
                    ;;
                "Restart VM")
                    kill $QEMU_PID
                    sleep 1
                    eval "$qemu_command" &
                    QEMU_PID=$!
                    zenity --info --title="VM Restarted" --text="The VM has been restarted." --width=300
                    ;;
                *)
                    break  # Close window
                    ;;
            esac
        done
    else
        # Run GUI mode normally
        eval "$qemu_command"
    fi

    # Prompt to start another VM
    zenity --question --title="QEMU - QuickBoot" --text="QuickBoot another VM?" --width="$smaller_width" --height="$smaller_height"

    if [ $? -ne 0 ]; then
        break
    fi
done

# End of script