#!/bin/bash

# QEMU QuickBoot Script using YAD (lightweight alternative to Zenity)
# Requires: yad, qemu-system-x86_64

# Set the GTK theme to dark
export GTK_THEME=Orchis:dark

# Calculate window sizes
original_width=450
original_height=320
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")

# Icon for YAD windows
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ICON="$SCRIPT_DIR/QEMU-QuickBoot.png"
YAD_ICON=""
[ -f "$ICON" ] && YAD_ICON="--window-icon=$ICON"

extra_disks=""
usb_hotplug_enabled=1

# --- Helper: prompt for boot mode + USB hotplug toggle in a single form ---
# Sets global variables: boot_mode, usb_hotplug_enabled
# Returns 1 if user cancels.
#
# UI shape: one form dialog with a single "Enable USB Support" checkbox.
# Firmware choice is made by pressing one of three dialog buttons:
#   Cancel -> exit code 1
#   BIOS   -> exit code 10
#   UEFI   -> exit code 12
# This keeps BIOS/UEFI as big, visible buttons (no dropdown) and still lets
# us bundle the USB toggle into the same window.
prompt_boot_mode_and_usb() {
    local result rc
    result=$(yad --form $YAD_ICON \
        --title="Select Boot Mode" \
        --width="$smaller_width" --height="$smaller_height" \
        --text="Choose firmware and VM options:" \
        --separator="|" \
        --field="Enable USB Support:CHK" "TRUE" \
        --button="Cancel:1" --button="BIOS:10" --button="UEFI:12")
    rc=$?

    case "$rc" in
        10) boot_mode="BIOS" ;;
        12) boot_mode="UEFI" ;;
         *) return 1 ;;
    esac

    local usb_flag
    usb_flag=$(echo "$result" | cut -d'|' -f1)
    if [ "$usb_flag" = "TRUE" ]; then
        usb_hotplug_enabled=1
    else
        usb_hotplug_enabled=0
    fi
    return 0
}

