#!/bin/bash

# Script name: qemu-quickboot.sh
# Description: A GUI launcher for QEMU virtual machines with USB hot-plugging support

# Set script defaults and constants
DEFAULT_RAM=2048
DEFAULT_CPU_CORES=4
GTK_THEME=Orchis:dark
OVMF_PATH="/usr/share/qemu/OVMF.fd"
TCP_PORT=2222
QEMU_MONITOR_SOCKET="/tmp/qemu-monitor-socket-$$"
USB_CONTROL_FIFO="/tmp/qemu-usb-control-$$"

# Exit if required tools aren't installed
for cmd in zenity qemu-system-x86_64 lsblk yad socat lsusb; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed. Please install it and try again."
        [ "$cmd" = "yad" ] && echo "YAD is needed for the floating control bar."
        [ "$cmd" = "socat" ] && echo "socat is needed for QEMU monitor communication."
        exit 1
    fi
done

# Set the GTK theme to dark
export GTK_THEME=$GTK_THEME

# Calculate window sizes for consistent UI
original_width=440
original_height=360
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")
standard_geometry="${smaller_width}x${smaller_height}"
large_geometry="${bigger_width}x${smaller_height}"

# Cleanup function to remove temporary files
cleanup() {
    echo "Cleaning up..."
    [ -e "$QEMU_MONITOR_SOCKET" ] && rm -f "$QEMU_MONITOR_SOCKET"
    [ -e "$USB_CONTROL_FIFO" ] && rm -f "$USB_CONTROL_FIFO"
    # Kill any remaining control panels
    pkill -f "yad --title=VM Control Panel"
    exit 0
}

# Set trap for cleanup on exit
trap cleanup EXIT INT TERM

# Helper functions
show_error() {
    zenity --error --title="Error" --text="$1" --width="$smaller_width"
}

show_info() {
    zenity --info --title="Information" --text="$1" --width="$smaller_width"
}

get_disk_list() {
    # Filter out loop and rom devices, display with size
    lsblk -o NAME,SIZE,MODEL -lnp -d -e 7,11 | grep -v "^$"
}

select_physical_disk() {
    local title="$1"
    local drives
    local selected_drive
    
    # Create a formatted list for Zenity
    drives=$(get_disk_list | awk '{print $1 " " $2 " " $3}')
    
    # Show selection dialog
    selected_drive=$(zenity --list --title="$title" \
                    --column="Drive" --column="Size" --column="Model" \
                    --text="Select a disk:" \
                    --width="$bigger_width" --height="$smaller_height" $drives)
    
    echo "$selected_drive"
}

select_virtual_disk() {
    local title="$1"
    
    zenity --file-selection \
        --title="$title" \
        --file-filter="Disk Images (*.img *.vhd *.vhdx *.qcow2 *.raw)| *.img *.vhd *.vhdx *.qcow2 *.raw" \
        --width="$bigger_width" --height="$smaller_height"
}

add_extra_disks() {
    local extra_disks=""
    local extra_disk_id=1
    
    while true; do
        extra_disk_choice=$(zenity --list --title="Extra Disk Options" \
            --column="Option" --width="$bigger_width" --height="$smaller_height" \
            "Add Virtual Disk" "Add Physical Device" "Done")
        
        if [ $? -ne 0 ] || [ "$extra_disk_choice" == "Done" ]; then
            break
        fi
        
        case "$extra_disk_choice" in
            "Add Virtual Disk")
                extra_disk=$(select_virtual_disk "Select Extra Virtual Disk")
                
                if [ $? -eq 0 ] && [ -f "$extra_disk" ]; then
                    # Determine disk format from extension
                    format="raw"
                    case "${extra_disk,,}" in
                        *.qcow2) format="qcow2" ;;
                        *.vhd|*.vhdx) format="vpc" ;;
                    esac
                    
                    extra_disks="$extra_disks -drive file=\"$extra_disk\",format=$format,id=extra_drive$extra_disk_id"
                    extra_disk_id=$((extra_disk_id + 1))
                    show_info "Added virtual disk: $extra_disk"
                fi
                ;;
                
            "Add Physical Device")
                extra_disk=$(select_physical_disk "Select Extra Physical Device")
                
                if [ $? -eq 0 ] && [ -n "$extra_disk" ]; then
                    extra_disks="$extra_disks -drive file=\"$extra_disk\",format=raw,id=extra_drive$extra_disk_id,cache=none"
                    extra_disk_id=$((extra_disk_id + 1))
                    show_info "Added physical device: $extra_disk"
                fi
                ;;
        esac
    done
    
    echo "$extra_disks"
}

