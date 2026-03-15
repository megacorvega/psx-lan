# emu-sff

A streamlined setup utility to serve game files over a local Ethernet connection. 

`emu-sff` configures a Linux host machine to act as an isolated file host for legacy consoles (like the PlayStation 2). Using Docker, it spins up a DHCP server and an older-protocol SMB share (SMBv1), while automatically handling power-management tweaks to ensure fast and reliable game loading over the network.

## Prerequisites
* A Debian/Ubuntu-based Linux machine (uses `apt-get` and `netplan`).
* Root/sudo privileges.
* An active Wi-Fi connection (WLAN) and an Ethernet port (LAN) connected to your console.

## Usage

To configure your system and start the services, run the setup script with root privileges:

```bash
chmod +x emu-sff.sh
sudo ./emu-sff.sh setup
```

During execution, the script will prompt you to define your LAN interface, WLAN interface, storage path (where your games are located), and configuration path.

## What the Setup Script Does

The `emu-sff.sh` script is interactive and will ask for your consent before proceeding with each of the following configuration steps:

1. **Installs Dependencies**: Configures the official Docker apt repository to install `docker-ce` and `docker-compose-plugin`, and installs `wireless-tools` from the standard repositories.
2. **Configures Static IP**: Uses Netplan to assign a static IP address (`192.168.2.1`) to your specified Ethernet (LAN) interface so the console can connect directly.
3. **Disables Wi-Fi Power Management**: Turns off power-saving features on your Wi-Fi interface to fix slow SMB transfer speeds, and creates a systemd service to keep this setting applied after reboots.
4. **Configures and Starts Docker Services**: 
    * Generates a `dnsmasq.conf` file to act as an isolated DHCP server.
    * Generates an `smb.conf` file configured with the NT1 protocol (SMBv1), which is required for legacy console compatibility.
    * Creates a `docker-compose.yml` file and spins up the Samba and Dnsmasq containers in the background.

## Checking Status & Uninstalling

You can easily check the health and status of all components (Docker, Samba, DHCP, IP assignment, and Wi-Fi power management) using the script.

```bash
sudo ./emu-sff.sh status
```

To safely remove the Docker containers, Netplan configuration, and restore your Wi-Fi power management, run:
```bash
sudo ./emu-sff.sh uninstall
```

## Connection Details

Once the setup is complete, your retro console can connect using the following details:
* **IP Gateway:** `192.168.2.1`
* **SMB Share Path:** `\\192.168.2.1\share`