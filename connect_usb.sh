#!/bin/bash

# Validate that the VM process is running
VM_PID=$(pgrep -f "qemu-system-x86_64")

if [ -z "$VM_PID" ]; then
    zenity --error --text="Error: No running QEMU process found."
    exit 1
fi

# Define the correct path for the QEMU monitor socket
MONITOR_SOCKET="/tmp/qemu-monitor-socket"

# List USB devices and format them for display
USB_DEVICES=$(lsusb | awk '{print NR ": Bus "$2" Device "$4" ID "$6" - "$7" "$8" "$9" "$10}')

# Display the list of devices using Zenity and prompt for user input
USER_CHOICE=$(zenity --forms --title="Select USB Device" \
    --text="Available USB devices:\n$USB_DEVICES\n\nEnter the index number of the USB device to connect:" \
    --add-entry="Device Index")

# Check if the user provided a selection
if [ -z "$USER_CHOICE" ]; then
    zenity --warning --text="No USB device selected. Exiting."
    exit 1
fi

# Validate the user input
if ! [[ "$USER_CHOICE" =~ ^[0-9]+$ ]]; then
    zenity --error --text="Invalid input. Please enter a valid number."
    exit 1
fi

# Extract the selected USB device details
DEVICE_LINE=$(echo "$USB_DEVICES" | sed -n "${USER_CHOICE}p")

if [ -z "$DEVICE_LINE" ]; then
    zenity --error --text="Error: No device found at index $USER_CHOICE."
    exit 1
fi

# Extract bus and device numbers
BUS=$(echo "$DEVICE_LINE" | awk '{print $3}')
DEVICE=$(echo "$DEVICE_LINE" | awk '{print $5}' | sed 's/://')

# Confirm the selection with the user
zenity --info --text="Selected USB device - Bus: $BUS, Device: $DEVICE"

# Function to connect USB device to VM
connect_usb_device() {
    local bus=$1
    local device=$2

    if [ ! -e "$MONITOR_SOCKET" ]; then
        zenity --error --text="Error: QEMU monitor socket $MONITOR_SOCKET does not exist."
        exit 1
    fi

    # Connect using QEMU monitor command
    echo "device_add usb-host,hostbus=$bus,hostaddr=$device" | socat - UNIX-CONNECT:$MONITOR_SOCKET
    if [ $? -eq 0 ]; then
        zenity --info --text="USB device connected successfully!"
    else
        zenity --error --text="Failed to connect USB device."
    fi
}

# Connect the selected USB device to the VM
connect_usb_device "$BUS" "$DEVICE"
