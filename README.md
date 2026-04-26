# QEMU-QuickBoot

YAD GUI Interface for quick and easy deployment of QEMU Virtual Machines

<img width="1920" height="1080" alt="Screenshot_20260415_161233" src="https://github.com/user-attachments/assets/a1e188b9-7b9e-4bd7-9938-ef6c28421b7b" />

---

Works on Debian, Ubuntu, Arch, CachyOS, EndeavourOS, Garuda, Manjaro, Fedora & RHEL Both BIOS and UEFI. Tested as of April 2026.

## What does the utilty do?

Prompts user with yad dialogs that you through:

1. Pick a boot source (a connected device, a disk image, or an ISO + drive combo)
2. Optionally attach extra disks (phydical or virtual)
3. Select Firmware type (BIOS or UEFI)
4. Set RAM size (Manually in MB)

Then it launches QEMU with KVM acceleration, USB 3.0, and SSH port forwarding on a random host port. A companion panel called **VM Session Settings** opens alongside the VM so you can hotplug USB devices, add port forwards, change the guest's IPv4 subnet, or shut the VM down cleanly. All without restarting QEMU.

The whole pre-boot flow takes about 15 seconds.

## What's new in 2026

The big rewrite swapped Zenity for YAD and added a companion panel with USB hotplugging, network controls, and storage hotplug. The April 2026 update added:

- **Format autodetection.** ISOs boot via `-cdrom`. `qcow2`, `vmdk`, `vdi`, `vhdx`, `vhd` boot with their actual format. Block devices boot raw. The previous version forced `format=raw` on everything, which silently corrupted qcow2 images.
- **Cross-distro UEFI.** OVMF firmware is autodetected. Works on Arch (`/usr/share/edk2/x64/OVMF.4m.fd`), Debian (`/usr/share/qemu/OVMF.fd`), and Fedora without per-distro patches. The previous "UEFI unstable on Arch" warning in the README was a hardcoded path bug, not an actual incompatibility.
- **USB toggle actually works now.** Unchecking "Enable USB Support" at launch removes the USB controllers from the VM, not just the helper script.
- **Companion panel renamed** from `usb-hotplug.sh` to `quickboot-settings.sh`. The window is titled "VM Session Settings" because it does more than USB now.
- **Smart SSH forward.** View the current port, add a new one live, or copy `ssh -p N user@localhost` to clipboard (xclip / wl-copy / xsel).
- **Manual IPv4 config.** Set a custom CIDR, gateway, DHCP start, and DNS. QEMU can't change netdev parameters on a running VM, so the panel queues the change and offers "Save & Restart Now". The parent script re-launches QEMU with the same drives, RAM, boot mode, and SSH port, just with the new network.
- **VM power controls.** Soft reset, ACPI shutdown, force-quit, restart-with-pending-config. All over HMP.

<img width="1305" height="801" alt="hotplug-window-3" src="https://github.com/user-attachments/assets/dcf6d89a-d149-4eea-bfb1-2aca5dbb5dbb" />

## [🔗 QEMU-QuickBoot-v1.5 ](https://github.com/GlitchLinux/QEMU-QuickBoot/releases/tag/QEMU-QuickBoot-v1.5) Installers
### For Debian Based Distros:
## [![debian](https://github.com/user-attachments/assets/03adedd6-ac80-4cfc-961a-bb22315eaf9d)](https://...deb-url)![Ubuntu](https://github.com/user-attachments/assets/fa705583-84ba-46d6-8601-9e22bb182ff7)![Mint](https://github.com/user-attachments/assets/4955d558-791a-4670-a6b1-0090e5566c89) [.deb](https://github.com/GlitchLinux/QEMU-QuickBoot/releases/download/QEMU-QuickBoot-v1.5/qemu-quickboot-v1.5-1_amd64.deb)

### For RHEL Based Distros:
## [![rhel](https://github.com/user-attachments/assets/10f6e927-68f9-45e2-a886-549b333587f2)](https://...rpm-url)![cent](https://github.com/user-attachments/assets/80e898fa-4861-4a94-9860-355c1ad43520)![fedora](https://github.com/user-attachments/assets/924dbe3e-d958-4405-83af-e92f0d630b75) [.rpm](https://github.com/GlitchLinux/QEMU-QuickBoot/releases/download/QEMU-QuickBoot-v1.5/qemu-quickboot-1.5-1.fc41.noarch.rpm)

### For Arch Based Distros: 
## [![rhel](https://github.com/user-attachments/assets/0975c6d8-d100-4c5d-9e17-9177aecfc988)](https://...rpm-url)![Manjaro](https://github.com/user-attachments/assets/a93d0c08-f3e6-498e-82a2-bb1432a2a9a8)![endevour](https://github.com/user-attachments/assets/ce007302-ddef-4fa0-93cc-2f0f3e5e7e27) [.zst](https://github.com/GlitchLinux/QEMU-QuickBoot/releases/download/QEMU-QuickBoot-v1.5/qemu-quickboot-1.5-1-any.pkg.tar.zst)

