#!/bin/bash

# QuickBoot Settings — VM Session Settings panel for QEMU-QuickBoot
# Requires: yad, socat
# Usage: launches automatically when qemu-quickboot.sh starts a VM with USB enabled.
#        Can also be run manually while a VM is active.
#        Companion to: qemu-quickboot.sh
#
# 2026 restructure:
#   * Window title is now "VM Session Settings"
#   * Top-level menu grouped: USB Devices / Network / Storage / VM Power
#   * Network sub-menu: smart SSH forward, view, add, remove, IPv4 config
#   * IPv4 reconfig requests a VM restart via /tmp/qemu-quickboot-restart;
#     the parent script picks it up and re-launches QEMU with the new netdev.
#   * VM Power sub-menu: reboot / shutdown / force-quit via HMP

export GTK_THEME=Orchis:dark

SOCK=/tmp/qemu-monitor.sock
MEMFILE=/tmp/hotplug-devices.list
RESTART_FILE=/tmp/qemu-quickboot-restart
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ICON="$SCRIPT_DIR/QEMU-QuickBoot.png"
YAD_ICON=""
[ -f "$ICON" ] && YAD_ICON="--window-icon=$ICON"
smaller_width=380
smaller_height=300
bigger_width=480

# --- Window positioning ---
# Honors HOTPLUG_POSX / HOTPLUG_POSY from the parent (qemu-quickboot.sh) so
# the panel opens to the side of the VM, not on top of it.
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

# --- Sanity checks ---
if [ ! -S "$SOCK" ]; then
    yad --error $YAD_ICON \
        --title="VM Session Settings" \
        --width="$smaller_width" \
        --text="No QEMU monitor socket found at $SOCK\n\nIs a VM running?" \
        --button="OK:0"
    exit 1
fi

if ! command -v socat &>/dev/null; then
    yad --error $YAD_ICON \
        --title="VM Session Settings" \
        --width="$smaller_width" \
        --text="socat is not installed.\n\nInstall it with:\nsudo apt install socat" \
        --button="OK:0"
    exit 1
fi

touch "$MEMFILE"

# --- Helper: send command to QEMU monitor (fire-and-forget) ---
send_monitor() {
    echo "$1" | socat - UNIX-CONNECT:"$SOCK" &>/dev/null
}

# --- Helper: query QEMU monitor and return cleaned output ---
# Strips banner, prompt, echoed command, and ANSI sequences.
query_monitor() {
    local cmd="$1"
    echo "$cmd" | socat -t1 - UNIX-CONNECT:"$SOCK" 2>/dev/null |
        sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
            -e '/^QEMU /d' \
            -e '/^(qemu)/d' \
            -e "/^${cmd}\$/d" \
            -e '/^$/d'
}

# The user-mode netdev id that QEMU-QuickBoot launches with.
NETDEV_ID="net0"

# --- Helpers: USB session log (memory file) ---
sanitize_name() {
    echo "$1" | tr -s ' ' | tr ' ' '_' | tr -cd '[:alnum:]_'
}

# Format: [BUS.ADDR_(DeviceName)]  STATE  dev_id   (STATE: 1=attached, 0=detached)
mem_write() {
    local key="$1"
    local state="$2"
    local dev_id="$3"
    grep -v "^\[${key}\]" "$MEMFILE" > "${MEMFILE}.tmp" 2>/dev/null || true
    mv "${MEMFILE}.tmp" "$MEMFILE" 2>/dev/null || true
    echo "[${key}]  ${state}  ${dev_id}" >> "$MEMFILE"
}

mem_get_attached() {
    grep "  1  " "$MEMFILE" 2>/dev/null
}

# --- Storage state file (separate from USB memfile) ---
STORAGE_FILE=/tmp/vm-storage-devices.list
touch "$STORAGE_FILE"

storage_next_id() {
    local max=0 n
    while IFS='|' read -r id _ _ _; do
        n=$(echo "$id" | sed 's/^storage_//')
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$max" ] && max="$n"
    done < "$STORAGE_FILE"
    echo "storage_$((max + 1))"
}

storage_record() {
    echo "$1|$2|$3|$4" >> "$STORAGE_FILE"
}

storage_forget() {
    local id="$1"
    grep -v "^${id}|" "$STORAGE_FILE" > "${STORAGE_FILE}.tmp" 2>/dev/null || true
    mv "${STORAGE_FILE}.tmp" "$STORAGE_FILE" 2>/dev/null || true
}

