# QEMU-QuickBoot
QEMU-QuickBoot - Zenity GUI Interface for quick and easy deployment of QEMU Virtual Machines

![Screenshot_2024-07-17_21-59-42](https://github.com/user-attachments/assets/4228f66a-cefe-4c85-bd99-26ad465dd354)

QEMU QuickBoot is a Bash script designed to simplify the deployment of Virtual Machines (VMs) using QEMU, with a user-friendly GUI interface provided by Zenity. It allows users to quickly create and boot VMs directly from their desktop, using connected physical devices or bootable image files as the source media. User-Friendly Interface, Utilizes Zenity to present a straightforward interface for selecting VM boot sources and configurations. Multiple Boot Options: Supports booting VMs from connected devices, various file formats (.vhd, .img, .iso), and ISO images with virtual drives or physical devices. Dynamic RAM Configuration: Allows users to specify the amount of RAM (in MB) allocated to the VM. BIOS and UEFI Support: Provides options for booting in BIOS or UEFI mode depending on the user's preference. Includes error handling to ensure smooth operation and user feedback throughout the VM setup process.



![qq](https://github.com/user-attachments/assets/1ac6dfcf-eeba-4276-8a6c-62dc26c513af)



Download QEMU-QuickBoot.sh bash script and install the dependencies to use!

DEPENDENCIES:

qemu-system-x86_64
wget
qemu-utils
qemu-system-gui
xdotool
ovmf
zenity
Lsblk

You can install these dependencies on Debian/Ubuntu with:

sudo apt update && sudo apt install qemu-system wget qemu-utils qemu-system-gui xdotool ovmf qemu-system-x86_64 zenity lsblk

Run the script:
./quickboot.sh

QEMU QuickBoot is a hassle-free creation of virtual machines with configurable boot options. Ideal for testing or development scenarios where VM setup needs to be efficient and straightforward.

Boot Modes
1. Boot from Any Connected Device
Description:
Allows you to boot the virtual machine directly from a connected device (USB drive, SD card, or internal/external SSD/HDD).
Potential Use Cases:
Testing bootable storage media without the need for a physical machine or system reboot.
Rapid deployment of virtual environments using any connected physical device in both BIOS and UEFI modes.

2. Boot from File (.vhd, .img, .iso..)
Description:
Boots a VM directly from any file, supporting formats like .vhd, .img, or an ISO file, with options for both BIOS and UEFI modes.
Supported File Types:

.qcow2, .ISO, .qcow, .raw, .vmdk, .vdi, .vhdx, .vhd, .cloop, .qed, .parallels, .bochs, .dmg, .blkdebug

Potential Use Cases:
Quick setup for testing .ISOs, .IMGs, .VHDs, etc.
Great for testing custom ISO files quickly without rebooting your computer.
Perfect for booting any Linux live distro, WinPE ISO, etc., seamlessly in a separate window on your desktop.
Efficient tool for development, testing, and debugging using pre-configured virtual disks, installation media files, or raw disk images.

3. ISO & Drive (Boot an ISO/IMG file as a virtual DVD along with a Disk File or Physical Device)
Description:
Combines booting from an ISO or IMG file (as a virtual DVD installation/rescue media) with choosing a virtual disk file or any physical device to be set up as a virtual drive, with options for both BIOS and UEFI modes.
Be Aware:

ALL physical devices are mounted as virtual INTERNAL drives in the Virtual Machine!
QEMU reads externally connected USB devices, SD cards, as well as built-in drives HDD/SDD PCIeNVME as internal devices.
Potential Use Cases:

Installing any operating system using a virtual DVD and configuring a separate virtual disk.
Mimicking a real hardware setup with an installer DVD and a dedicated disk.
Great for installing an OS to a virtual disk and/or a 2nd internal disk directly from your host desktop.
Creating portable systems by installing to a connected USB device or SD cards.
Perfect for deploying rescue tools on crashed drives without ever rebooting.
Prompt Order
Boot Source Selection:
Choose between booting from a connected device, a file (.vhd, .img, .iso), or an ISO & Drive setup.
Connected Device Boot:
If selected:
List connected devices (USB, SD card, SSD/HDD).
Choose a device for VM boot.
Select BIOS or UEFI boot mode.
File Boot:
If selected:
Choose a file for VM boot (.vhd, .img, .iso).
Select BIOS or UEFI boot mode.
Select the amount of RAM for the VM in MB and proceed. (Attention!: 4000MB=4GB)
ISO & Drive Boot:
Choose an ISO/IMG file for virtual DVD (installer media).
Choose a virtual disk file or a physical device for VM boot.
Select BIOS or UEFI boot mode.
RAM Size Selection:
Enter the amount of RAM for the VM in megabytes (MB).
Note: Be cautious not to allocate more RAM than the host system can spare, as this may prevent the VM from starting.

VM Execution:
Display selected choices.
Start the QEMU VM with the specified parameters.
Repeat or Exit:
Prompt to QuickBoot another VM.
If the user chooses to exit, the script terminates.
Potential Use Cases:
Installing any Operating System with Virtual DVD and Separate Virtual Disk:

Utilize the script to install a wide range of operating systems by employing a virtual DVD for the installation media and configuring a separate virtual disk for the OS. This allows for testing, development, and experimentation with various operating systems in a virtualized environment.
Mimicking Real Hardware Setup with Installer DVD and Dedicated Disk:

Simulate a realistic hardware setup by deploying an installer DVD alongside a dedicated virtual disk. This use case is valuable for scenarios where the goal is to replicate the conditions of a physical machine, providing an authentic environment for testing and development.
Efficient OS Installation to Virtual and Internal Disks:

Facilitate swift and hassle-free installations by directly installing an operating system to a virtual disk or a second internal disk from your host desktop. This is particularly useful for users who need to set up new systems quickly for development or testing purposes.
Creating Portable Systems on USB Devices or SD Cards:

Leverage the script to create portable and self-contained systems by installing an operating system on connected USB devices or SD cards. This allows for the creation of on-the-go environments that can be easily transported and run on different host machines without the need for a system reboot.
Deploying Rescue Tools on Crashed Drives Without Rebooting:

Employ the script for deploying rescue tools onto crashed drives without the necessity of a system reboot. This enables users to perform recovery and analysis tasks on malfunctioning systems directly from their host desktop, streamlining the rescue process and minimizing downtime.
These use cases showcase the versatility and convenience offered by the QEMU QuickBoot script, making it an invaluable tool for a variety of scenarios ranging from OS installations to system recovery and development tasks.
