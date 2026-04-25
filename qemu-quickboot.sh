#!/bin/bash

# QEMU QuickBoot — main launcher (uses YAD for GUI dialogs)
# Requires: yad, qemu-system-x86_64, socat
# Companion script: quickboot-settings.sh (VM Session Settings panel)
#
# 2026 update — applied via review:
#   * Format autodetection for primary boot source and extra disks
#   * ISO selected as primary boot source now boots via -cdrom (not -drive)
#   * USB controllers gated on the "Enable USB" checkbox
#   * Inner restart loop so the session panel can request an IPv4 reconfig
#     restart without losing the user's other settings

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
ICON="$SCRIPT_DIR/qemu-quickboot.png"
YAD_ICON=""
[ -f "$ICON" ] && YAD_ICON="--window-icon=$ICON"

extra_disks=""
usb_hotplug_enabled=1

# --- Detect QEMU drive format from path or block device ---
# Block devices and unknown extensions default to raw. ISOs return "iso" so
# the caller can decide whether to attach as -drive or -cdrom.
detect_format() {
    local path="$1"
    if [ -b "$path" ]; then echo "raw"; return; fi
    local ext="${path##*.}"
    case "${ext,,}" in
        qcow2|qcow) echo "qcow2" ;;
        vmdk)       echo "vmdk" ;;
        vdi)        echo "vdi" ;;
        vhdx)       echo "vhdx" ;;
        vhd|vpc)    echo "vpc" ;;
        iso)        echo "iso" ;;
        *)          echo "raw" ;;
    esac
}

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
                        --width="$smaller_width" --height="$smaller_height" \
                        --column="Option" \
                        --text="Choose the type of extra disk:" \
                        --button="Cancel:1" --button="OK:0" \
                        "Select Virtual Disk File" \
                        "Select Physical Device" \
                        "Done")

                    if [ $? -ne 0 ]; then
                        break
                    fi

                    extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                    if [ "$extra_disk_choice" == "Select Virtual Disk File" ]; then
                        extra_disk=$(yad --file $YAD_ICON \
                            --title="Select Extra Virtual Disk File" \
                            --width="$bigger_width" --height="$smaller_height")

                        if [ $? -ne 0 ]; then
                            continue
                        fi

                        extra_fmt=$(detect_format "$extra_disk")
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        yad_args=("--list" "--title=Select Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a physical device:" "--button=Cancel:1" "--button=OK:0")

                        while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                drive_name=$(echo "$line" | awk '{print $1}')
                                drive_size=$(echo "$line" | awk '{print $2}')
                                yad_args+=("$drive_name" "$drive_size")
                            fi
                        done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                        extra_disk=$(yad "${yad_args[@]}")

                        if [ $? -ne 0 ]; then
                            continue
                        fi

                        extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                        extra_fmt=$(detect_format "$extra_disk")
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    fi
                done
            fi

            # Use a single form dialog for boot mode + USB toggle.
            prompt_boot_mode_and_usb || exit 1
            ;;

        "Boot from file (.vhd, .img, .iso)")
            # Select disk image file
            selected_drive=$(yad --file $YAD_ICON \
                --title="Select Disk Image" \
                --width="$bigger_width" --height="$smaller_height")

            if [ $? -ne 0 ]; then
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
                        --width="$smaller_width" --height="$smaller_height" \
                        --column="Option" \
                        --text="Choose the type of extra disk:" \
                        --button="Cancel:1" --button="OK:0" \
                        "Select Virtual Disk File" \
                        "Select Physical Device" \
                        "Done")

                    if [ $? -ne 0 ]; then
                        break
                    fi

                    extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                    if [ "$extra_disk_choice" == "Select Virtual Disk File" ]; then
                        extra_disk=$(yad --file $YAD_ICON \
                            --title="Select Extra Virtual Disk File" \
                            --width="$bigger_width" --height="$smaller_height")

                        if [ $? -ne 0 ]; then
                            continue
                        fi

                        extra_fmt=$(detect_format "$extra_disk")
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                        yad_args=("--list" "--title=Select Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a physical device:" "--button=Cancel:1" "--button=OK:0")

                        while IFS= read -r line; do
                            if [ -n "$line" ]; then
                                drive_name=$(echo "$line" | awk '{print $1}')
                                drive_size=$(echo "$line" | awk '{print $2}')
                                yad_args+=("$drive_name" "$drive_size")
                            fi
                        done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                        extra_disk=$(yad "${yad_args[@]}")

                        if [ $? -ne 0 ]; then
                            continue
                        fi

                        extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                        extra_fmt=$(detect_format "$extra_disk")
                        extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                        extra_disk_id=$((extra_disk_id + 1))

                    elif [ "$extra_disk_choice" == "Done" ]; then
                        break
                    fi
                done
            fi

            # Use a single form dialog for boot mode + USB toggle.
            prompt_boot_mode_and_usb || exit 1
            ;;

        "ISO &amp; Drive..."|"ISO &amp; Drive (Virtual disk or Physical Device)"|"ISO & Drive (Virtual disk or Physical Device)")
            # First select ISO file
            iso_path=$(yad --file $YAD_ICON \
                --title="Select ISO File" \
                --width="$bigger_width" --height="$smaller_height" \
                --file-filter="ISO files | *.iso")

            if [ $? -ne 0 ]; then
                continue
            fi

            # Then select drive type
            drive_type=$(yad --list $YAD_ICON \
                --title="Select Drive Type" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Option" \
                --text="Choose drive type:" \
                --button="Cancel:1" --button="OK:0" \
                "Virtual Disk" \
                "Physical Device")

            if [ $? -ne 0 ]; then
                exit 1
            fi

            drive_type=$(echo "$drive_type" | sed 's/|$//')

            if [ "$drive_type" == "Virtual Disk" ]; then
                selected_drive=$(yad --file $YAD_ICON \
                    --title="Select Virtual Disk File" \
                    --width="$bigger_width" --height="$smaller_height")

                if [ $? -ne 0 ]; then
                    exit 1
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
                            --width="$smaller_width" --height="$smaller_height" \
                            --column="Option" \
                            --text="Choose the type of extra disk:" \
                            --button="Cancel:1" --button="OK:0" \
                            "Select Virtual Disk File" \
                            "Select Physical Device" \
                            "Done")

                        if [ $? -ne 0 ]; then
                            break
                        fi

                        extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                        if [ "$extra_disk_choice" == "Select Virtual Disk File" ]; then
                            extra_disk=$(yad --file $YAD_ICON \
                                --title="Select Extra Virtual Disk File" \
                                --width="$bigger_width" --height="$smaller_height")

                            if [ $? -ne 0 ]; then
                                continue
                            fi

                            extra_fmt=$(detect_format "$extra_disk")
                            extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                            extra_disk_id=$((extra_disk_id + 1))

                        elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                            yad_args=("--list" "--title=Select Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a physical device:" "--button=Cancel:1" "--button=OK:0")

                            while IFS= read -r line; do
                                if [ -n "$line" ]; then
                                    drive_name=$(echo "$line" | awk '{print $1}')
                                    drive_size=$(echo "$line" | awk '{print $2}')
                                    yad_args+=("$drive_name" "$drive_size")
                                fi
                            done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                            extra_disk=$(yad "${yad_args[@]}")

                            if [ $? -ne 0 ]; then
                                continue
                            fi

                            extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                            extra_fmt=$(detect_format "$extra_disk")
                            extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                            extra_disk_id=$((extra_disk_id + 1))

                        elif [ "$extra_disk_choice" == "Done" ]; then
                            break
                        fi
                    done
                fi

            elif [ "$drive_type" == "Physical Device" ]; then
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
                            --width="$smaller_width" --height="$smaller_height" \
                            --column="Option" \
                            --text="Choose the type of extra disk:" \
                            --button="Cancel:1" --button="OK:0" \
                            "Select Virtual Disk File" \
                            "Select Physical Device" \
                            "Done")

                        if [ $? -ne 0 ]; then
                            break
                        fi

                        extra_disk_choice=$(echo "$extra_disk_choice" | sed 's/|$//')

                        if [ "$extra_disk_choice" == "Select Virtual Disk File" ]; then
                            extra_disk=$(yad --file $YAD_ICON \
                                --title="Select Extra Virtual Disk File" \
                                --width="$bigger_width" --height="$smaller_height")

                            if [ $? -ne 0 ]; then
                                continue
                            fi

                            extra_fmt=$(detect_format "$extra_disk")
                            extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                            extra_disk_id=$((extra_disk_id + 1))

                        elif [ "$extra_disk_choice" == "Select Physical Device" ]; then
                            yad_args=("--list" "--title=Select Physical Device" "--width=$bigger_width" "--height=$smaller_height" "--column=Drive" "--column=Size" "--text=Select a physical device:" "--button=Cancel:1" "--button=OK:0")

                            while IFS= read -r line; do
                                if [ -n "$line" ]; then
                                    drive_name=$(echo "$line" | awk '{print $1}')
                                    drive_size=$(echo "$line" | awk '{print $2}')
                                    yad_args+=("$drive_name" "$drive_size")
                                fi
                            done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                            extra_disk=$(yad "${yad_args[@]}")

                            if [ $? -ne 0 ]; then
                                continue
                            fi

                            extra_disk=$(echo "$extra_disk" | cut -d'|' -f1)
                            extra_fmt=$(detect_format "$extra_disk")
                            extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$extra_fmt,id=extra_drive$extra_disk_id"
                            extra_disk_id=$((extra_disk_id + 1))

                        elif [ "$extra_disk_choice" == "Done" ]; then
                            break
                        fi
                    done
                fi
            fi

            # Use a single form dialog for boot mode + USB toggle.
            prompt_boot_mode_and_usb || exit 1
            ;;

        *)
            yad --error $YAD_ICON --title="Invalid Choice" --text="Please select a valid option" --width="$smaller_width" --height="$smaller_height"
            continue
            ;;
    esac

    # Prompt for RAM size
    ram_size=$(yad --entry $YAD_ICON \
        --title="Set RAM Size" \
        --width="$smaller_width" --height="$smaller_height" \
        --text="Enter RAM size in MB:" \
        --entry-text="2048" \
        --button="Cancel:1" --button="OK:0")

    if [ $? -ne 0 ]; then
        continue
    fi

    if ! [[ "$ram_size" =~ ^[0-9]+$ ]] || [ "$ram_size" -lt 256 ]; then
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

    # --- Launch / restart loop ---
    # The session panel can request a VM restart (e.g. for IPv4 reconfig) by
    # writing /tmp/qemu-quickboot-restart and sending 'quit' to the monitor.
    # We re-enter this inner loop with the new netdev fragment appended,
    # reusing every other launch parameter so the user doesn't redo prompts.
    net_config_extras=""
    rm -f /tmp/qemu-quickboot-restart

    while true; do
        # Clean any stale monitor socket and panel state files from a previous run
        rm -f /tmp/qemu-monitor.sock
        rm -f /tmp/vm-storage-devices.list
        rm -f /tmp/hotplug-devices.list

        # Detect format of the primary source. ISOs become -cdrom, everything
        # else (block device or disk image) becomes -drive with that format.
        main_format=$(detect_format "$selected_drive")

        if [ "$main_format" = "iso" ] && [ -z "$iso_path" ]; then
            # User picked an ISO via "Boot from file" — boot it as a CD.
            primary_args="-cdrom \"$selected_drive\" -boot order=d"
        elif [ -n "$iso_path" ]; then
            # ISO + Drive mode: drive is primary, ISO is supplementary.
            primary_args="-drive file=\"$selected_drive\",format=$main_format -cdrom \"$iso_path\" -boot order=dc"
        else
            primary_args="-drive file=\"$selected_drive\",format=$main_format"
        fi

        # USB controllers only when the user enabled USB at launch time.
        usb_args=""
        if [ "$usb_hotplug_enabled" = "1" ]; then
            usb_args="-usb -device usb-ehci,id=ehci -device qemu-xhci,id=xhci"
        fi

        # SSH-forward host port. Persist within a session so a restart for
        # IPv4 reconfig keeps the same SSH endpoint.
        if [ -z "$random_port" ]; then
            random_port=$((RANDOM % 1000 + 2222))
        fi

        # Network: SLIRP user-mode, optional IPv4/subnet override appended
        # by the session panel via the restart loop.
        netdev_arg="user,id=net0,hostfwd=tcp::${random_port}-:22"
        if [ -n "$net_config_extras" ]; then
            netdev_arg="${netdev_arg},${net_config_extras}"
        fi
        network_args="-netdev ${netdev_arg} -device e1000,netdev=net0"

        bios_args=""
        if [ "$boot_mode" = "UEFI" ]; then
            bios_args="-bios /usr/share/qemu/OVMF.fd"
        fi

        qemu_command="qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m ${ram_size}M $primary_args $usb_args -device virtio-scsi-pci,id=scsi0 -monitor stdio -monitor unix:/tmp/qemu-monitor.sock,server,nowait $bios_args $network_args $extra_disks"

        echo "Running: $qemu_command"
        echo "SSH port forwarding: localhost:${random_port} -> VM:22"
        if [ -n "$net_config_extras" ]; then
            echo "Custom network: $net_config_extras"
        fi

        export QEMU_QUICKBOOT_SSH_PORT="$random_port"

        # Resolve script dir for hotplug helper
        SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
        SETTINGS_PANEL="$SCRIPT_DIR/quickboot-settings.sh"

        # Compute desired hotplug window position (upper-right area of screen so
        # it does NOT land on top of the QEMU window, which opens centered).
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

        # Launch QEMU in the background so we can supervise the helper.
        bash -c "$qemu_command" &
        qemu_pid=$!
        export QEMU_PID="$qemu_pid"

        hotplug_pid=""
        hotplug_pgid=""
        if [ "$usb_hotplug_enabled" = "1" ]; then
            # Helper runs in its own process group via setsid; killing the
            # group reaches yad and any descendants when QEMU dies.
            setsid bash -c '
                for i in $(seq 1 15); do
                    [ -S /tmp/qemu-monitor.sock ] && break
                    kill -0 "'"$qemu_pid"'" 2>/dev/null || exit 0
                    sleep 1
                done
                if [ -S /tmp/qemu-monitor.sock ] && kill -0 "'"$qemu_pid"'" 2>/dev/null; then
                    if [ -f "'"$SETTINGS_PANEL"'" ]; then
                        exec bash "'"$SETTINGS_PANEL"'"
                    else
                        yad --error '"$YAD_ICON"' --title="VM Session Settings" --text="quickboot-settings.sh not found at:\n'"$SETTINGS_PANEL"'" --button="OK:0"
                    fi
                fi
            ' </dev/null &
            hotplug_pid=$!
            hotplug_pgid="$hotplug_pid"

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

        wait "$qemu_pid"

        if [ -n "$hotplug_pgid" ]; then
            kill -TERM -- "-$hotplug_pgid" 2>/dev/null
            sleep 0.2
            kill -KILL -- "-$hotplug_pgid" 2>/dev/null
        fi
        rm -f /tmp/qemu-monitor.sock

        # Did the panel ask for a restart with new settings?
        if [ -f /tmp/qemu-quickboot-restart ]; then
            PENDING_NET_CONFIG=""
            # shellcheck disable=SC1091
            source /tmp/qemu-quickboot-restart
            rm -f /tmp/qemu-quickboot-restart
            if [ -n "$PENDING_NET_CONFIG" ]; then
                net_config_extras="$PENDING_NET_CONFIG"
                continue
            fi
        fi

        break
    done

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
    random_port=""
done

# End of script
