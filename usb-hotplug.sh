#!/bin/bash

# USB Hotplug Tool for QEMU-QuickBoot
# Requires: yad, socat
# Usage: Run while a QEMU VM is active

export GTK_THEME=Orchis:dark

SOCK=/tmp/qemu-monitor.sock
MEMFILE=/tmp/hotplug-devices.list
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ICON="$SCRIPT_DIR/QEMU-QuickBoot.png"
YAD_ICON=""
[ -f "$ICON" ] && YAD_ICON="--window-icon=$ICON"
smaller_width=400
smaller_height=250
bigger_width=580

# --- Window positioning ---
# Honors HOTPLUG_POSX / HOTPLUG_POSY from the parent (QEMU-QuickBoot.sh) so
# the hotplug window opens to the side of the VM, not on top of it.
# Falls back to computing an upper-right position if not provided.
if [ -z "$HOTPLUG_POSX" ]; then
    _screen_w=""
    if command -v xdpyinfo &>/dev/null; then
        _screen_w=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {print $2}' | cut -d'x' -f1)
    fi
    [ -z "$_screen_w" ] && _screen_w=1920
    HOTPLUG_POSX=$(( _screen_w - smaller_width - 40 ))
    [ "$HOTPLUG_POSX" -lt 0 ] && HOTPLUG_POSX=40
fi
[ -z "$HOTPLUG_POSY" ] && HOTPLUG_POSY=120
YAD_POS="--posx=$HOTPLUG_POSX --posy=$HOTPLUG_POSY"

# --- Check socket exists ---
if [ ! -S "$SOCK" ]; then
    yad --error $YAD_ICON \
        --title="USB Hotplug" \
        --width="$smaller_width" \
        --text="No QEMU monitor socket found at $SOCK\n\nIs a VM running?" \
        --button="OK:0"
    exit 1
fi

# --- Check socat is available ---
if ! command -v socat &>/dev/null; then
    yad --error $YAD_ICON \
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

# --- Helper: query QEMU monitor and return cleaned output ---
# Socat reads the monitor's banner + prompt + our echoed command + the response
# + another prompt. We strip the framing and return only meaningful lines.
query_monitor() {
    local cmd="$1"
    # -t1 tells socat to wait up to 1s of idle before closing the read side.
    # Without it, socat may close before the monitor has finished printing.
    echo "$cmd" | socat -t1 - UNIX-CONNECT:"$SOCK" 2>/dev/null |
        # Drop banner, prompt lines, echoed command, and blank lines
        sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
            -e '/^QEMU /d' \
            -e '/^(qemu)/d' \
            -e "/^${cmd}\$/d" \
            -e '/^$/d'
}