storage_format_from_path() {
    local path="$1"
    local ext="${path##*.}"
    case "${ext,,}" in
        qcow2|qcow)  echo "qcow2" ;;
        vhdx)        echo "vhdx" ;;
        vhd|vpc)     echo "vpc" ;;
        vmdk)        echo "vmdk" ;;
        vdi)         echo "vdi" ;;
        *)           echo "raw" ;;
    esac
}

# --- Helper: copy text to clipboard if any clipboard tool is available ---
copy_to_clipboard() {
    local text="$1"
    if command -v wl-copy &>/dev/null; then
        echo -n "$text" | wl-copy 2>/dev/null && return 0
    fi
    if command -v xclip &>/dev/null; then
        echo -n "$text" | xclip -selection clipboard 2>/dev/null && return 0
    fi
    if command -v xsel &>/dev/null; then
        echo -n "$text" | xsel -ib 2>/dev/null && return 0
    fi
    return 1
}

# =============================================================================
# USB DEVICES SUB-MENU
# =============================================================================
usb_submenu() {
    while true; do
        local action
        action=$(yad --list $YAD_ICON $YAD_POS \
            --title="USB Devices" \
            --width="$smaller_width" --height="$smaller_height" \
            --column="Action" \
            --text="USB hotplug controls:" \
            --button="Back:1" --button="OK:0" \
            "Attach USB Device" \
            "Detach USB Device" \
            "Session Device Log")

        [ $? -ne 0 ] && return 0
        action=$(echo "$action" | sed 's/|$//')

        case "$action" in

            "Attach USB Device")
                local yad_args=("--list"
                    "--title=Select USB Device to Attach"
                    "--width=$bigger_width" "--height=$smaller_height"
                    "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                    "--column=Bus" "--column=Device" "--column=ID" "--column=Name"
                    "--text=Select a USB device to attach to the VM:"
                    "--button=Cancel:1" "--button=Attach:0")

                while IFS= read -r line; do
                    [[ "$line" == *"Linux Foundation"* ]] && continue
                    local bus addr id name
                    bus=$(echo "$line" | grep -oP 'Bus \K[0-9]+')
                    addr=$(echo "$line" | grep -oP 'Device \K[0-9]+')
                    id=$(echo "$line" | grep -oP 'ID \K[0-9a-f]{4}:[0-9a-f]{4}')
                    name=$(echo "$line" | sed 's/.*ID [0-9a-f:]*  *//')
                    [ -n "$bus" ] && yad_args+=("$bus" "$addr" "$id" "$name")
                done <<< "$(lsusb)"

                local selected
                selected=$(yad "${yad_args[@]}")
                [ $? -ne 0 ] && continue

                local bus addr name dev_id short_name mem_key attach_cmd
                bus=$(echo "$selected" | cut -d'|' -f1 | sed 's/|//g' | sed 's/^0*//')
                addr=$(echo "$selected" | cut -d'|' -f2 | sed 's/|//g' | sed 's/^0*//')
                name=$(echo "$selected" | cut -d'|' -f4 | sed 's/|//g')

                dev_id="usb_${bus}_${addr}"
                short_name=$(sanitize_name "$name")
                mem_key="${bus}.${addr}_(${short_name})"
                attach_cmd="device_add usb-host,hostbus=${bus},hostaddr=${addr},id=${dev_id}"

                send_monitor "$attach_cmd"
                mem_write "$mem_key" "1" "$dev_id"

                yad --info $YAD_ICON $YAD_POS \
                    --title="USB Hotplug" \
                    --width="$smaller_width" \
                    --text="[ + ]  Attached : USB $name" \
                    --timeout=4 --timeout-indicator=bottom \
                    --no-buttons
                ;;

            "Detach USB Device")
                local attached
                attached=$(mem_get_attached)

                if [ -z "$attached" ]; then
                    yad --info $YAD_ICON $YAD_POS \
                        --title="USB Hotplug" \
                        --width="$smaller_width" \
                        --text="No devices in session log.\n\nUse manual entry below." \
                        --button="OK:0"

                    local dev_id
                    dev_id=$(yad --entry $YAD_ICON $YAD_POS \
                        --title="Detach USB Device" \
                        --width="$smaller_width" \
                        --text="Enter the Device ID to detach\n(format: usb_BUS_ADDR  e.g. usb_1_45):" \
                        --entry-text="usb_" \
                        --button="Cancel:1" --button="Detach:0")

                    [ $? -ne 0 ] && continue
                    dev_id=$(echo "$dev_id" | tr -d ' ')
                    send_monitor "device_del ${dev_id}"

                    yad --info $YAD_ICON $YAD_POS \
                        --title="USB Hotplug" \
                        --width="$smaller_width" \
                        --text="[ - ]  Detached : USB $dev_id" \
                        --timeout=4 --timeout-indicator=bottom \
                        --no-buttons
                else
                    local yad_args=("--list"
                        "--title=Select Device to Detach"
                        "--width=$bigger_width" "--height=$smaller_height"
                        "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                        "--column=Device" "--column=ID"
                        "--text=Select a device to detach from the VM:"
                        "--button=Cancel:1" "--button=Detach:0")

                    while IFS= read -r line; do
                        local key did
                        key=$(echo "$line" | grep -oP '^\[\K[^\]]+')
                        did=$(echo "$line" | awk '{print $3}')
                        yad_args+=("$key" "$did")
                    done <<< "$attached"

                    local selected
                    selected=$(yad "${yad_args[@]}")
                    [ $? -ne 0 ] && continue

                    local mem_key dev_id
                    mem_key=$(echo "$selected" | cut -d'|' -f1)
                    dev_id=$(echo "$selected" | cut -d'|' -f2)

                    send_monitor "device_del ${dev_id}"
                    mem_write "$mem_key" "0" "$dev_id"

                    yad --info $YAD_ICON $YAD_POS \
                        --title="USB Hotplug" \
                        --width="$smaller_width" \
                        --text="[ - ]  Detached : USB $mem_key" \
                        --timeout=4 --timeout-indicator=bottom \
                        --no-buttons
                fi
                ;;

            "Session Device Log")
                if [ ! -s "$MEMFILE" ]; then
                    yad --info $YAD_ICON $YAD_POS \
                        --title="Session Device Log" \
                        --width="$smaller_width" \
                        --text="No devices logged this session yet." \
                        --button="OK:0"
                    continue
                fi

                local display
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
                    yad --info $YAD_ICON $YAD_POS \
                        --title="USB Hotplug" \
                        --width="$smaller_width" \
                        --text="Session log cleared." \
                        --timeout=2 --timeout-indicator=bottom \
                        --no-buttons
                fi
                ;;
        esac
    done
}