### Test the utility without installing it:

### Debian / Ubuntu

```bash
sudo apt update
sudo apt install qemu-system qemu-utils qemu-system-gui ovmf yad socat wget git -y
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash qemu-quickboot.sh
```

### Arch / CachyOS / EndeavourOS / Garuda / Manjaro

```bash
sudo pacman -Sy
sudo pacman -S --needed qemu-desktop edk2-ovmf yad socat git
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash qemu-quickboot.sh
```

If you're on a live ISO and pacman complains about gstreamer or libcbor version conflicts (CachyOS and Garuda live media tend to lag a few weeks behind the rolling repos), add `--overwrite='*'`:

```bash
sudo pacman -S --needed --overwrite='*' qemu-desktop edk2-ovmf yad socat git
```

That bypasses the version skew without needing a full system upgrade.

### Fedora / CentOS / RHEL / Alma / Rocky

```bash
sudo dnf update
sudo dnf install -y qemu-system-x86 qemu-img edk2-ovmf yad socat usbutils xclip xdpyinfo git
git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo bash qemu-quickboot.sh
```

## Usage

```bash
sudo bash qemu-quickboot.sh
```

The settings panel auto-launches a few seconds after the VM boots, as long as USB support was enabled at launch. Both scripts must be in the same directory.

You can also run the panel manually any time a VM is alive:

```bash
bash quickboot-settings.sh
```

To SSH into the guest:

```bash
ssh -p <random_port> user@localhost
```

The port is printed to the terminal at launch. The settings panel can also copy the full command to clipboard via Network → SSH Quick-Forward.

### Optional clipboard tools

For the "copy SSH command to clipboard" feature in the settings panel, install one of: `xclip`, `wl-clipboard`, or `xsel`. Most desktops already have at least one.

## Boot modes

**Boot from connected device.** Pick a real disk by `/dev/sdX` from a list of attached drives. Useful for testing a USB live distro or rescuing a crashed system without rebooting.

**Boot from file.** Point at an ISO, IMG, QCOW2, VMDK, VDI, VHD, or VHDX. The format is autodetected. ISOs boot as a CD-ROM; the rest boot as drives with their native format.

**ISO & Drive.** Combine both: an ISO as virtual DVD plus a separate disk (virtual or physical). This is the OS-install workflow.

## VM Session Settings panel

Four sections. Everything is driven over the QEMU monitor socket at `/tmp/qemu-monitor.sock`.

**USB Devices.** Attach (picks from `lsusb`), detach (lists what you've attached this session), and a session log of everything that's been hotplugged.

**Network.** View the SLIRP defaults and live `info usernet` output. Add or remove generic TCP/UDP port forwards. The SSH Quick-Forward sub-menu shows the current SSH port, copies the ssh command to clipboard, or adds a new host port live. The IPv4/Subnet Config form lets you override network CIDR, gateway, DHCP start, and DNS, then triggers a clean restart with the same drives, RAM, boot mode, and SSH port.

**Storage.** Hotplug a virtual disk file or physical block device into the running VM. Format is autodetected for files; physical devices are raw. Removing a hot-added device prompts you to unmount first inside the guest. Also shows the full `info block` layout.

**VM Power.** `system_reset` (hard reboot), `system_powerdown` (ACPI shutdown), restart with pending config, or force-quit (HMP `quit`). Force-quit clears any pending restart so the parent script doesn't relaunch.

## What it's good for

- Test a live ISO without rebooting
- Install an OS onto a USB stick from inside a VM
- Try out bootable media before writing it to real hardware
- Spin up a throwaway VM for testing
- Hotplug a USB stick, smartcard reader, or external drive into a running guest
- Stress-test a guest's reaction to network changes (custom subnets, gateways, DNS)

## What it isn't

Not a VirtualBox replacement. Not a VM library, not a snapshot manager, not a multi-VM hypervisor. One QEMU instance per launch, by design.

The launch flow is short on purpose. Anything that adds friction goes into the settings panel, which only opens after the VM is already running. The two scripts together total about 1700 lines of bash and have no daemon, no config file, and no state outside `/tmp`.

## Dependencies

| Package | What it's for |
|---|---|
| `qemu-system-x86_64` | The VM itself |
| `qemu-img` | Disk image utilities |
| `ovmf` / `edk2-ovmf` | UEFI firmware |
| `yad` | All the GUI dialogs |
| `socat` | Talking to the QEMU monitor socket |
| `git` | Cloning this repo |

Optional: `xclip`, `wl-clipboard`, or `xsel` for the SSH-copy feature.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. On the radar: multi-VM session support, ARM/aarch64 guest boot, and a headless smoke-test mode.

<img width="85" height="85" alt="QEMU-QuickBoot" src="https://github.com/user-attachments/assets/6ddec8b1-e5b0-4a9f-a793-b7c67b58236c" />

**GLITCH LINUX**

[glitchlinux.wtf](https://glitchlinux.wtf) · info@glitchlinux.com