# The user-mode netdev id that QEMU-QuickBoot.sh launches with (`-netdev user,id=net0`).
# Used as the explicit target for hostfwd_add / hostfwd_remove.
NETDEV_ID="net0"

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
    action=$(yad --list $YAD_ICON $YAD_POS \
        --title="QEMU VM Controls" \
        --width="$smaller_width" --height="$smaller_height" \
        --column="Action" \
        --text="What do you want to do?" \
        --button="Quit:1" --button="OK:0" \
        "Attach USB Device" \
        "Detach USB Device" \
        "Session Device Log" \
        "Network: Info &amp; Port Forwards")

    [ $? -ne 0 ] && exit 0
    action=$(echo "$action" | sed 's/|$//')

    case "$action" in

        "Attach USB Device")
            yad_args=("--list"
                "--title=Select USB Device to Attach"
                "--width=$bigger_width" "--height=$smaller_height"
                "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
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

            yad --info $YAD_ICON \
                --title="USB Hotplug" \
                --width="$smaller_width" \
                --text="[ i ]  Attaching : USB $name" \
                --timeout=5 --timeout-indicator=bottom \
                --no-buttons
            ;;

        "Detach USB Device")
            attached=$(mem_get_attached)

            if [ -z "$attached" ]; then
                yad --info $YAD_ICON \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="No devices in session log.\n\nUse manual entry below." \
                    --button="OK:0"

                dev_id=$(yad --entry $YAD_ICON $YAD_POS \
                    --title="Detach USB Device" \
                    --width="$smaller_width" \
                    --text="Enter the Device ID to detach\n(format: usb_BUS_ADDR  e.g. usb_1_45):" \
                    --entry-text="usb_" \
                    --button="Cancel:1" --button="Detach:0")

                [ $? -ne 0 ] && continue
                dev_id=$(echo "$dev_id" | tr -d ' ')
                send_monitor "device_del ${dev_id}"

                yad --info $YAD_ICON \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="[ i ]  Detaching : USB $dev_id" \
                    --timeout=5 --timeout-indicator=bottom \
                    --no-buttons
            else
                yad_args=("--list"
                    "--title=Select Device to Detach"
                    "--width=$bigger_width" "--height=$smaller_height"
                    "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
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

                yad --info $YAD_ICON \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="[ i ]  Detaching : USB $mem_key" \
                    --timeout=5 --timeout-indicator=bottom \
                    --no-buttons
            fi
            ;;

        "Session Device Log")
            if [ ! -s "$MEMFILE" ]; then
                yad --info $YAD_ICON \
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

            yad --text-info $YAD_ICON $YAD_POS \
                --title="Session Device Log — $MEMFILE" \
                --width="$bigger_width" --height="$smaller_height" \
                --fontname="Monospace 10" \
                --button="Clear Log:2" --button="OK:0" \
                <<< "$display"

            if [ $? -eq 2 ]; then
                > "$MEMFILE"
                yad --info $YAD_ICON \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="Session log cleared." \
                    --button="OK:0"
            fi
            ;;

        "Network: Info &amp; Port Forwards"|"Network: Info & Port Forwards")
            # Inner loop for the network sub-menu so the user can do several
            # operations (view, add, remove) without bouncing back to main.
            while true; do
                net_action=$(yad --list $YAD_ICON $YAD_POS \
                    --title="Network" \
                    --width="$smaller_width" --height="$smaller_height" \
                    --column="Action" \
                    --text="Select an option:" \
                    --button="Back:1" --button="OK:0" \
                    "View Network Info" \
                    "Add Port Forward" \
                    "Add SSH Forward (quick)" \
                    "Remove Port Forward")

                [ $? -ne 0 ] && break
                net_action=$(echo "$net_action" | sed 's/|$//')

                case "$net_action" in

                    "View Network Info")
                        # Pull live forward list from QEMU, plus the static SLIRP
                        # defaults (guest IP/gateway/DNS are baked in at launch).
                        usernet_raw=$(query_monitor "info usernet")
                        # Extract only HOST_FORWARD lines and format them.
                        # QEMU prints host-address column empty when binding to all
                        # interfaces, which shifts column positions — so we parse
                        # from the END of each line (always g_addr g_port rq sq)
                        # and only treat the field before h_port as an address if
                        # it contains a dot.
                        forwards=$(echo "$usernet_raw" | awk '
                            /HOST_FORWARD/ {
                                proto=$1; sub(/\[.*/,"",proto)
                                g_port=$(NF-2); g_addr=$(NF-3); h_port=$(NF-4)
                                prev=$(NF-5)
                                if (prev ~ /\./) h_addr=prev; else h_addr="0.0.0.0"
                                if (g_addr=="") g_addr="10.0.2.15"
                                printf "  %-4s  %s:%-5s  ->  %s:%s\n", proto, h_addr, h_port, g_addr, g_port
                            }
                        ')
                        [ -z "$forwards" ] && forwards="  (none)"

                        info_text="SLIRP user-mode network defaults:

  Guest IP       : 10.0.2.15
  Gateway / Host : 10.0.2.2
  DNS            : 10.0.2.3
  DHCP range     : 10.0.2.15 – 10.0.2.31

Active host port forwards (host -> guest):

${forwards}

Raw 'info usernet' output:
${usernet_raw:-  (no response from QEMU monitor)}"

                        yad --text-info $YAD_ICON $YAD_POS \
                            --title="Network Info" \
                            --width="$bigger_width" --height="350" \
                            --fontname="Monospace 10" \
                            --button="OK:0" \
                            <<< "$info_text"
                        ;;

                    "Add Port Forward"|"Add SSH Forward (quick)")
                        # Pre-fill the form with SSH defaults for the quick path.
                        default_gport=22
                        default_hport=2222
                        if [ "$net_action" = "Add Port Forward" ]; then
                            default_gport=80
                            default_hport=8080
                        fi

                        form_result=$(yad --form $YAD_ICON $YAD_POS \
                            --title="Add Port Forward" \
                            --width="$smaller_width" --height="$smaller_height" \
                            --text="Redirect a host port to a guest port." \
                            --separator="|" \
                            --field="Protocol:CB" "tcp!udp" \
                            --field="Host port:NUM" "${default_hport}!1..65535!1!0" \
                            --field="Guest port:NUM" "${default_gport}!1..65535!1!0" \
                            --button="Cancel:1" --button="Add:0")

                        [ $? -ne 0 ] && continue

                        proto=$(echo "$form_result" | cut -d'|' -f1)
                        h_port=$(echo "$form_result" | cut -d'|' -f2 | cut -d. -f1)
                        g_port=$(echo "$form_result" | cut -d'|' -f3 | cut -d. -f1)

                        if ! [[ "$h_port" =~ ^[0-9]+$ ]] || ! [[ "$g_port" =~ ^[0-9]+$ ]]; then
                            yad --error $YAD_ICON $YAD_POS \
                                --title="Invalid Input" \
                                --width="$smaller_width" \
                                --text="Host and guest ports must be numeric." \
                                --button="OK:0"
                            continue
                        fi

                        # hostfwd_add NETDEV_ID tcp::HOSTPORT-:GUESTPORT
                        fwd_spec="${proto}::${h_port}-:${g_port}"
                        add_result=$(query_monitor "hostfwd_add ${NETDEV_ID} ${fwd_spec}")

                        # QEMU prints nothing on success, an error line on failure.
                        if [ -n "$add_result" ]; then
                            yad --error $YAD_ICON $YAD_POS \
                                --title="Port Forward Failed" \
                                --width="$bigger_width" \
                                --text="QEMU rejected the forward:\n\n${add_result}" \
                                --button="OK:0"
                        else
                            yad --info $YAD_ICON $YAD_POS \
                                --title="Port Forward Added" \
                                --width="$smaller_width" \
                                --text="[ + ]  ${proto^^}  host:${h_port}  ->  guest:${g_port}" \
                                --timeout=4 --timeout-indicator=bottom \
                                --no-buttons
                        fi
                        ;;

                    "Remove Port Forward")
                        usernet_raw=$(query_monitor "info usernet")
                        # Build a yad_args array of {proto, host:port, guest:port} rows.
                        yad_args=("--list"
                            "--title=Remove Port Forward"
                            "--width=$bigger_width" "--height=$smaller_height"
                            "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                            "--column=Protocol" "--column=Host" "--column=Guest" "--column=Spec"
                            "--text=Select a forward to remove:"
                            "--button=Cancel:1" "--button=Remove:0")

                        row_count=0
                        while IFS= read -r line; do
                            [[ "$line" != *"HOST_FORWARD"* ]] && continue
                            # Same back-of-line parsing as the View action.
                            proto=$(echo "$line" | awk '{print $1}' | sed 's/\[.*//')
                            g_port=$(echo "$line" | awk '{print $(NF-2)}')
                            g_addr=$(echo "$line" | awk '{print $(NF-3)}')
                            h_port=$(echo "$line" | awk '{print $(NF-4)}')
                            prev=$(echo "$line" | awk '{print $(NF-5)}')
                            if [[ "$prev" == *.* ]]; then h_addr="$prev"; else h_addr=""; fi
                            [ -z "$h_port" ] || [ -z "$g_port" ] && continue
                            # Spec matches what hostfwd_remove expects
                            proto_lc="${proto,,}"
                            spec="${proto_lc}:${h_addr}:${h_port}-:${g_port}"
                            yad_args+=("$proto_lc" "${h_addr:-0.0.0.0}:${h_port}" "${g_addr:-10.0.2.15}:${g_port}" "$spec")
                            row_count=$((row_count + 1))
                        done <<< "$usernet_raw"

                        if [ "$row_count" -eq 0 ]; then
                            yad --info $YAD_ICON $YAD_POS \
                                --title="Remove Port Forward" \
                                --width="$smaller_width" \
                                --text="No host port forwards are currently active." \
                                --button="OK:0"
                            continue
                        fi

                        selected=$(yad "${yad_args[@]}")
                        [ $? -ne 0 ] && continue

                        spec=$(echo "$selected" | cut -d'|' -f4)
                        rm_result=$(query_monitor "hostfwd_remove ${NETDEV_ID} ${spec}")

                        if [ -n "$rm_result" ] && [[ "$rm_result" != *"removed"* ]]; then
                            yad --error $YAD_ICON $YAD_POS \
                                --title="Remove Failed" \
                                --width="$bigger_width" \
                                --text="QEMU rejected the removal:\n\n${rm_result}" \
                                --button="OK:0"
                        else
                            yad --info $YAD_ICON $YAD_POS \
                                --title="Port Forward Removed" \
                                --width="$smaller_width" \
                                --text="[ - ]  ${spec}" \
                                --timeout=4 --timeout-indicator=bottom \
                                --no-buttons
                        fi
                        ;;
                esac
            done
            ;;
    esac
done