while true; do
    # Option to choose boot source using YAD - escape the & character
    boot_source_choice=$(yad --list $YAD_ICON \
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
            add_extra_disk=$(yad --list $YAD_ICON \
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
                    extra_disk_choice=$(yad --list $YAD_ICON \
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

            # Boot mode + USB support selection
            prompt_boot_mode_and_usb || exit 1
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
            add_extra_disk=$(yad --list $YAD_ICON \
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
                    extra_disk_choice=$(yad --list $YAD_ICON \
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

            prompt_boot_mode_and_usb || exit 1
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

            selected_drive_type=$(yad --list $YAD_ICON \
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
            add_extra_disk=$(yad --list $YAD_ICON \
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
                    extra_disk_choice=$(yad --list $YAD_ICON \
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

            prompt_boot_mode_and_usb || exit 1
            ;;

        *)
            continue
            ;;
    esac

    # Get RAM size using YAD entry
    ram_size=$(yad --entry $YAD_ICON \
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
        yad --error $YAD_ICON --title="Invalid Input" --text="Please enter a valid RAM size in MB" --width="$smaller_width" --height="$smaller_height"
        continue
    fi

    # Print the selected drive, extra disks, boot mode, and RAM size for debugging
    echo -e "\nSelected Drive: $selected_drive"
    echo "Extra Disks: $extra_disks"
    echo "Boot Mode: $boot_mode"
    echo "RAM Size: $ram_size MB"
    if [ "$usb_hotplug_enabled" = "1" ]; then
        echo "USB Hotplug: ENABLED"
    else
        echo "USB Hotplug: disabled"
    fi
    if [ -n "$iso_path" ]; then
        echo "ISO Path: $iso_path"
    fi

    # Clean any stale monitor socket and panel state files from a previous run
    rm -f /tmp/qemu-monitor.sock
    rm -f /tmp/vm-storage-devices.list
    rm -f /tmp/hotplug-devices.list

    # Start QEMU VM with the specified parameters
    qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw -usb -device usb-ehci,id=ehci -device qemu-xhci,id=xhci -device virtio-scsi-pci,id=scsi0 -monitor stdio -monitor unix:/tmp/qemu-monitor.sock,server,nowait"

    # Add ISO if specified
    if [ -n "$iso_path" ]; then
        qemu_command="$qemu_command -cdrom \"$iso_path\" -boot order=dc"
    fi

    # Add network (use random port to avoid conflicts)
    random_port=$((RANDOM % 1000 + 2222))
    qemu_command="$qemu_command -netdev user,id=net0,hostfwd=tcp::${random_port}-:22 -device e1000,netdev=net0 $extra_disks"

    # Set UEFI if selected
    if [ "$boot_mode" == "UEFI" ]; then
        qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M -drive file=\"$selected_drive\",format=raw -usb -device usb-ehci,id=ehci -device qemu-xhci,id=xhci -device virtio-scsi-pci,id=scsi0 -monitor stdio -monitor unix:/tmp/qemu-monitor.sock,server,nowait"

        if [ -n "$iso_path" ]; then
            qemu_command="$qemu_command -cdrom \"$iso_path\" -boot order=dc"
        fi

        qemu_command="$qemu_command -bios /usr/share/qemu/OVMF.fd -netdev user,id=net0,hostfwd=tcp::${random_port}-:22 -device e1000,netdev=net0 $extra_disks"
    fi

    echo "Running: $qemu_command"
    echo "SSH port forwarding: localhost:${random_port} -> VM:22"

    # Resolve script dir for hotplug helper
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    USB_HOTPLUG="$SCRIPT_DIR/usb-hotplug.sh"

    # Compute desired hotplug window position (upper-right area of screen so
    # it does NOT land on top of the QEMU window, which opens centered).
    # We target roughly: right edge minus hotplug width minus a margin; y ~120.
    HOTPLUG_WIDTH=400
    screen_w=""
    if command -v xdpyinfo &>/dev/null; then
        screen_w=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
    fi
    [ -z "$screen_w" ] && screen_w=1920
    HOTPLUG_POSX=$(( screen_w - HOTPLUG_WIDTH - 40 ))
    [ "$HOTPLUG_POSX" -lt 0 ] && HOTPLUG_POSX=40
    HOTPLUG_POSY=120
    export HOTPLUG_POSX HOTPLUG_POSY

    # --- Launch QEMU in the background so we can supervise the hotplug helper ---
    # Start QEMU in its own background process so we hold its PID.
    bash -c "$qemu_command" &
    qemu_pid=$!
    export QEMU_PID="$qemu_pid"

    hotplug_pid=""
    hotplug_pgid=""
    if [ "$usb_hotplug_enabled" = "1" ]; then
        # Launch the hotplug helper in its OWN process group via setsid, so when
        # QEMU dies we can kill the entire group (including yad, its children,
        # and any GUI dialogs it has spawned) with a single signal.
        setsid bash -c '
            # Wait up to 15 seconds for QEMU monitor socket
            for i in $(seq 1 15); do
                [ -S /tmp/qemu-monitor.sock ] && break
                kill -0 "'"$qemu_pid"'" 2>/dev/null || exit 0
                sleep 1
            done
            if [ -S /tmp/qemu-monitor.sock ] && kill -0 "'"$qemu_pid"'" 2>/dev/null; then
                if [ -f "'"$USB_HOTPLUG"'" ]; then
                    exec bash "'"$USB_HOTPLUG"'"
                else
                    yad --error '"$YAD_ICON"' --title="USB Hotplug" --text="usb-hotplug.sh not found at:\n'"$USB_HOTPLUG"'" --button="OK:0"
                fi
            fi
        ' </dev/null &
        hotplug_pid=$!
        # In a setsid-launched process, PID == PGID
        hotplug_pgid="$hotplug_pid"

        # Watchdog: when QEMU exits, kill the hotplug process group.
        # Killing the group (via negative PID) reaches yad and any descendants,
        # unlike `pkill -P` which only hits direct children.
        (
            while kill -0 "$qemu_pid" 2>/dev/null; do
                sleep 1
            done
            if [ -n "$hotplug_pgid" ]; then
                kill -TERM -- "-$hotplug_pgid" 2>/dev/null
                sleep 0.3
                kill -KILL -- "-$hotplug_pgid" 2>/dev/null
            fi
        ) &
    fi

    # Block on QEMU like before; the hotplug helper is coupled via the watchdog above.
    wait "$qemu_pid"

    # Final cleanup in case watchdog missed anything
    if [ -n "$hotplug_pgid" ]; then
        kill -TERM -- "-$hotplug_pgid" 2>/dev/null
        sleep 0.2
        kill -KILL -- "-$hotplug_pgid" 2>/dev/null
    fi
    rm -f /tmp/qemu-monitor.sock

    # Ask to run another VM
    yad --question $YAD_ICON \
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
    usb_hotplug_enabled=1
done

# End of script
