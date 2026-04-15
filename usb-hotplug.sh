#!/bin/bash

# USB Hotplug Tool for QEMU-QuickBoot
# Requires: yad, socat
# Usage: Run while a QEMU VM is active

export GTK_THEME=Orchis:dark

SOCK=/tmp/qemu-monitor.sock
smaller_width=400
smaller_height=250
bigger_width=580

# --- Check socket exists ---
if [ ! -S "$SOCK" ]; then
    yad --error \
        --title="USB Hotplug" \
        --width="$smaller_width" \
        --text="No QEMU monitor socket found at $SOCK\n\nIs a VM running?" \
        --button="OK:0"
    exit 1
fi

# --- Check socat is available ---
if ! command -v socat &>/dev/null; then
    yad --error \
        --title="USB Hotplug" \
        --width="$smaller_width" \
        --text="socat is not installed.\n\nInstall it with:\nsudo apt install socat" \
        --button="OK:0"
    exit 1
fi

send_monitor() {
    echo "$1" | socat - UNIX-CONNECT:"$SOCK" &>/dev/null
}

while true; do
    # --- Action selection ---
    action=$(yad --list \
        --title="QEMU USB Hotplug" \
        --width="$smaller_width" --height="$smaller_height" \
        --column="Action" \
        --text="What do you want to do?" \
        --button="Quit:1" --button="OK:0" \
        "Attach USB Device" \
        "Detach USB Device" \
        "List Attached Devices")

    [ $? -ne 0 ] && exit 0
    action=$(echo "$action" | sed 's/|$//')

    case "$action" in

        "Attach USB Device")
            # Build device list from lsusb, skip root hubs
            yad_args=("--list"
                "--title=Select USB Device to Attach"
                "--width=$bigger_width" "--height=$smaller_height"
                "--column=Bus" "--column=Device" "--column=ID" "--column=Name"
                "--text=Select a USB device to attach to the VM:"
                "--button=Cancel:1" "--button=Attach:0")

            while IFS= read -r line; do
                # Skip Linux root hubs
                [[ "$line" == *"Linux Foundation"* ]] && continue
                bus=$(echo "$line" | grep -oP 'Bus \K[0-9]+')
                addr=$(echo "$line" | grep -oP 'Device \K[0-9]+')
                id=$(echo "$line" | grep -oP 'ID \K[0-9a-f]{4}:[0-9a-f]{4}')
                name=$(echo "$line" | sed 's/.*ID [0-9a-f:]*  *//')
                [ -n "$bus" ] && yad_args+=("$bus" "$addr" "$id" "$name")
            done <<< "$(lsusb)"

            selected=$(yad "${yad_args[@]}")
            [ $? -ne 0 ] && continue

            bus=$(echo "$selected" | cut -d'|' -f1)
            addr=$(echo "$selected" | cut -d'|' -f2)
            name=$(echo "$selected" | cut -d'|' -f4)

            # Generate unique ID from bus+addr
            dev_id="usb_${bus}_${addr}"

            attach_cmd="device_add usb-host,hostbus=${bus},hostaddr=${addr},id=${dev_id}"
            detach_cmd="device_del ${dev_id}"

            # Ask: auto-attach or show command?
            mode=$(yad --list \
                --title="Attach Method" \
                --width="$smaller_width" --height="$smaller_height" \
                --column="Method" \
                --text="How do you want to attach <b>$name</b>?" \
                --button="Cancel:1" --button="OK:0" \
                "Auto-attach (send to VM now)" \
                "Show command (copy/paste into terminal)")

            [ $? -ne 0 ] && continue
            mode=$(echo "$mode" | sed 's/|$//')

            if [ "$mode" == "Auto-attach (send to VM now)" ]; then
                send_monitor "$attach_cmd"
                yad --info \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="✔ Attached: $name\n\nDevice ID: <b>$dev_id</b>\nUse this ID to detach later." \
                    --button="OK:0"
            else
                yad --form \
                    --title="USB Hotplug Commands" \
                    --width="$bigger_width" \
                    --text="Paste into your QEMU monitor terminal:\n" \
                    --field="Attach:":RO "$attach_cmd" \
                    --field="Detach:":RO "$detach_cmd" \
                    --button="Close:0"
            fi
            ;;

        "Detach USB Device")
            # Ask for the device ID to remove
            dev_id=$(yad --entry \
                --title="Detach USB Device" \
                --width="$smaller_width" \
                --text="Enter the Device ID to detach\n(format: usb_BUS_ADDR  e.g. usb_1_45):" \
                --entry-text="usb_" \
                --button="Cancel:1" --button="Detach:0")

            [ $? -ne 0 ] && continue
            dev_id=$(echo "$dev_id" | tr -d ' ')

            send_monitor "device_del ${dev_id}"

            yad --info \
                --title="USB Hotplug" \
                --width="$smaller_width" \
                --text="✔ Detach command sent for: <b>$dev_id</b>" \
                --button="OK:0"
            ;;

        "List Attached Devices")
            # Query monitor for attached USB devices
            result=$(echo "info usb" | socat - UNIX-CONNECT:"$SOCK" 2>/dev/null | grep -v "^QEMU\|^$")

            [ -z "$result" ] && result="No USB devices currently attached to VM."

            yad --text-info \
                --title="Attached USB Devices" \
                --width="$bigger_width" --height="$smaller_height" \
                --fontname="Monospace 10" \
                --button="OK:0" \
                <<< "$result"
            ;;
    esac
done
