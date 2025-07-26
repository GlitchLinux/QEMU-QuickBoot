#!/bin/bash

# QEMU QuickBoot Script using YAD (lightweight alternative to Zenity)
# Requires: yad, qemu-system-x86_64

# Set the GTK theme to dark
export GTK_THEME=Orchis:dark

# Calculate window sizes
original_width=450
original_height=300
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")

extra_disks=""

while true; do
    # Option to choose boot source using YAD - escape the & character
    boot_source_choice=$(yad --list \
        --title="Select VM Boot Source" \
        --width="$original_width" --height="$smaller_height" \
        --column="Option" \
        --text="Select items from the list below." \
        --button="Cancel:1" --button="OK:0" \
        "Boot from connected device" \
        "Boot from file (.vhd, .img, .iso)" \
        "ISO &amp; Drive (Virtual disk or Physical Device)")

    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Remove YAD's trailing | from output
    boot_source_choice=$(echo "$boot_source_choice" | sed 's/|$//')

    case "$boot_source_choice" in
        "Boot from connected device")
            # Simple approach - build the YAD command with all drives as arguments
            yad_args=("--list" "--title=Select Disk" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a disk:" "--button=Cancel:1" "--button=OK:0")
            
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    drive_name=$(echo "$line" | awk '{print $1}')
                    drive_size=$(echo "$line" | awk '{print $2}')
                    yad_args+=("$drive_name" "$drive_size")
                fi
            done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

            selected_drive=$(yad "${yad_args[@]}")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            # Extract just the drive name (first column)
            selected_drive=$(echo "$selected_drive" | cut -d'|' -f1)

            # Prompt for extra disks
            add_extra_disk=$(yad --list \
                --title="Add Extra Disk" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Option" \
                --text="Do you want to add an extra disk?" \
                --button="Cancel:1" --button="OK:0" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            add_extra_disk=$(echo "$add_extra_disk" | sed 's/|$//')

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    extra_disk_choice=$(yad --list \
                        --title="Select Extra Disk Type" \
                        --width="$bigger_width" --height="$smaller_height" \
                        --column="Option" \
                        --text="Select items from the list below." \
                        --button="Cancel:1" --button="OK:0" \
                        "Select Virtual Disk" \
                        "Select Physical Device" \
                        "Done")

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(yad --file \
                            --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" \
                            --width="$smaller_width" --height="$smaller_height" \
                            --file-filter="Virtual Disks | *.img *.vhd *.vhdx" \
                            --file-filter="All files | *")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        # Use the same working drive listing approach
                        yad_args=("--list" "--title=Select Extra Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select an extra physical device:" "--button=Cancel:1" "--button=OK:0")
                        
                        while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                drive_name=$(echo "$line" | awk '{print $1}')
                                drive_size=$(echo "$line" | awk '{print $2}')
                                yad_args+=("$drive_name" "$drive_size")
                            fi
                        done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                        extra_disk=$(yad "${yad_args[@]}")

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            # Boot mode selection exactly like your screenshot
            boot_mode=$(yad --list \
                --title="Select Boot Mode" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Boot Mode" \
                --text="Select items from the list below." \
                --button="Cancel:1" --button="OK:0" \
                "BIOS" "UEFI")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            boot_mode=$(echo "$boot_mode" | sed 's/|$//')
            ;;

        "Boot from file (.vhd, .img, .iso)")
            selected_drive=$(yad --file \
                --title="Select Virtual Disk (.vhd, .img, .iso)" \
                --width="$smaller_width" --height="$smaller_height" \
                --file-filter="Virtual Disks | *.vhd *.img *.iso *.vhdx" \
                --file-filter="All files | *")

            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                continue
            fi

            # Prompt for extra disks
            add_extra_disk=$(yad --list \
                --title="Add Extra Disk" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Option" \
                --text="Do you want to add an extra disk?" \
                --button="Cancel:1" --button="OK:0" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            add_extra_disk=$(echo "$add_extra_disk" | sed 's/|$//')

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    extra_disk_choice=$(yad --list \
                        --title="Select Extra Disk Type" \
                        --width="$bigger_width" --height="$smaller_height" \
                        --column="Option" \
                        --text="Select items from the list below." \
                        --button="Cancel:1" --button="OK:0" \
                        "Select Virtual Disk" \
                        "Select Physical Device" \
                        "Done")

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(yad --file \
                            --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" \
                            --width="$smaller_width" --height="$smaller_height" \
                            --file-filter="Virtual Disks | *.img *.vhd *.vhdx" \
                            --file-filter="All files | *")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        # Use the same working drive listing approach
                        yad_args=("--list" "--title=Select Extra Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select an extra physical device:" "--button=Cancel:1" "--button=OK:0")
                        
                        while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                drive_name=$(echo "$line" | awk '{print $1}')
                                drive_size=$(echo "$line" | awk '{print $2}')
                                yad_args+=("$drive_name" "$drive_size")
                            fi
                        done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                        extra_disk=$(yad "${yad_args[@]}")

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(yad --list \
                --title="Select Boot Mode" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Boot Mode" \
                --text="Select items from the list below." \
                --button="Cancel:1" --button="OK:0" \
                "BIOS" "UEFI")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            boot_mode=$(echo "$boot_mode" | sed 's/|$//')
            ;;

        "ISO &amp; Drive (Virtual disk or Physical Device)"|"ISO & Drive (Virtual disk or Physical Device)")
            iso_path=$(yad --file \
                --title="Select .ISO file" \
                --width="$smaller_width" --height="$smaller_height" \
                --file-filter="ISO files | *.iso" \
                --file-filter="All files | *")

            if [ $? -ne 0 ] || [ ! -f "$iso_path" ]; then
                continue
            fi

            selected_drive_type=$(yad --list \
                --title="Select Virtual Disk or Physical Device" \
                --width="$bigger_width" --height="$smaller_height" \
                --column="Option" \
                --text="Select items from the list below." \
                --button="Cancel:1" --button="OK:0" \
                "Select Virtual Disk" \
                "Select Physical Device")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            selected_drive_type=$(echo "$selected_drive_type" | sed 's/|$//')

            if [ "$selected_drive_type" == "Select Virtual Disk" ]; then
                selected_drive=$(yad --file \
                    --title="Select Virtual Disk (.img, .vhd, .vhdx)" \
                    --width="$smaller_width" --height="$smaller_height" \
                    --file-filter="Virtual Disks | *.img *.vhd *.vhdx" \
                    --file-filter="All files | *")

                if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                    continue
                fi
            elif [ "$selected_drive_type" == "Select Physical Device" ]; then
                # Use the same working drive listing approach
                yad_args=("--list" "--title=Select Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a physical device:" "--button=Cancel:1" "--button=OK:0")
                
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        drive_name=$(echo "$line" | awk '{print $1}')
                        drive_size=$(echo "$line" | awk '{print $2}')
                        yad_args+=("$drive_name" "$drive_size")
                    fi
                done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                selected_drive=$(yad "${yad_args[@]}")

                if [ $? -ne 0 ]; then
                    exit 1
                fi

                selected_drive=$(echo "$selected_drive" | cut -d'|' -f1)
            else
                continue
            fi

            # Prompt for extra disks
            add_extra_disk=$(yad --list \
                --title="Add Extra Disk" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Option" \
                --text="Do you want to add an extra disk?" \
                --button="Cancel:1" --button="OK:0" \
                "Yes" "No")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            add_extra_disk=$(echo "$add_extra_disk" | sed 's/|$//')

            if [ "$add_extra_disk" == "Yes" ]; then
                extra_disk_id=1

                while true; do
                    extra_disk_choice=$(yad --list \
                        --title="Select Extra Disk Type" \
                        --width="$bigger_width" --height="$smaller_height" \
                        --column="Option" \
                        --text="Select items from the list below." \
                        --button="Cancel:1" --button="OK:0" \
                        "Select Virtual Disk" \
                        "Select Physical Device" \
                        "Done")

                    if [ $? -ne 0 ]; then
                        exit 1
                    fi

                    extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                    if [ "$extra_disk_choice" == "Select Virtual Disk" ]; then
                        extra_disk=$(yad --file \
                            --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" \
                            --width="$smaller_width" --height="$smaller_height" \
                            --file-filter="Virtual Disks | *.img *.vhd *.vhdx" \
                            --file-filter="All files | *")

                        if [ $? -ne 0 ] || [ ! -f "$extra_disk" ]; then
                            continue
                        fi

                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        # Use the same working drive listing approach
                        yad_args=("--list" "--title=Select Extra Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select an extra physical device:" "--button=Cancel:1" "--button=OK:0")
                        
                        while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                drive_name=$(echo "$line" | awk '{print $1}')
                                drive_size=$(echo "$line" | awk '{print $2}')
                                yad_args+=("$drive_name" "$drive_size")
                            fi
                        done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                        extra_disk=$(yad "${yad_args[@]}")

                        if [ $? -ne 0 ]; then
                            exit 1
                        fi

                        extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    else
                        continue
                    fi
                done
            fi

            boot_mode=$(yad --list \
                --title="Select Boot Mode" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Boot Mode" \
                --text="Select items from the list below." \
                --button="Cancel:1" --button="OK:0" \
                "BIOS" "UEFI")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            boot_mode=$(echo "$boot_mode" | sed 's/|$//')
            ;;

        *)
            continue
            ;;
    esac

    # Get RAM size using YAD entry
    ram_size=$(yad --entry \
        --title="Enter RAM Size" \
        --width="$smaller_width" --height="$smaller_height" \
        --text="Enter the amount of RAM for the VM (in MB):" \
        --entry-text="2048" \
        --button="Cancel:1" --button="OK:0")

    if [ $? -ne 0 ]; then
        continue
    fi

    # Validate RAM size
    if ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
        yad --error --title="Invalid Input" --text="Please enter a valid RAM size in MB" --width="$smaller_width" --height="$smaller_height"
        continue
    fi

    # Print the selected drive, extra disks, boot mode, and RAM size for debugging
    echo -e "\nSelected Drive: $selected_drive"
    echo "Extra Disks: $extra_disks"
    echo "Boot Mode: $boot_mode"
    echo "RAM Size: $ram_size MB"
    if [ -n "$iso_path" ]; then
        echo "ISO Path: $iso_path"
    fi

    # Start QEMU VM with the specified parameters
    qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw"

    # Add ISO if specified
    if [ -n "$iso_path" ]; then
        qemu_command="$qemu_command -cdrom \"$iso_path\" -boot order=dc"
    fi

    # Add network (use random port to avoid conflicts)
    random_port=$((RANDOM % 1000 + 2222))
    qemu_command="$qemu_command -netdev user,id=net0,hostfwd=tcp::${random_port}-:22 -device e1000,netdev=net0 $extra_disks"

    # Set UEFI if selected
    if [ "$boot_mode" == "UEFI" ]; then
        qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw"
        
        if [ -n "$iso_path" ]; then
            qemu_command="$qemu_command -cdrom \"$iso_path\" -boot order=dc"
        fi
        
        qemu_command="$qemu_command -bios /usr/share/qemu/OVMF.fd -netdev user,id=net0,hostfwd=tcp::${random_port}-:22 -device e1000,netdev=net0 $extra_disks"
    fi

    echo "Running: $qemu_command"
    echo "SSH port forwarding: localhost:${random_port} -> VM:22"
    
    # Run QEMU command
    eval $qemu_command

    # Ask to run another VM
    yad --question \
        --title="QEMU - QuickBoot" \
        --width="$smaller_width" --height="$smaller_height" \
        --text="QuickBoot another VM?" \
        --button="No:1" --button="Yes:0"

    if [ $? -ne 0 ]; then
        break
    fi

    # Reset variables for next iteration
    extra_disks=""
    iso_path=""
done

# End of script
