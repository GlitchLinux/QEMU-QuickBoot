# QEMU-QuickBoot

QEMU-QuickBoot is a Zenity GUI interface for quick and easy deployment of QEMU Virtual Machines.

![349671419-4228f66a-cefe-4c85-bd99-26ad465dd354](https://github.com/user-attachments/assets/83ee258e-395a-4278-b866-875ee1505089)

## Overview

QEMU-QuickBoot is a Bash script designed to simplify the deployment of Virtual Machines (VMs) using QEMU, with a user-friendly GUI interface provided by Zenity. It allows users to quickly create and boot VMs directly from their desktop, using connected physical devices or bootable image files as the source media.

> **Note:** Currently, QEMU-QuickBoot is supported only on Debian and Ubuntu-based distributions. Support for Arch and Fedora-based distributions is planned to be added in future updates.

### Key Features

- **User-Friendly Interface**: Utilizes Zenity to present a straightforward interface for selecting VM boot sources and configurations.
- **Multiple Boot Options**: Supports booting VMs from connected devices, various file formats (.vhd, .img, .iso), and ISO images with virtual drives or physical devices.
- **Dynamic RAM Configuration**: Allows users to specify the amount of RAM (in MB) allocated to the VM.
- **BIOS and UEFI Support**: Provides options for booting in BIOS or UEFI mode.
- **Error Handling**: Includes error handling to ensure smooth operation and user feedback throughout the VM setup process.

![QEMU-QuickBoot Interface](https://github.com/user-attachments/assets/1ac6dfcf-eeba-4276-8a6c-62dc26c513af)

## Installation & Execution

### Debian/Ubuntu
```bash
sudo apt update
sudo apt install qemu-system wget qemu-utils qemu-system-gui xdotool ovmf qemu-system zenity orchis-gtk-theme
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash QEMU-QuickBoot.sh
```

### Arch Linux
```bash
sudo pacman -Syu
sudo pacman -S qemu-full qemu-img libvirt virt-install virt-manager virt-viewer edk2 swtpm guestfs-tools libosinfo
sudo systemctl enable virt${drv}d.service;
sudo systemctl enable virt${drv}d{,-ro,-admin}.socket;
sudo systemctl enable libvirtd.service
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash QEMU-QuickBoot.sh
```

### Dependencies
- `qemu-system`
- `wget`
- `qemu-utils`
- `qemu-system-gui`
- `xdotool`
- `ovmf`
- `zenity`
- `orchis-gtk-theme`

### Running the Script

To run the script:

sudo bash QEMU-QuickBoot.sh

### SSH Access to VM:
Once the VM is running, you can SSH to it from the host machine. Use the following command to connect:

```bash
ssh -p 2222 (user)@localhost
```
Replace (user) with your actual username.


## Boot Modes

### 1. Boot from Any Connected Device

- **Description**: Boot the virtual machine directly from a connected device (USB drive, SD card, or internal/external SSD/HDD).
- **Potential Use Cases**: Testing bootable storage media without a physical machine or system reboot, rapid deployment of virtual environments.

### 2. Boot from File (.vhd, .img, .iso)

- **Description**: Boot a VM directly from any file, supporting formats like .vhd, .img, or an ISO file.
- **Supported File Types**: `.qcow2`, `.iso`, `.qcow`, `.raw`, `.vmdk`, `.vdi`, `.vhdx`, `.vhd`, `.cloop`, `.qed`, `.parallels`, `.bochs`, `.dmg`, `.blkdebug`
- **Potential Use Cases**: Quick setup for testing various file formats, booting any Linux live distro, WinPE ISO, etc.

### 3. ISO & Drive

- **Description**: Combines booting from an ISO or IMG file as a virtual DVD with a virtual disk file or physical device as a virtual drive.
- **Be Aware**: All physical devices are mounted as virtual internal drives in the VM.
- **Potential Use Cases**: Installing an OS using a virtual DVD and configuring a separate virtual disk, creating portable systems on USB devices or SD cards, deploying rescue tools on crashed drives without rebooting.

## Prompt Order

1. **Boot Source Selection**: Choose between booting from a connected device, a file, or an ISO & Drive setup.
2. **Connected Device Boot**: List connected devices, choose a device for VM boot, select BIOS or UEFI boot mode.
3. **File Boot**: Choose a file for VM boot, select BIOS or UEFI boot mode, specify RAM amount.
4. **ISO & Drive Boot**: Choose an ISO/IMG file for virtual DVD, choose a virtual disk file or physical device for VM boot, select BIOS or UEFI boot mode.
5. **RAM Size Selection**: Enter the amount of RAM for the VM in megabytes (MB).
6. **VM Execution**: Display selected choices and start the QEMU VM.
7. **Repeat or Exit**: Prompt to QuickBoot another VM or terminate the script.

## Potential Use Cases

- **Installing OS with Virtual DVD and Separate Virtual Disk**: For testing, development, and experimentation with various operating systems.
- **Mimicking Real Hardware Setup**: Deploy an installer DVD alongside a dedicated virtual disk.
- **Efficient OS Installation**: Install an OS to a virtual disk or second internal disk directly from your host desktop.
- **Creating Portable Systems**: Install an OS on USB devices or SD cards for on-the-go environments.
- **Deploying Rescue Tools**: Deploy rescue tools onto crashed drives without rebooting.

These use cases showcase the versatility and convenience of QEMU-QuickBoot, making it an invaluable tool for various scenarios ranging from OS installations to system recovery and development tasks.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues or pull requests if you find any bugs or have suggestions for improvements.

## Author

GLITCH LINUX 

www.glitchlinux.wtf  
info@glitchlinux.com

Happy QuickBoot!