# Function to send commands to QEMU monitor
send_qemu_command() {
    echo "$1" | socat - UNIX-CONNECT:"$QEMU_MONITOR_SOCKET"
}

# Function to attach USB device
attach_usb_device() {
    local vendor_id="${1%%:*}"
    local product_id="${1#*:}"
    
    send_qemu_command "device_add usb-host,vendorid=0x$vendor_id,productid=0x$product_id,id=usb-$vendor_id-$product_id"
    echo "Added USB device $vendor_id:$product_id"
}

# Function to detach USB device
detach_usb_device() {
    local vendor_id="${1%%:*}"
    local product_id="${1#*:}"
    
    send_qemu_command "device_del usb-$vendor_id-$product_id"
    echo "Removed USB device $vendor_id:$product_id"
}

# Function to get USB devices with HID devices first
get_usb_devices() {
    # First get HID devices (keyboards, mice, gamepads)
    lsusb | grep -i "Human Interface Device\|Keyboard\|Mouse\|Gamepad\|Controller" | 
    awk -F'[ :]' '{printf "%s:%s|%s %s %s %s %s (HID)\n", $2, $4, $7, $8, $9, $10, $11}' | sort
    
    # Then get webcams and other common user devices
    lsusb | grep -i "Webcam\|Camera\|Audio\|Headset\|Microphone" | 
    awk -F'[ :]' '{printf "%s:%s|%s %s %s %s %s\n", $2, $4, $7, $8, $9, $10, $11}' | sort
    
    # Then get all other devices (excluding the ones already listed)
    lsusb | grep -vi "Human Interface Device\|Keyboard\|Mouse\|Gamepad\|Controller\|Webcam\|Camera\|Audio\|Headset\|Microphone" | 
    awk -F'[ :]' '{printf "%s:%s|%s %s %s %s %s\n", $2, $4, $7, $8, $9, $10, $11}' | sort
}

# Function to show a better formatted USB menu
show_usb_menu() {
    zenity --list \
        --title="USB Devices" \
        --text="Select a USB device to attach" \
        --column="ID" --column="Device" \
        $(get_usb_devices | tr '|' ' ') \
        --width=400 --height=300 \
        --print-column=1 > "$USB_CONTROL_FIFO"
}

# Function to launch the floating control panel
launch_control_panel() {
    local vm_name="$1"
    local qemu_pid="$2"
    
    # Create named pipe for USB control
    [ -e "$USB_CONTROL_FIFO" ] && rm -f "$USB_CONTROL_FIFO"
    mkfifo "$USB_CONTROL_FIFO"
    
    # Start control panel with YAD as a horizontal toolbar
    # Modified to be twice as long and half as tall with buttons in a row
    yad --title="VM Control Panel - $vm_name" \
        --width=700 --height=20 \
        --form \
        --window-icon=computer \
        --borders=0 \
        --geometry=+0+0 \
        --sticky \
        --skip-taskbar \
        --no-focus \
        --fixed \
        --no-buttons \
        --compact \
        --field="USB Devices:BTN" \
        --field="⏻:BTN" \
        --field="↻:BTN" \
        --field="📷:BTN" \
        --button="×:1" \
        "bash -c \"show_usb_menu\"" \
        "bash -c 'echo SHUTDOWN > $USB_CONTROL_FIFO'" \
        "bash -c 'echo RESET > $USB_CONTROL_FIFO'" \
        "bash -c 'echo SCREENSHOT > $USB_CONTROL_FIFO'" &
    
    control_panel_pid=$!
    
    launch_control_panel() {
    local vm_name="$1"
    local qemu_pid="$2"

    # Create named pipe for USB control
    [ -e "$USB_CONTROL_FIFO" ] && rm -f "$USB_CONTROL_FIFO"
    mkfifo "$USB_CONTROL_FIFO"

    # Start control panel with YAD as a horizontal toolbar
    yad --title="VM Control Panel - $vm_name" \
        --width=700 --height=20 \
        --form \
        --window-icon=computer \
        --borders=0 \
        --geometry=+0+0 \
        --sticky \
        --skip-taskbar \
        --no-focus \
        --fixed \
        --no-buttons \
        --compact \
        --text-align=center \
        --field="USB Devices:CB" "$(get_usb_devices | tr '|' ' ')" \
        --field="Shutdown:BTN" "bash -c 'echo SHUTDOWN > $USB_CONTROL_FIFO'" \
        --field="Reset:BTN" "bash -c 'echo RESET > $USB_CONTROL_FIFO'" \
        --button="×:1" \
        &
    
    control_panel_pid=$!

    # Process to handle the control panel commands
    (
        while [ -e "$USB_CONTROL_FIFO" ] && kill -0 $qemu_pid 2>/dev/null; do
            if read line < "$USB_CONTROL_FIFO"; then
                case "$line" in
                    ATTACH_USB)
                        if read device_id < "$USB_CONTROL_FIFO"; then
                            attach_usb_device "$device_id"
                            yad --notification --text="USB device $device_id attached" --icon=computer --timeout=3 &
                        fi
                        ;;
                    DETACH_USB)
                        if read device_id < "$USB_CONTROL_FIFO"; then
                            detach_usb_device "$device_id"
                        fi
                        ;;
                    SHUTDOWN)
                        send_qemu_command "system_powerdown"
                        ;;
                    RESET)
                        send_qemu_command "system_reset"
                        ;;
                esac
            fi
        done
        [ -e "$USB_CONTROL_FIFO" ] && rm -f "$USB_CONTROL_FIFO"
        kill $control_panel_pid 2>/dev/null
    ) &
}