# =============================================================================
# NETWORK SUB-MENU
# =============================================================================
network_submenu() {
    while true; do
        # Pull current SSH forward port from env (set by parent) for the menu label.
        local current_ssh_port="${QEMU_QUICKBOOT_SSH_PORT:-?}"

        local action
        action=$(yad --list $YAD_ICON $YAD_POS \
            --title="Network" \
            --width="$smaller_width" --height="$smaller_height" \
            --column="Action" \
            --text="Network configuration. SSH host port: ${current_ssh_port}" \
            --button="Back:1" --button="OK:0" \
            "View Network Info" \
            "SSH Quick-Forward..." \
            "Add Port Forward" \
            "Remove Port Forward" \
            "IPv4 / Subnet Config (restart required)")

        [ $? -ne 0 ] && return 0
        action=$(echo "$action" | sed 's/|$//')

        case "$action" in

            "View Network Info")
                local usernet_raw forwards info_text
                usernet_raw=$(query_monitor "info usernet")
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
                    --width="$bigger_width" --height="380" \
                    --fontname="Monospace 10" \
                    --button="OK:0" \
                    <<< "$info_text"
                ;;

            "SSH Quick-Forward...")
                # Show current SSH forward, let user copy ssh command, or change host port.
                local ssh_action ssh_user
                ssh_user="${USER:-root}"

                ssh_action=$(yad --list $YAD_ICON $YAD_POS \
                    --title="SSH Quick-Forward" \
                    --width="$smaller_width" --height="$smaller_height" \
                    --column="Action" \
                    --text="Current SSH forward: localhost:${current_ssh_port} -> guest:22" \
                    --button="Back:1" --button="OK:0" \
                    "Copy ssh command to clipboard" \
                    "Show ssh command" \
                    "Change host SSH port")

                [ $? -ne 0 ] && continue
                ssh_action=$(echo "$ssh_action" | sed 's/|$//')

                case "$ssh_action" in

                    "Copy ssh command to clipboard")
                        local ssh_cmd="ssh -p ${current_ssh_port} ${ssh_user}@localhost"
                        if copy_to_clipboard "$ssh_cmd"; then
                            yad --info $YAD_ICON $YAD_POS \
                                --title="Copied" \
                                --width="$bigger_width" \
                                --text="Copied to clipboard:\n\n  ${ssh_cmd}" \
                                --timeout=4 --timeout-indicator=bottom \
                                --no-buttons
                        else
                            yad --info $YAD_ICON $YAD_POS \
                                --title="No clipboard tool" \
                                --width="$bigger_width" \
                                --text="No clipboard tool available (xclip / wl-copy / xsel).\n\nManual copy:\n  ${ssh_cmd}" \
                                --button="OK:0"
                        fi
                        ;;

                    "Show ssh command")
                        yad --info $YAD_ICON $YAD_POS \
                            --title="SSH Command" \
                            --width="$bigger_width" \
                            --text="ssh -p ${current_ssh_port} ${ssh_user}@localhost\n\n(Replace '${ssh_user}' with the guest username if different.)" \
                            --button="OK:0"
                        ;;

                    "Change host SSH port")
                        local new_port_form new_port_in
                        new_port_form=$(yad --form $YAD_ICON $YAD_POS \
                            --title="Change SSH Host Port" \
                            --width="$smaller_width" --height="$smaller_height" \
                            --text="Add a NEW host port forwarding to guest:22.\n(The old forward will remain unless removed.)" \
                            --separator="|" \
                            --field="New host port:NUM" "2222!1..65535!1!0" \
                            --button="Cancel:1" --button="Add:0")

                        [ $? -ne 0 ] && continue
                        new_port_in=$(echo "$new_port_form" | cut -d'|' -f1 | cut -d. -f1)

                        if ! [[ "$new_port_in" =~ ^[0-9]+$ ]]; then
                            yad --error $YAD_ICON $YAD_POS \
                                --title="Invalid Input" \
                                --width="$smaller_width" \
                                --text="Host port must be numeric." \
                                --button="OK:0"
                            continue
                        fi

                        local fwd_spec="tcp::${new_port_in}-:22"
                        local add_result
                        add_result=$(query_monitor "hostfwd_add ${NETDEV_ID} ${fwd_spec}")

                        if [ -n "$add_result" ]; then
                            yad --error $YAD_ICON $YAD_POS \
                                --title="SSH Forward Failed" \
                                --width="$bigger_width" \
                                --text="QEMU rejected the forward:\n\n${add_result}" \
                                --button="OK:0"
                        else
                            yad --info $YAD_ICON $YAD_POS \
                                --title="SSH Forward Added" \
                                --width="$bigger_width" \
                                --text="[ + ]  ssh -p ${new_port_in} ${ssh_user}@localhost" \
                                --timeout=5 --timeout-indicator=bottom \
                                --no-buttons
                        fi
                        ;;
                esac
                ;;

            "Add Port Forward")
                local form_result proto h_port g_port
                form_result=$(yad --form $YAD_ICON $YAD_POS \
                    --title="Add Port Forward" \
                    --width="$smaller_width" --height="$smaller_height" \
                    --text="Redirect a host port to a guest port." \
                    --separator="|" \
                    --field="Protocol:CB" "tcp!udp" \
                    --field="Host port:NUM" "8080!1..65535!1!0" \
                    --field="Guest port:NUM" "80!1..65535!1!0" \
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

                local fwd_spec="${proto}::${h_port}-:${g_port}"
                local add_result
                add_result=$(query_monitor "hostfwd_add ${NETDEV_ID} ${fwd_spec}")

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
                local usernet_raw
                usernet_raw=$(query_monitor "info usernet")
                local yad_args=("--list"
                    "--title=Remove Port Forward"
                    "--width=$bigger_width" "--height=$smaller_height"
                    "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                    "--column=Protocol" "--column=Host" "--column=Guest" "--column=Spec"
                    "--text=Select a forward to remove:"
                    "--button=Cancel:1" "--button=Remove:0")

                local row_count=0
                while IFS= read -r line; do
                    [[ "$line" != *"HOST_FORWARD"* ]] && continue
                    local proto g_port g_addr h_port prev h_addr proto_lc spec
                    proto=$(echo "$line" | awk '{print $1}' | sed 's/\[.*//')
                    g_port=$(echo "$line" | awk '{print $(NF-2)}')
                    g_addr=$(echo "$line" | awk '{print $(NF-3)}')
                    h_port=$(echo "$line" | awk '{print $(NF-4)}')
                    prev=$(echo "$line" | awk '{print $(NF-5)}')
                    if [[ "$prev" == *.* ]]; then h_addr="$prev"; else h_addr=""; fi
                    [ -z "$h_port" ] || [ -z "$g_port" ] && continue
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

                local selected
                selected=$(yad "${yad_args[@]}")
                [ $? -ne 0 ] && continue

                local spec rm_result
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

            "IPv4 / Subnet Config (restart required)")
                ipv4_config_dialog
                ;;
        esac
    done
}

