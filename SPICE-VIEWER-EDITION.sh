#!/bin/bash

# Set the GTK theme to dark
export GTK_THEME=Orchis:dark

# Calculate window sizes
original_width=440
original_height=320
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")
geometry="${smaller_width}x${smaller_height}"

extra_disks=""

# Function to check and fix permissions for media access
fix_media_permissions() {
    local path="$1"
    local media_dir=$(dirname "$path")
    
    if [[ "$media_dir" == /media/* ]]; then
        zenity --question --title="Permission Required" \
               --text="The ISO file is in /media/ which requires special permissions. Fix permissions now? (Requires sudo)" \
               --width="$smaller_width" --height="$smaller_height"
        
        if [ $? -eq 0 ]; then
            local media_user=$(echo "$media_dir" | cut -d'/' -f3)
            sudo chmod o+x "/media/$media_user" 2>/dev/null
            sudo setfacl -m u:libvirt-qemu:rx "/media/$media_user" 2>/dev/null || \
            sudo chmod g+rx "/media/$media_user" 2>/dev/null
        fi
        
        # If still having issues, offer to copy to /tmp
        if [ ! -r "$path" ]; then
            zenity --question --title="Alternative Solution" \
                   --text="Couldn't fix permissions. Copy ISO to /tmp instead?" \
                   --width="$smaller_width" --height="$smaller_height"
            if [ $? -eq 0 ]; then
                temp_path="/tmp/$(basename "$path")"
                cp "$path" "$temp_path" && path="$temp_path"
            fi
        fi
    fi
    echo "$path"
}

# Function to safely release disk devices
release_disk() {
    local disk_path="$1"
    # Check if disk is in use by any VM
    for vm in $(virsh list --name --all); do
        if virsh dumpxml "$vm" | grep -q "$disk_path"; then
            zenity --question --title="Disk in Use" \
                   --text="Disk $disk_path is used by VM $vm. Shut down this VM first?" \
                   --width="$smaller_width" --height="$smaller_height"
            if [ $? -eq 0 ]; then
                virsh destroy "$vm" 2>/dev/null
                virsh undefine "$vm" --nvram 2>/dev/null
            else
                return 1
            fi
        fi
    done
    
    # Ensure disk is not mounted
    sudo umount "${disk_path}"* 2>/dev/null
    
    return 0
}

# Function to setup virtual network
setup_virtual_network() {
    # Try system connection first
    if virsh -c qemu:///system list >/dev/null 2>&1; then
        # Check if default network exists and is active
        if virsh -c qemu:///system net-info default >/dev/null 2>&1; then
            echo "qemu:///system"
            return
        fi
    fi
    
    # Fall back to user session
    echo "qemu:///session"
}

# Function to launch VM viewer
launch_vm_viewer() {
    local vm_name="$1"
    local connect_uri="$2"
    if which virt-viewer >/dev/null; then
        virt-viewer -c "$connect_uri" "$vm_name" &> /dev/null &
    elif which remote-viewer >/dev/null; then
        remote-viewer "spice://127.0.0.1" &> /dev/null &
    else
        zenity --warning --title="Viewer Not Found" \
               --text="Could not find virt-viewer or remote-viewer. Install with:\nsudo apt install virt-viewer virt-manager" \
               --width="$smaller_width" --height="$smaller_height"
    fi
}

while true; do
    # Option to choose boot source
    boot_source_choice=$(zenity --list --title="Select VM Boot Source" \
        --column="Option" --width="$original_width" --height="$smaller_height" \
        "Boot from connected device" \
        "Boot from file (.vhd, .img, .iso)" \
        "ISO & Drive (Virtual disk or Physical Device)")

    [ $? -ne 0 ] && exit 1

    iso_path=""
    case "$boot_source_choice" in
        "Boot from connected device")
            drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
            selected_drive=$(zenity --list --title="Select Disk" \
                --column="Drive" --column="Size" --text "Select a disk:" \
                --width="$bigger_width" --height="$smaller_height" $drives)
            [ $? -ne 0 ] && exit 1

            if ! release_disk "$selected_drive"; then
                zenity --error --title="Disk in Use" \
                       --text="Cannot use $selected_drive - it's in use by another VM" \
                       --width="$smaller_width" --height="$smaller_height"
                continue
            fi

            add_extra_disk=$(zenity --list --title="Add Extra Disk" \
                --column="Option" --text="Add an extra disk?" \
                --width="$smaller_width" --height="$smaller_height" "Yes" "No")
            [ $? -ne 0 ] && exit 1

            if [ "$add_extra_disk" == "Yes" ]; then
                while true; do
                    extra_disk_choice=$(zenity --list --title="Select Extra Disk Type" \
                        --column="Option" --width="$bigger_width" --height="$smaller_height" \
                        "Select Virtual Disk" "Select Physical Device" "Done")
                    [ $? -ne 0 ] && exit 1

                    case "$extra_disk_choice" in
                        "Select Virtual Disk")
                            extra_disk=$(zenity --file-selection \
                                --title="Select Extra Virtual Disk (.img, .vhd, .vhdx)" \
                                --width="$smaller_width" --height="$smaller_height")
                            [ $? -eq 0 ] && [ -f "$extra_disk" ] && \
                                extra_disks="$extra_disks --disk path=$extra_disk"
                            ;;
                        "Select Physical Device")
                            drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                            extra_disk=$(zenity --list --title="Select Extra Physical Device" \
                                --column="Drive" --column="Size" \
                                --text "Select an extra physical device:" \
                                --width="$bigger_width" --height="$smaller_height" $drives)
                            if [ $? -eq 0 ] && release_disk "$extra_disk"; then
                                extra_disks="$extra_disks --disk path=$extra_disk,check=off"
                            fi
                            ;;
                        "Done") break ;;
                        *) continue ;;
                    esac
                done
            fi
            ;;

        "Boot from file (.vhd, .img, .iso)")
            selected_drive=$(zenity --file-selection \
                --title="Select Virtual Disk (.vhd, .img, .iso)" \
                --width="$smaller_width" --height="$smaller_height")
            [ $? -ne 0 ] || [ ! -f "$selected_drive" ] && continue
            ;;

        "ISO & Drive (Virtual disk or Physical Device)")
            iso_path=$(zenity --file-selection --title="Select .ISO file" \
                --width="$smaller_width" --height="$smaller_height")
            [ $? -ne 0 ] || [ ! -f "$iso_path" ] && continue

            iso_path=$(fix_media_permissions "$iso_path")

            selected_drive=$(zenity --list --title="Select Virtual Disk or Physical Device" \
                --column="Option" --width="$bigger_width" --height="$smaller_height" \
                "Select Virtual Disk" "Select Physical Device")
            [ $? -ne 0 ] && exit 1

            if [ "$selected_drive" == "Select Virtual Disk" ]; then
                selected_drive=$(zenity --file-selection \
                    --title="Select Virtual Disk (.img, .vhd, .vhdx)" \
                    --width="$smaller_width" --height="$smaller_height")
                [ $? -ne 0 ] || [ ! -f "$selected_drive" ] && continue
            else
                drives=$(lsblk -o NAME,SIZE -lnp -d -e 7,11)
                selected_drive=$(zenity --list --title="Select Physical Device" \
                    --column="Drive" --column="Size" --text "Select a physical device:" \
                    --width="$bigger_width" --height="$smaller_height" $drives)
                [ $? -ne 0 ] && exit 1
                
                if ! release_disk "$selected_drive"; then
                    continue
                fi
            fi
            ;;
        *) continue ;;
    esac

    # Get common configuration
    boot_mode=$(zenity --list --title="Select Boot Mode" \
        --column="Boot Mode" "BIOS" "UEFI" \
        --width="$smaller_width" --height="$smaller_height")
    [ $? -ne 0 ] && exit 1

    ram_size=$(zenity --entry --title="Enter RAM Size" \
        --text "Enter RAM for the VM (in MB):" \
        --width="$smaller_width" --height="$smaller_height")
    [ $? -ne 0 ] || ! [[ "$ram_size" =~ ^[1-9][0-9]*$ ]] && continue

    vm_name=$(zenity --entry --title="Enter VM Name" \
        --text "Enter a name for this VM:" \
        --width="$smaller_width" --height="$smaller_height")
    [ $? -ne 0 ] || [ -z "$vm_name" ] && continue

    os_variant=$(zenity --list --title="Select OS Variant" \
        --column="OS Variant" --text "Select the closest OS variant:" \
        --width="$bigger_width" --height="$smaller_height" \
        "generic" "linux2022" "linux2020" "linux2018" "linux2016" \
        "windows11" "windows10" "windows8.1" "windows7" \
        "ubuntu22.04" "ubuntu20.04" "debian11" "fedora36" "centos9")
    [ $? -ne 0 ] && continue

    # Setup connection
    connect_uri=$(setup_virtual_network)
    if [ -z "$connect_uri" ]; then
        zenity --error --title="Network Error" \
               --text="Cannot proceed without network configuration" \
               --width="$smaller_width" --height="$smaller_height"
        continue
    fi

    # Build virt-install command
    virt_command="virt-install --connect $connect_uri --name \"$vm_name\" --memory $ram_size --os-variant \"$os_variant\""

    # Handle boot source
    if [ -n "$iso_path" ]; then
        virt_command="$virt_command --cdrom \"$iso_path\""
    elif [ "$boot_source_choice" == "Boot from connected device" ]; then
        virt_command="$virt_command --import"
    else
        virt_command="$virt_command --boot hd"
    fi

    # Add disk with appropriate options
    if [[ "$selected_drive" == /dev/* ]]; then
        virt_command="$virt_command --disk path=\"$selected_drive\",check=off"
    else
        virt_command="$virt_command --disk path=\"$selected_drive\""
    fi

    # Add UEFI/BIOS configuration
    if [ "$boot_mode" == "UEFI" ]; then
        virt_command="$virt_command --boot uefi --machine q35"
    fi

    # Add extra disks if specified
    [ -n "$extra_disks" ] && virt_command="$virt_command $extra_disks"

    # Add graphics and networking
    virt_command="$virt_command --graphics spice,listen=0.0.0.0 --video qxl"
    
    if [ "$connect_uri" == "qemu:///system" ]; then
        virt_command="$virt_command --network network=default"
    else
        virt_command="$virt_command --network user"
    fi
    
    virt_command="$virt_command --noautoconsole"

    # Execute the command
    echo "Executing: $virt_command"
    if ! eval "$virt_command"; then
        zenity --error --title="VM Creation Failed" \
               --text="Failed to create VM '$vm_name'.\nCheck terminal for errors." \
               --width="$smaller_width" --height="$smaller_height"
        continue
    fi

    # Launch viewer and check status
    launch_vm_viewer "$vm_name" "$connect_uri"
    sleep 3

    if virsh --connect "$connect_uri" list --all | grep -q "$vm_name"; then
        zenity --info --title="VM Started" \
               --text="VM '$vm_name' started successfully.\nViewer window should be visible." \
               --width="$smaller_width" --height="$smaller_height"
    else
        zenity --error --title="VM Creation Failed" \
               --text="VM '$vm_name' failed to start.\nCheck terminal for errors." \
               --width="$smaller_width" --height="$smaller_height"
    fi

    zenity --question --title="libvirt - QuickBoot" \
           --text="Create another VM?" \
           --width="$smaller_width" --height="$smaller_height"
    [ $? -ne 0 ] && break
done

echo "VM creation script ended"
