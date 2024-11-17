#!/bin/bash

# Set the GTK theme to dark
#export GTK_THEME=Adwaita-Dark:dark

# Calculate 30% wider size for the first Zenity window
original_width=440
original_height=340
smaller_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 0.5}")
smaller_height=$(awk "BEGIN {printf \"%.0f\n\", $original_height * 0.7}")
bigger_width=$(awk "BEGIN {printf \"%.0f\n\", $original_width * 1.3}")
geometry="${smaller_width}x${smaller_height}"

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
            ;;

        *)
            zenity --error --text="Invalid selection! Please try again."
            continue
            ;;
    esac
done