# --- IPv4/subnet reconfig dialog ---
# QEMU's user-mode -netdev parameters cannot be changed on a live VM, so we
# write the desired override to a state file and ask the parent to restart.
ipv4_config_dialog() {
    local form_result proceed_choice
    form_result=$(yad --form $YAD_ICON $YAD_POS \
        --title="IPv4 / Subnet Configuration" \
        --width="$bigger_width" --height="320" \
        --text="Override the SLIRP user-mode subnet for this VM.

Defaults if left blank:
  Network    10.0.2.0/24
  Gateway    10.0.2.2
  Guest IP   10.0.2.15
  DNS        10.0.2.3

Applying these settings requires the VM to restart with the same drives,
boot mode, and SSH forward port — only the network changes." \
        --separator="|" \
        --field="Network (CIDR):" "10.0.2.0/24" \
        --field="Gateway / host IP:" "10.0.2.2" \
        --field="DHCP start (guest IP):" "10.0.2.15" \
        --field="DNS server:" "10.0.2.3" \
        --button="Cancel:1" --button="Save (no restart):2" --button="Save & Restart Now:0")

    local rc=$?
    [ "$rc" = "1" ] && return 0

    local net_cidr gw dhcp dns
    net_cidr=$(echo "$form_result" | cut -d'|' -f1)
    gw=$(echo "$form_result" | cut -d'|' -f2)
    dhcp=$(echo "$form_result" | cut -d'|' -f3)
    dns=$(echo "$form_result" | cut -d'|' -f4)

    # Build the QEMU netdev fragment. Empty fields are omitted so SLIRP picks defaults.
    local frag=""
    [ -n "$net_cidr" ] && frag="${frag}net=${net_cidr},"
    [ -n "$gw" ]       && frag="${frag}host=${gw},"
    [ -n "$dhcp" ]     && frag="${frag}dhcpstart=${dhcp},"
    [ -n "$dns" ]      && frag="${frag}dns=${dns},"
    frag="${frag%,}"  # strip trailing comma

    if [ -z "$frag" ]; then
        yad --info $YAD_ICON $YAD_POS \
            --title="No changes" \
            --width="$smaller_width" \
            --text="All fields blank — using SLIRP defaults.\n\nNo restart needed." \
            --timeout=3 --timeout-indicator=bottom \
            --no-buttons
        return 0
    fi

    # Write to restart file so the parent script picks it up after QEMU exits.
    cat > "$RESTART_FILE" <<EOF
PENDING_NET_CONFIG="${frag}"
EOF

    if [ "$rc" = "2" ]; then
        # Save without restarting — config will apply on the next manual restart.
        yad --info $YAD_ICON $YAD_POS \
            --title="Saved" \
            --width="$bigger_width" \
            --text="IPv4 config saved to:\n  $RESTART_FILE\n\nIt will apply when the VM restarts. To restart now,\nuse VM Power -> Restart VM (apply pending config)." \
            --button="OK:0"
        return 0
    fi

    # Save & Restart Now: confirm, then quit QEMU. Parent re-launches.
    yad --question $YAD_ICON $YAD_POS \
        --title="Restart VM Now?" \
        --width="$bigger_width" \
        --text="The running VM will be powered off (HMP 'quit') and re-launched
with the new IPv4 settings. Unsaved guest state will be lost.

Proceed with restart?" \
        --button="Cancel:1" --button="Restart Now:0"

    if [ $? -ne 0 ]; then
        rm -f "$RESTART_FILE"
        return 0
    fi

    send_monitor "quit"
    # Helper exits naturally when the parent's watchdog kills our process group.
    sleep 1
    exit 0
}

# =============================================================================
# STORAGE SUB-MENU
# =============================================================================
storage_submenu() {
    while true; do
        local stor_action
        stor_action=$(yad --list $YAD_ICON $YAD_POS \
            --title="Storage Manager" \
            --width="$smaller_width" --height="$smaller_height" \
            --column="Action" \
            --text="Hot-plug additional storage devices:" \
            --button="Back:1" --button="OK:0" \
            "Add storage device" \
            "Remove storage device" \
            "View current storage layout")

        [ $? -ne 0 ] && return 0
        stor_action=$(echo "$stor_action" | sed 's/|$//')

        case "$stor_action" in

            "Add storage device")
                local src_type
                src_type=$(yad --list $YAD_ICON $YAD_POS \
                    --title="Add Storage" \
                    --width="$smaller_width" --height="$smaller_height" \
                    --column="Source" \
                    --text="Attach what kind of storage?" \
                    --button="Cancel:1" --button="OK:0" \
                    "Virtual Disk" \
                    "Physical Device")

                [ $? -ne 0 ] && continue
                src_type=$(echo "$src_type" | sed 's/|$//')

                local source_path="" dev_kind=""

                if [ "$src_type" = "Virtual Disk" ]; then
                    source_path=$(yad --file $YAD_ICON $YAD_POS \
                        --title="Select Virtual Disk (.img, .qcow2, .vhd, .vhdx)" \
                        --width="$bigger_width" --height="$smaller_height" \
                        --file-filter="Virtual Disks | *.img *.qcow2 *.qcow *.vhd *.vhdx *.vmdk *.vdi *.raw" \
                        --file-filter="All files | *")
                    [ $? -ne 0 ] || [ ! -f "$source_path" ] && continue
                    dev_kind="virtual"
                else
                    local yad_args=("--list"
                        "--title=Select Physical Device"
                        "--width=$bigger_width" "--height=$smaller_height"
                        "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                        "--column=Drive" "--column=Size"
                        "--text=Select a physical device to attach:"
                        "--button=Cancel:1" "--button=Attach:0")
                    while IFS= read -r line; do
                        if [ -n "$line" ]; then
                            local d s
                            d=$(echo "$line" | awk '{print $1}')
                            s=$(echo "$line" | awk '{print $2}')
                            yad_args+=("$d" "$s")
                        fi
                    done <<< "$(lsblk -o NAME,SIZE -lnp -d -e 7,11)"

                    source_path=$(yad "${yad_args[@]}")
                    [ $? -ne 0 ] && continue
                    source_path=$(echo "$source_path" | cut -d'|' -f1)
                    [ -z "$source_path" ] || [ ! -b "$source_path" ] && continue
                    dev_kind="physical"
                fi

                local fmt
                if [ "$dev_kind" = "physical" ]; then
                    fmt="raw"
                else
                    fmt=$(storage_format_from_path "$source_path")
                fi

                local stor_id add_drive_cmd add_drive_result add_dev_cmd add_dev_result
                stor_id=$(storage_next_id)

                add_drive_cmd="drive_add 0 if=none,id=${stor_id},file=${source_path},format=${fmt}"
                add_drive_result=$(query_monitor "$add_drive_cmd")

                if [[ "$add_drive_result" == *"could not"* ]] || \
                   [[ "$add_drive_result" == *"error"* ]] || \
                   [[ "$add_drive_result" == *"Error"* ]] || \
                   [[ "$add_drive_result" == *"Invalid"* ]]; then
                    yad --error $YAD_ICON $YAD_POS \
                        --title="drive_add failed" \
                        --width="$bigger_width" \
                        --text="QEMU rejected drive_add:\n\n${add_drive_result}" \
                        --button="OK:0"
                    continue
                fi

                add_dev_cmd="device_add scsi-hd,drive=${stor_id},id=${stor_id},bus=scsi0.0"
                add_dev_result=$(query_monitor "$add_dev_cmd")

                if [ -n "$add_dev_result" ]; then
                    query_monitor "drive_del ${stor_id}" >/dev/null 2>&1
                    yad --error $YAD_ICON $YAD_POS \
                        --title="device_add failed" \
                        --width="$bigger_width" \
                        --text="QEMU rejected device_add. The drive has been rolled back.\n\n${add_dev_result}" \
                        --button="OK:0"
                    continue
                fi

                storage_record "$stor_id" "$dev_kind" "$source_path" "$fmt"

                yad --info $YAD_ICON $YAD_POS \
                    --title="Storage Attached" \
                    --width="$bigger_width" \
                    --text="[ + ]  ${stor_id}  (${dev_kind}, ${fmt})\n${source_path}\n\nGuest should see a new SCSI disk (/dev/sdX on Linux)." \
                    --timeout=5 --timeout-indicator=bottom \
                    --no-buttons
                ;;

            "Remove storage device")
                if [ ! -s "$STORAGE_FILE" ]; then
                    yad --info $YAD_ICON $YAD_POS \
                        --title="Remove Storage" \
                        --width="$smaller_width" \
                        --text="No hot-added storage devices to remove.\n\n(The boot disk is not listed here and cannot be detached.)" \
                        --button="OK:0"
                    continue
                fi

                local yad_args=("--list"
                    "--title=Remove Storage Device"
                    "--width=$bigger_width" "--height=$smaller_height"
                    "--posx=$HOTPLUG_POSX" "--posy=$HOTPLUG_POSY"
                    "--column=ID" "--column=Type" "--column=Format" "--column=Source"
                    "--text=Select a device to detach:"
                    "--button=Cancel:1" "--button=Detach:0")

                while IFS='|' read -r id kind src fmt; do
                    [ -z "$id" ] && continue
                    yad_args+=("$id" "$kind" "$fmt" "$src")
                done < "$STORAGE_FILE"

                local selected
                selected=$(yad "${yad_args[@]}")
                [ $? -ne 0 ] && continue

                local rm_id rm_src
                rm_id=$(echo "$selected" | cut -d'|' -f1)
                rm_src=$(echo "$selected" | cut -d'|' -f4)

                yad --question $YAD_ICON $YAD_POS \
                    --title="Detach ${rm_id}" \
                    --width="$bigger_width" \
                    --text="About to detach:\n  ${rm_id}  →  ${rm_src}\n\nTip: for cleanest results, unmount the device inside the guest first. Detaching a device that is still in use may cause I/O errors or data loss.\n\nProceed?" \
                    --button="Cancel:1" --button="Proceed:0"
                [ $? -ne 0 ] && continue

                local del_dev_result
                del_dev_result=$(query_monitor "device_del ${rm_id}")
                if [ -n "$del_dev_result" ]; then
                    yad --error $YAD_ICON $YAD_POS \
                        --title="device_del failed" \
                        --width="$bigger_width" \
                        --text="QEMU rejected device_del:\n\n${del_dev_result}" \
                        --button="OK:0"
                    continue
                fi

                sleep 0.3
                query_monitor "drive_del ${rm_id}" >/dev/null 2>&1
                storage_forget "$rm_id"

                yad --info $YAD_ICON $YAD_POS \
                    --title="Storage Detached" \
                    --width="$smaller_width" \
                    --text="[ - ]  ${rm_id} detached." \
                    --timeout=4 --timeout-indicator=bottom \
                    --no-buttons
                ;;

            "View current storage layout")
                local hot_added info_raw layout_text
                if [ -s "$STORAGE_FILE" ]; then
                    hot_added=$(awk -F'|' '{printf "  %-12s  %-8s  %-6s  %s\n", $1, $2, $4, $3}' "$STORAGE_FILE")
                else
                    hot_added="  (none)"
                fi

                info_raw=$(query_monitor "info block")
                [ -z "$info_raw" ] && info_raw="  (no response from QEMU monitor)"

                layout_text="Hot-added devices (managed by this panel):

