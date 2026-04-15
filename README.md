# QEMU-QuickBoot

**QEMU-QuickBoot** is a lightweight YAD-based GUI for rapid deployment of QEMU virtual machines — boot from physical devices, disk images, or ISO files in seconds, directly from your desktop.

![QEMU-QuickBoot](https://github.com/user-attachments/assets/83ee258e-395a-4278-b866-875ee1505089)

---

## What's New in 2026

This release is a significant update over the original Zenity-based version:

- **YAD replaces Zenity** — faster, more flexible, better-looking dialogs
- **USB Hotplug support** — attach and detach USB devices to a running VM without restarting
- **`usb-hotplug.sh` companion tool** — launches automatically alongside the VM, lists host USB devices via YAD, and attaches them with one click
- **USB 3.0 controller** — `qemu-xhci` included by default, no manual `-usb` flags needed
- **QEMU monitor socket** — exposes `/tmp/qemu-monitor.sock` for programmatic device management
- **Auto-launch hotplug tool** — the USB helper starts automatically after VM boot, no second terminal needed
- **`socat` integration** — hotplug commands sent directly to the QEMU monitor via Unix socket

---

<img width="1305" height="801" alt="hotplug-window-3" src="https://github.com/user-attachments/assets/dcf6d89a-d149-4eea-bfb1-2aca5dbb5dbb" />


## Overview

QEMU-QuickBoot is a Bash script that simplifies virtual machine deployment using QEMU. It provides a clean GUI workflow for selecting boot sources, RAM, and boot mode — then launches the VM with sensible defaults including KVM acceleration, USB 3.0, network forwarding, and SSH access.

> **Note:** Supported on Debian and Ubuntu-based distributions. Arch Linux support is available but UEFI boot is currently unstable on Arch.

---

## Key Features

- **YAD GUI** — lightweight alternative to Zenity with richer dialog support
- **Multiple boot modes** — physical device, disk image/ISO file, or ISO + drive combination
- **BIOS and UEFI** — OVMF-based UEFI support included
- **USB Hotplug** — attach/detach USB devices to a live VM via GUI, no reboot required
- **Dynamic RAM selection** — specify RAM per VM at launch
- **SSH port forwarding** — random port assigned per session, SSH into the VM from the host
- **KVM acceleration** — `-enable-kvm -cpu host` by default for near-native performance
- **Extra disk support** — attach additional virtual or physical disks at boot time

---

## Installation

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install qemu-system qemu-utils qemu-system-gui ovmf yad socat wget git orchis-gtk-theme -y
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash QEMU-QuickBoot.sh
```

### Arch Linux *(BIOS only — UEFI unstable)*

```bash
sudo pacman -Syu
sudo pacman -S qemu-full qemu-img edk2 yad socat git
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash QEMU-QuickBoot.sh
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `qemu-system` | Core VM engine |
| `qemu-utils` | Disk image tools |
| `qemu-system-gui` | QEMU display support |
| `ovmf` | UEFI firmware |
| `yad` | GUI dialogs |
| `socat` | QEMU monitor socket communication |
| `wget` | Downloads |
| `orchis-gtk-theme` | Dark GTK theme |

---

## Usage

```bash
sudo bash QEMU-QuickBoot.sh
```

The USB hotplug helper (`usb-hotplug.sh`) launches automatically a few seconds after the VM boots. Both scripts must be in the same directory.

### SSH into the VM

```bash
ssh -p <random_port> user@localhost
```

The assigned port is printed to the terminal at launch.

---

## Boot Modes

### 1. Boot from Connected Device
Boot directly from a USB drive, SD card, or internal/external disk. Useful for testing bootable media without rebooting the host.

### 2. Boot from File
Boot from `.vhd`, `.img`, `.iso`, `.qcow2`, `.vmdk`, `.vdi`, `.vhdx`, and other image formats.

### 3. ISO & Drive
Combine an ISO as a virtual DVD with a separate virtual or physical disk — ideal for OS installations inside the VM.

---

## USB Hotplug

The `usb-hotplug.sh` companion tool allows you to attach and detach USB devices to a running VM without restarting it.

**It launches automatically** when the VM boots. You can also run it manually at any time:

```bash
bash usb-hotplug.sh
```

### Features

- Lists all connected USB devices (root hubs filtered out)
- **Auto-attach** — sends `device_add` directly to QEMU via monitor socket
- **Manual command** — displays the attach/detach commands to paste into the terminal
- **Detach by ID** — remove devices using the generated `usb_BUS_ADDR` identifier
- **List attached devices** — queries the live QEMU monitor for currently attached USB devices

### Example

```
Host USB device:  Bus 002 Device 006 — Kingston DataTraveler 80
→ Select in YAD → Auto-attach
→ Guest OS sees /dev/sdb instantly, no reboot
```

---

## Prompt Order

1. **Boot source** — connected device / file / ISO & drive
2. **Device or file selection** — from list or file picker
3. **Extra disks** — optionally attach additional disks
4. **Boot mode** — BIOS or UEFI
5. **RAM size** — in MB (default: 2048)
6. **VM launches** — USB hotplug helper auto-starts
7. **Repeat or exit** — option to QuickBoot another VM

---

## Use Cases

- Boot and test any Linux live distro or WinPE ISO without rebooting the host
- Install an OS to a USB drive or SD card from within a VM
- Test bootable media before writing to hardware
- Deploy rescue tools to a crashed drive without touching the host system
- Rapidly spin up throwaway VMs for testing and development
- Hotplug USB storage, smartcard readers, or other devices into a live VM

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Contributing

Issues and pull requests welcome. Arch Linux UEFI support and multi-VM socket management are planned for future releases.

---

<img width="85" height="85" alt="QEMU-QuickBoot" src="https://github.com/user-attachments/assets/6ddec8b1-e5b0-4a9f-a793-b7c67b58236c" />

**GLITCH LINUX**  
[glitchlinux.wtf](https://glitchlinux.wtf) · info@glitchlinux.com

*Happy QuickBoot!*
