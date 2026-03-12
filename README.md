# psx-lan

A streamlined setup utility to serve game files over a PlayStation 2 Ethernet connection. 

`psx-lan` configures a Linux host machine to act as an isolated file host for your PS2. Using Docker, it spins up a DHCP server and a PS2-compatible SMB share (SMBv1), while automatically handling power-management tweaks to ensure fast and reliable game loading.

## Prerequisites
* A Debian/Ubuntu-based Linux machine (uses `apt-get` and `netplan`).
* Root/sudo privileges.
* An active Wi-Fi connection (WLAN) and an Ethernet port (LAN) connected to your PS2.

## Usage

To configure your system and start the services, run the setup script with root privileges:

```bash
sudo ./setup.sh
```

During execution, the script will prompt you to define your LAN interface, WLAN interface, storage path (where your games are located), and configuration path.

## What the Setup Script Does

The `setup.sh` script is interactive and will ask for your consent before proceeding with each of the following configuration steps:

1. **Installs Dependencies**: Configures the official Docker apt repository to install `docker-ce` and `docker-compose-plugin`, and installs `wireless-tools` from the standard repositories.
2. **Configures Static IP**: Uses Netplan to assign a static IP address (`192.168.2.1`) to your specified Ethernet (LAN) interface so the PS2 can connect directly.
3. **Disables Wi-Fi Power Management**: Turns off power-saving features on your Wi-Fi interface to fix slow SMB transfer speeds, and creates a systemd service to keep this setting applied after reboots.
4. **Configures and Starts Docker Services**: 
    * Generates a `dnsmasq.conf` file to act as an isolated DHCP server for the PS2.
    * Generates an `smb.conf` file configured with the NT1 protocol (SMBv1), which is required for PS2 compatibility.
    * Creates a `docker-compose.yml` file and spins up the Samba and Dnsmasq containers in the background.

## Connection Details

Once the setup is complete, your PS2 can connect using the following details:
* **PS2 IP Gateway:** `192.168.2.1`
* **SMB Share Path (From PS2):** `\\192.168.2.1\share`