${hot_added}

Full block-device layout ('info block'):

${info_raw}"

                yad --text-info $YAD_ICON $YAD_POS \
                    --title="Storage Layout" \
                    --width="$bigger_width" --height="400" \
                    --fontname="Monospace 10" \
                    --button="OK:0" \
                    <<< "$layout_text"
                ;;
        esac
    done
}

# =============================================================================
# VM POWER SUB-MENU
# =============================================================================
power_submenu() {
    while true; do
        local pwr_action
        pwr_action=$(yad --list $YAD_ICON $YAD_POS \
            --title="VM Power" \
            --width="$smaller_width" --height="$smaller_height" \
            --column="Action" \
            --text="Power and lifecycle controls:" \
            --button="Back:1" --button="OK:0" \
            "Send Reset (hard reboot)" \
            "Send ACPI Shutdown (graceful)" \
            "Restart VM (apply pending config)" \
            "Force Quit VM")

        [ $? -ne 0 ] && return 0
        pwr_action=$(echo "$pwr_action" | sed 's/|$//')

        case "$pwr_action" in

            "Send Reset (hard reboot)")
                yad --question $YAD_ICON $YAD_POS \
                    --title="Reset VM" \
                    --width="$bigger_width" \
                    --text="Send 'system_reset' to the VM (equivalent to pressing reset).\n\nUnsaved guest state will be lost. Proceed?" \
                    --button="Cancel:1" --button="Reset:0"
                [ $? -ne 0 ] && continue

                send_monitor "system_reset"
                yad --info $YAD_ICON $YAD_POS \
                    --title="Reset Sent" \
                    --width="$smaller_width" \
                    --text="VM reset signal sent." \
                    --timeout=2 --timeout-indicator=bottom \
                    --no-buttons
                ;;

            "Send ACPI Shutdown (graceful)")
                yad --question $YAD_ICON $YAD_POS \
                    --title="Shutdown VM" \
                    --width="$bigger_width" \
                    --text="Send 'system_powerdown' (ACPI shutdown).\n\nThe guest OS may prompt or take time to shut down cleanly.\nThe panel will close when QEMU exits.\n\nProceed?" \
                    --button="Cancel:1" --button="Shutdown:0"
                [ $? -ne 0 ] && continue

                send_monitor "system_powerdown"
                yad --info $YAD_ICON $YAD_POS \
                    --title="Shutdown Signal Sent" \
                    --width="$bigger_width" \
                    --text="ACPI shutdown signal sent.\n\nWaiting for the guest to power off..." \
                    --timeout=4 --timeout-indicator=bottom \
                    --no-buttons
                ;;

            "Restart VM (apply pending config)")
                if [ ! -f "$RESTART_FILE" ]; then
                    yad --info $YAD_ICON $YAD_POS \
                        --title="No Pending Config" \
                        --width="$bigger_width" \
                        --text="No pending IPv4/network config to apply.\n\nUse Network -> IPv4 / Subnet Config first to queue\na new configuration." \
                        --button="OK:0"
                    continue
                fi

                yad --question $YAD_ICON $YAD_POS \
                    --title="Restart VM Now?" \
                    --width="$bigger_width" \
                    --text="The VM will be powered off and re-launched with the\npending config from $RESTART_FILE.\n\nUnsaved guest state will be lost. Proceed?" \
                    --button="Cancel:1" --button="Restart Now:0"
                [ $? -ne 0 ] && continue

                send_monitor "quit"
                sleep 1
                exit 0
                ;;

            "Force Quit VM")
                yad --question $YAD_ICON $YAD_POS \
                    --title="Force Quit VM" \
                    --width="$bigger_width" \
                    --text="Send HMP 'quit' — terminates QEMU immediately.\nEquivalent to pulling the plug.\n\nUnsaved guest state will be LOST. Proceed?" \
                    --button="Cancel:1" --button="Force Quit:0"
                [ $? -ne 0 ] && continue

                # Discard any pending restart file so the parent doesn't relaunch.
                rm -f "$RESTART_FILE"
                send_monitor "quit"
                sleep 1
                exit 0
                ;;
        esac
    done
}

# =============================================================================
# TOP-LEVEL MENU LOOP
# =============================================================================
while true; do
    action=$(yad --list $YAD_ICON $YAD_POS \
        --title="VM Session Settings" \
        --width="$smaller_width" --height="$smaller_height" \
        --column="Section" \
        --text="QEMU-QuickBoot — live VM controls" \
        --button="Quit Panel:1" --button="OK:0" \
        "USB Devices" \
        "Network" \
        "Storage" \
        "VM Power")

    [ $? -ne 0 ] && exit 0
    action=$(echo "$action" | sed 's/|$//')

    case "$action" in
        "USB Devices") usb_submenu ;;
        "Network")     network_submenu ;;
        "Storage")     storage_submenu ;;
        "VM Power")    power_submenu ;;
    esac
done
