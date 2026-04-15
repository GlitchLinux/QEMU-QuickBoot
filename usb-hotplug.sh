#!/bin/bash

# USB Hotplug Tool for QEMU-QuickBoot
# Requires: yad, socat
# Usage: Run while a QEMU VM is active

export GTK_THEME=Orchis:dark

SOCK=/tmp/qemu-monitor.sock
MEMFILE=/tmp/hotplug-devices.list
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

# --- Init memory file ---
touch "$MEMFILE"

# --- Helper: send command to QEMU monitor ---
send_monitor() {
    echo "$1" | socat - UNIX-CONNECT:"$SOCK" &>/dev/null
}

# --- Helper: sanitize device name for memory file key ---
sanitize_name() {
    echo "$1" | tr -s ' ' | tr ' ' '_' | tr -cd '[:alnum:]_'
}

# --- Helper: write to memory file ---
# Format: [BUS.ADDR_(DeviceName)]  STATE  dev_id
# STATE: 1=attached, 0=detached
mem_write() {
    local key="$1"
    local state="$2"
    local dev_id="$3"
    # Remove existing entry for this key
    grep -v "^\[${key}\]" "$MEMFILE" > "${MEMFILE}.tmp" 2>/dev/null && mv "${MEMFILE}.tmp" "$MEMFILE"
    # Append updated entry
    echo "[${key}]  ${state}  ${dev_id}" >> "$MEMFILE"
}

# --- Helper: get currently attached devices from memory file ---
mem_get_attached() {
    grep "  1  " "$MEMFILE" 2>/dev/null
}

while true; do
    action=$(yad --list \
        --title="QEMU USB Hotplug" \
        --width="$smaller_width" --height="$smaller_height" \
        --column="Action" \
        --text="What do you want to do?" \
        --button="Quit:1" --button="OK:0" \
        "Attach USB Device" \
        "Detach USB Device" \
        "Session Device Log")

    [ $? -ne 0 ] && exit 0
    action=$(echo "$action" | sed 's/|$//')

    case "$action" in

        "Attach USB Device")
            yad_args=("--list"
                "--title=Select USB Device to Attach"
                "--width=$bigger_width" "--height=$smaller_height"
                "--column=Bus" "--column=Device" "--column=ID" "--column=Name"
                "--text=Select a USB device to attach to the VM:"
                "--button=Cancel:1" "--button=Attach:0")

            while IFS= read -r line; do
                [[ "$line" == *"Linux Foundation"* ]] && continue
                bus=$(echo "$line" | grep -oP 'Bus \K[0-9]+')
                addr=$(echo "$line" | grep -oP 'Device \K[0-9]+')
                id=$(echo "$line" | grep -oP 'ID \K[0-9a-f]{4}:[0-9a-f]{4}')
                name=$(echo "$line" | sed 's/.*ID [0-9a-f:]*  *//')
                [ -n "$bus" ] && yad_args+=("$bus" "$addr" "$id" "$name")
            done <<< "$(lsusb)"

            selected=$(yad "${yad_args[@]}")
            [ $? -ne 0 ] && continue

            # Strip trailing pipes, strip leading zeros from bus/addr
            bus=$(echo "$selected" | cut -d'|' -f1 | sed 's/|//g' | sed 's/^0*//')
            addr=$(echo "$selected" | cut -d'|' -f2 | sed 's/|//g' | sed 's/^0*//')
            name=$(echo "$selected" | cut -d'|' -f4 | sed 's/|//g')

            dev_id="usb_${bus}_${addr}"
            short_name=$(sanitize_name "$name")
            mem_key="${bus}.${addr}_(${short_name})"

            attach_cmd="device_add usb-host,hostbus=${bus},hostaddr=${addr},id=${dev_id}"
            detach_cmd="device_del ${dev_id}"

            # Auto-attach via monitor socket
            send_monitor "$attach_cmd"
            mem_write "$mem_key" "1" "$dev_id"

            yad --info \
                --title="USB Hotplug" \
                --width="$smaller_width" \
                --text="[ i ]  Attaching : USB $name" \
                --timeout=5 --timeout-indicator=bottom \
                --no-buttons
            ;;

        "Detach USB Device")
            attached=$(mem_get_attached)

            if [ -z "$attached" ]; then
                yad --info \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="No devices in session log.\n\nUse manual entry below." \
                    --button="OK:0"

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
                    --text="[ i ]  Detaching : USB $dev_id" \
                    --timeout=5 --timeout-indicator=bottom \
                    --no-buttons
            else
                yad_args=("--list"
                    "--title=Select Device to Detach"
                    "--width=$bigger_width" "--height=$smaller_height"
                    "--column=Device" "--column=ID"
                    "--text=Select a device to detach from the VM:"
                    "--button=Cancel:1" "--button=Detach:0")

                while IFS= read -r line; do
                    key=$(echo "$line" | grep -oP '^\[\K[^\]]+')
                    did=$(echo "$line" | awk '{print $3}')
                    yad_args+=("$key" "$did")
                done <<< "$attached"

                selected=$(yad "${yad_args[@]}")
                [ $? -ne 0 ] && continue

                mem_key=$(echo "$selected" | cut -d'|' -f1)
                dev_id=$(echo "$selected" | cut -d'|' -f2)

                send_monitor "device_del ${dev_id}"
                mem_write "$mem_key" "0" "$dev_id"

                yad --info \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="[ i ]  Detaching : USB $mem_key" \
                    --timeout=5 --timeout-indicator=bottom \
                    --no-buttons
            fi
            ;;

        "Session Device Log")
            if [ ! -s "$MEMFILE" ]; then
                yad --info \
                    --title="Session Device Log" \
                    --width="$smaller_width" \
                    --text="No devices logged this session yet." \
                    --button="OK:0"
                continue
            fi

            display=$(awk '{
                key=$1; state=$2; did=$3
                status=(state=="1") ? "ATTACHED" : "detached"
                printf "%-42s  %-10s  %s\n", key, status, did
            }' "$MEMFILE")

            yad --text-info \
                --title="Session Device Log — $MEMFILE" \
                --width="$bigger_width" --height="$smaller_height" \
                --fontname="Monospace 10" \
                --button="Clear Log:2" --button="OK:0" \
                <<< "$display"

            if [ $? -eq 2 ]; then
                > "$MEMFILE"
                yad --info \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="Session log cleared." \
                    --button="OK:0"
            fi
            ;;
    esac
done
