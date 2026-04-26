# QEMU-QuickBoot

**QEMU-QuickBoot** is a lightweight YAD-based GUI for rapid deployment of QEMU virtual machines — boot from physical devices, disk images, or ISO files in seconds, directly from your desktop.

<img width="1920" height="1080" alt="Screenshot_20260415_161233" src="https://github.com/user-attachments/assets/a1e188b9-7b9e-4bd7-9938-ef6c28421b7b" />

---

## What's New in 2026

This release is a major update over the original Zenity-based version, with two waves of changes.

### Spring 2026 — YAD rewrite

- **YAD replaces Zenity** - faster, more flexible, better-looking dialogs
- **USB Hotplug support** - attach and detach USB devices to a running VM without restarting
- **USB 3.0 controller** - `qemu-xhci` included by default
- **QEMU monitor socket** - exposes `/tmp/qemu-monitor.sock` for programmatic device management
- **Auto-launch companion panel** - settings panel starts automatically after VM boot, no second terminal needed
- **`socat` integration** - hotplug commands sent directly to the QEMU monitor via Unix socket

### April 2026 - Format autodetect, cross-distro UEFI, VM Session Settings panel

- **Smart boot-source handling** - ISOs now boot via `-cdrom` (not as raw drives), and `qcow2`/`vmdk`/`vdi`/`vhdx`/`vhd` images are mounted with their actual format instead of being forced to `raw`. Same applies to extra disks.
- **Cross-distro UEFI** - OVMF firmware path is now autodetected (Arch's `/usr/share/edk2/x64/OVMF.4m.fd`, Debian's `/usr/share/qemu/OVMF.fd`, Fedora's `/usr/share/edk2/ovmf/OVMF_CODE.fd`, etc.). Tested on Garuda Linux April 2026 — UEFI boot works on Arch out of the box. The "UEFI unstable on Arch" caveat from the previous README was a hardcoded path bug, not an actual incompatibility.
- **USB toggle now actually disables USB** - unchecking "Enable USB Support" at launch removes the USB controllers from the VM (not just the helper script)
- **Companion panel renamed** - `usb-hotplug.sh` is now `quickboot-settings.sh` and the window is titled **VM Session Settings**, reflecting that it now controls more than just USB
- **Top-level menu grouped** - USB Devices / Network / Storage / VM Power
- **Smart SSH forward** - view the current SSH port, add a new SSH host port live, or copy the full `ssh -p N user@localhost` command to clipboard (xclip / wl-copy / xsel auto-detected)
- **Manual IPv4 / subnet config** - set a custom CIDR, gateway, DHCP start, and DNS for the VM. The panel queues the config and offers "Save & Restart Now" — the parent script automatically re-launches QEMU with the same drives, RAM, boot mode, and SSH port, but with the new netdev applied.
- **VM Power sub-menu** - soft reset, ACPI shutdown, force-quit, and restart-with-pending-config, all driven over HMP

---

<img width="1305" height="801" alt="hotplug-window-3" src="https://github.com/user-attachments/assets/dcf6d89a-d149-4eea-bfb1-2aca5dbb5dbb" />

## Overview

QEMU-QuickBoot is a Bash tool that simplifies virtual machine deployment using QEMU. It provides a clean GUI workflow for selecting boot sources, RAM, and firmware — then launches the VM with sensible defaults including KVM acceleration, USB 3.0, network forwarding, and SSH access.

The companion **VM Session Settings** panel (`quickboot-settings.sh`) launches automatically alongside the VM and gives you live control over USB devices, networking, storage, and VM power state — without ever leaving the GUI.

> **Note:** Supported on Debian/Ubuntu and Arch-based distributions (CachyOS, EndeavourOS, Manjaro, Garuda). Both BIOS and UEFI boot are tested on Arch as of April 2026.

---

## Key Features

- **YAD GUI** — lightweight alternative to Zenity with richer dialog support
- **Multiple boot modes** — physical device, disk image/ISO file, or ISO + drive combination
- **Format autodetection** — ISOs boot as CD-ROMs; `qcow2`/`vmdk`/`vdi`/`vhdx`/`vhd` boot with their real format; block devices and `.img` boot raw. No more surprise corruption from forcing `format=raw` on a qcow2.
- **Cross-distro UEFI** — OVMF firmware path is now autodetected, so UEFI boot works out of the box on Arch (`/usr/share/edk2/x64/OVMF.4m.fd`), Debian/Ubuntu, and Fedora without per-distro patches. Falls back to BIOS with a clear error dialog if no firmware is found.
- **BIOS and UEFI** — OVMF-based UEFI support included
- **USB Hotplug** — attach/detach USB devices to a live VM via GUI, no reboot required
- **Dynamic RAM selection** — specify RAM per VM at launch
- **SSH port forwarding** — random port assigned per session, persists across in-session restarts
- **Live IPv4/subnet config** — change the VM's network on the fly with a clean restart
- **KVM acceleration** — `-enable-kvm -cpu host` by default for near-native performance
- **Extra disk support** — attach additional virtual or physical disks at boot time, each with its own auto-detected format

<img width="913" height="684" alt="Screenshot_20260415_162458-1" src="https://github.com/user-attachments/assets/34c5fd09-aeb7-4539-a1de-3cd62291052a" />

---

## Installation

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install qemu-system qemu-utils qemu-system-gui ovmf yad socat wget git orchis-gtk-theme -y
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash qemu-quickboot.sh
```

### Arch Linux / CachyOS / EndeavourOS / Garuda / Manjaro

```bash
sudo pacman -Sy
sudo pacman -S --needed qemu-desktop edk2-ovmf yad socat git
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash qemu-quickboot.sh
```

> **Tip for live ISOs:** if `pacman` reports gstreamer or libcbor version conflicts (common on weeks-old live media), add `--overwrite='*'` to bypass the version skew without doing a full system upgrade:
> ```bash
> sudo pacman -S --needed --overwrite='*' qemu-desktop edk2-ovmf yad socat git
> ```

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

Optional but recommended for SSH-command-copy in the settings panel: `xclip`, `wl-copy`, or `xsel`.

---

## Usage

```bash
sudo bash qemu-quickboot.sh
```

The VM Session Settings panel (`quickboot-settings.sh`) launches automatically a few seconds after the VM boots, provided USB support was enabled at launch. Both scripts must be in the same directory.

You can also run the panel manually at any time while a VM is active:

```bash
bash quickboot-settings.sh
```

### SSH into the VM

```bash
ssh -p <random_port> user@localhost
```

The assigned port is printed to the terminal at launch. The Settings panel (Network → SSH Quick-Forward) can also copy the full command to your clipboard.

---

## Boot Modes

### 1. Boot from Connected Device
Boot directly from a USB drive, SD card, or internal/external disk. Useful for testing bootable media without rebooting the host.

### 2. Boot from File
Boot from `.iso`, `.img`, `.qcow2`, `.vmdk`, `.vdi`, `.vhd`, or `.vhdx`. The format is autodetected — ISOs boot as a CD-ROM, everything else boots as a drive with its native format.

### 3. ISO & Drive
Combine an ISO as a virtual DVD with a separate virtual or physical disk — ideal for OS installations inside the VM.

---

## VM Session Settings Panel

The companion panel (`quickboot-settings.sh`) gives you live control over a running VM. It launches automatically alongside the VM and is organized into four sections.

### USB Devices

- **Attach** — pick from a live `lsusb` list and hotplug the device into the VM
- **Detach** — list currently attached devices and detach one cleanly
- **Session Device Log** — see everything attached/detached this session

### Network

- **View Network Info** — SLIRP defaults plus live `info usernet` output
- **SSH Quick-Forward** — view current SSH port, copy `ssh -p N user@localhost` to clipboard, or add a new SSH host port live
- **Add Port Forward** / **Remove Port Forward** — generic TCP/UDP port redirection
- **IPv4 / Subnet Config** — override the SLIRP subnet (network CIDR, gateway, DHCP start, DNS). QEMU can't change netdev parameters on a live VM, so the panel queues the new config and triggers a clean restart with the same drives, RAM, boot mode, and SSH port — only the network changes.

### Storage

- **Add storage device** — hotplug a virtual disk file or physical block device. Format is autodetected for virtual disks; physical devices use raw.
- **Remove storage device** — detach a previously hot-added device (with an unmount-first reminder)
- **View current storage layout** — see hot-added devices plus full `info block` output

### VM Power

- **Send Reset** — `system_reset` (hard reboot)
- **Send ACPI Shutdown** — `system_powerdown` (graceful)
- **Restart VM (apply pending config)** — re-launch with queued IPv4/network changes
- **Force Quit VM** — immediate `quit` over HMP, discards any pending restart

---

## Use Cases

- Boot and test any Linux live distro or WinPE ISO without rebooting the host
- Install an OS to a USB drive or SD card from within a VM
- Test bootable media before writing to hardware
- Deploy rescue tools to a crashed drive without touching the host system
- Rapidly spin up throwaway VMs for testing and development
- Hotplug USB storage, smartcard readers, or other devices into a live VM
- Test how a guest reacts to changing network configurations (custom subnets, gateways, DNS)

---

## Design Philosophy

QEMU-QuickBoot is **not** a VirtualBox/VMware/virt-manager replacement. It's a `qemu-system-x86_64` invocation that you can drive with a mouse — for the cases where typing the command line by hand is friction, but spinning up a managed VM is overkill.

The pre-boot path is intentionally short (sub-20-second boot from prompt to running VM). Anything that adds depth — IPv4 config, port forwards, storage hotplug — lives in the **VM Session Settings** panel that opens *after* the VM is already running. This keeps the launch flow fast while still letting you tune the VM in flight.

The tool deliberately does not aim to be a persistent VM library, a snapshot manager, or a multi-VM hypervisor. One QEMU instance per QuickBoot, by design.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Contributing

Issues and pull requests welcome. Multi-VM session support, ARM/aarch64 boot, and headless smoke-test modes are on the radar for future releases.

---

<img width="85" height="85" alt="QEMU-QuickBoot" src="https://github.com/user-attachments/assets/6ddec8b1-e5b0-4a9f-a793-b7c67b58236c" />

**GLITCH LINUX**
[glitchlinux.wtf](https://glitchlinux.wtf) · info@glitchlinux.com

*Happy QuickBoot!*