# Function to refresh USB devices in the control panel
refresh_usb_devices() {
    # Implementation would depend on how you want to update the YAD dialog
    echo "Refreshing USB devices list"
}

# Main loop
while true; do
    # Reset variables for each iteration
    selected_drive=""
    iso_path=""
    extra_disks=""
    
    # Option to choose boot source using Zenity
    boot_source_choice=$(zenity --list --title="QEMU QuickBoot" \
        --text="Select VM Boot Source:" \
        --column="Option" --width="$original_width" --height="$smaller_height" \
        "Boot from physical device" \
        "Boot from virtual disk (.vhd, .img, .qcow2)" \
        "Boot from ISO only" \
        "ISO & Drive (Virtual disk or Physical Device)")

    if [ $? -ne 0 ]; then
        exit 0
    fi

    case "$boot_source_choice" in
        "Boot from physical device")
            selected_drive=$(select_physical_disk "Select Physical Device")
            
            if [ -z "$selected_drive" ]; then
                show_error "No drive selected. Please try again."
                continue
            fi
            ;;

        "Boot from virtual disk (.vhd, .img, .qcow2)")
            selected_drive=$(select_virtual_disk "Select Virtual Disk")
            
            if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                show_error "Invalid disk file. Please try again."
                continue
            fi
            
            # Determine disk format from extension
            disk_format="raw"
            case "${selected_drive,,}" in
                *.qcow2) disk_format="qcow2" ;;
                *.vhd|*.vhdx) disk_format="vpc" ;;
            esac
            ;;
            
        "Boot from ISO only")
            iso_path=$(zenity --file-selection \
                --title="Select ISO File" \
                --file-filter="ISO Files (*.iso)| *.iso" \
                --width="$smaller_width" --height="$smaller_height")
                
            if [ $? -ne 0 ] || [ ! -f "$iso_path" ]; then
                show_error "Invalid ISO file. Please try again."
                continue
            fi
            selected_drive=""
            ;;

        "ISO & Drive (Virtual disk or Physical Device)")
            iso_path=$(zenity --file-selection \
                --title="Select ISO File" \
                --file-filter="ISO Files (*.iso)| *.iso" \
                --width="$smaller_width" --height="$smaller_height")
                
            if [ $? -ne 0 ] || [ ! -f "$iso_path" ]; then
                show_error "Invalid ISO file. Please try again."
                continue
            fi

            disk_type=$(zenity --list --title="Select Disk Type" \
                --column="Option" --width="$smaller_width" --height="$smaller_height" \
                "Virtual Disk" "Physical Device" "Create New Virtual Disk")

            if [ $? -ne 0 ]; then
                continue
            fi

            case "$disk_type" in
                "Virtual Disk")
                    selected_drive=$(select_virtual_disk "Select Virtual Disk")
                    
                    if [ $? -ne 0 ] || [ ! -f "$selected_drive" ]; then
                        show_error "Invalid disk file. Please try again."
                        continue
                    fi
                    
                    # Determine disk format from extension
                    disk_format="raw"
                    case "${selected_drive,,}" in
                        *.qcow2) disk_format="qcow2" ;;
                        *.vhd|*.vhdx) disk_format="vpc" ;;
                    esac
                    ;;
                    
                "Physical Device")
                    selected_drive=$(select_physical_disk "Select Physical Device")
                    
                    if [ -z "$selected_drive" ]; then
                        show_error "No drive selected. Please try again."
                        continue
                    fi
                    ;;
                    
                "Create New Virtual Disk")
                    # Get the disk path and size
                    disk_path=$(zenity --file-selection --save \
                        --title="Create New Virtual Disk" \
                        --filename="new_disk.qcow2" \
                        --width="$smaller_width" --height="$smaller_height")
                        
                    if [ $? -ne 0 ]; then
                        continue
                    fi
                    
                    disk_size=$(zenity --entry \
                        --title="Disk Size" \
                        --text="Enter disk size (e.g., 10G, 50G):" \
                        --width="$smaller_width" --height="$smaller_height")
                        
                    if [ $? -ne 0 ] || [ -z "$disk_size" ]; then
                        continue
                    fi
                    
                    # Create the disk
                    if ! qemu-img create -f qcow2 "$disk_path" "$disk_size"; then
                        show_error "Failed to create disk image"
                        continue
                    fi
                    
                    selected_drive="$disk_path"
                    disk_format="qcow2"
                    show_info "Created new disk: $disk_path ($disk_size)"
                    ;;
            esac
            ;;
            
        *)
            continue
            ;;
    esac

    # Add extra disks if requested
    add_extra=$(zenity --question \
        --title="Extra Disks" \
        --text="Do you want to add extra disks?" \
        --width="$smaller_width" --height="$smaller_height")
        
    if [ $? -eq 0 ]; then
        extra_disks=$(add_extra_disks)
    fi

    # Select boot mode
    boot_mode=$(zenity --list \
        --title="Boot Mode" \
        --column="Boot Mode" --width="$smaller_width" --height="$smaller_height" \
        "BIOS" "UEFI")
        
    if [ $? -ne 0 ]; then
        continue
    fi

    # Get VM name for the control panel
    vm_name=$(zenity --entry \
        --title="VM Name" \
        --text="Enter a name for this VM:" \
        --entry-text="QEMU VM" \
        --width="$smaller_width" --height="$smaller_height")
        
    if [ $? -ne 0 ]; then
        vm_name="QEMU VM"
    fi

    # Advanced VM settings form with multiple inputs
    vm_settings=$(zenity --forms \
        --title="VM Settings" \
        --text="Configure VM resources:" \
        --add-entry="RAM (MB)[$DEFAULT_RAM]" \
        --add-entry="CPU Cores[$DEFAULT_CPU_CORES]" \
        --add-entry="VNC Display Port [0=disabled]" \
        --add-entry="SSH Port Forwarding[$TCP_PORT]" \
        --width="$bigger_width" --height="$smaller_height")
        
    if [ $? -ne 0 ]; then
        continue
    fi
    
    # Parse form values
    IFS='|' read -r ram_size cpu_cores vnc_port ssh_port <<< "$vm_settings"
    
    # Set defaults if empty
    ram_size=${ram_size:-$DEFAULT_RAM}
    cpu_cores=${cpu_cores:-$DEFAULT_CPU_CORES}
    ssh_port=${ssh_port:-$TCP_PORT}
    
    # Validate inputs
    if ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]]; then
        show_error "Invalid RAM value. Using default $DEFAULT_RAM MB."
        ram_size=$DEFAULT_RAM
    fi
    
    if ! [[ "$cpu_cores" =~ ^[1-9][0-9]*$ ]]; then
        show_error "Invalid CPU cores value. Using default $DEFAULT_CPU_CORES cores."
        cpu_cores=$DEFAULT_CPU_CORES
    fi

    # USB controller options
    usb_support=$(zenity --list \
        --title="USB Support" \
        --text="Select USB controller type:" \
        --column="Controller" --width="$smaller_width" --height="$smaller_height" \
        "USB 2.0 (EHCI)" "USB 3.0 (xHCI)" "None")
        
    if [ $? -ne 0 ]; then
        usb_support="USB 2.0 (EHCI)"  # Default
    fi

    # Build the QEMU command
    qemu_command="qemu-system-x86_64"
    qemu_command+=" -name \"$vm_name\""
    qemu_command+=" -enable-kvm -cpu host -smp $cpu_cores -m ${ram_size}M"
    
    # Add drive parameters based on selected boot source
    if [ -n "$selected_drive" ]; then
        if [[ "$selected_drive" == /dev/* ]]; then
            qemu_command+=" -drive file=\"$selected_drive\",format=raw,cache=none"
        else
            qemu_command+=" -drive file=\"$selected_drive\",format=${disk_format:-raw}"
        fi
    fi
    
    # Add ISO if specified
    if [ -n "$iso_path" ]; then
        qemu_command+=" -cdrom \"$iso_path\""
    fi
    
    # Add boot mode
    if [ "$boot_mode" == "UEFI" ]; then
        if [ -f "$OVMF_PATH" ]; then
            qemu_command+=" -bios \"$OVMF_PATH\""
        else
            show_error "UEFI firmware not found at $OVMF_PATH. Falling back to BIOS."
        fi
    fi
    
    # Add networking
    qemu_command+=" -netdev user,id=net0"
    if [ -n "$ssh_port" ] && [ "$ssh_port" != "0" ]; then
        qemu_command+=",hostfwd=tcp::${ssh_port}-:22"
    fi
    qemu_command+=" -device e1000,netdev=net0"
    
    # Add USB controller based on selection
    case "$usb_support" in
        "USB 2.0 (EHCI)")
            qemu_command+=" -device qemu-xhci,id=usb-controller"
            ;;
        "USB 3.0 (xHCI)")
            qemu_command+=" -device nec-usb-xhci,id=usb-controller"
            ;;
        *)
            # No USB controller added
            ;;
    esac
    
    # Add VNC if requested
    if [ -n "$vnc_port" ] && [ "$vnc_port" != "0" ]; then
        qemu_command+=" -vnc :$vnc_port"
    fi
    
    # Add QEMU monitor socket for control
    [ -e "$QEMU_MONITOR_SOCKET" ] && rm -f "$QEMU_MONITOR_SOCKET"
    qemu_command+=" -monitor unix:$QEMU_MONITOR_SOCKET,server,nowait"
    
    # Add boot order and extra disks
    qemu_command+=" -boot order=dc $extra_disks"
    
    # Add display options
    qemu_command+=" -display gtk"
    
    # Print the command for debugging
    echo -e "\nExecuting QEMU command:\n$qemu_command\n"
    
    # Run QEMU command in background
    eval $qemu_command &
    qemu_pid=$!
    
    # Check if QEMU process started successfully
    if ! ps -p $qemu_pid > /dev/null 2>&1; then
        show_error "Failed to start QEMU. Check the command and try again."
        continue
    fi
    
    # Launch control panel if USB support is enabled
    if [ "$usb_support" != "None" ]; then
        # Wait a moment for QEMU monitor socket to be created
        sleep 1
        launch_control_panel "$vm_name" "$qemu_pid"
    fi
    
    # Wait for QEMU to finish
    wait $qemu_pid
    qemu_exit_code=$?
    
    # Check if QEMU exited with an error
    if [ $qemu_exit_code -ne 0 ]; then
        show_error "QEMU exited with error code $qemu_exit_code"
    fi

    # Clean up after VM shutdown
    [ -e "$QEMU_MONITOR_SOCKET" ] && rm -f "$QEMU_MONITOR_SOCKET"
    [ -e "$USB_CONTROL_FIFO" ] && rm -f "$USB_CONTROL_FIFO"
    
    # Kill any remaining control panels
    pkill -f "yad --title=VM Control Panel - $vm_name"

    # Ask if user wants to boot another VM
    zenity --question \
        --title="QEMU QuickBoot" \
        --text="QuickBoot another VM?" \
        --width="$smaller_width" --height="$smaller_height"
        
    if [ $? -ne 0 ]; then
        break
    fi
done

# End of script
