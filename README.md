# psx-lan

A streamlined setup utility to serve game files over a PlayStation 2 Ethernet connection. 

`psx-lan` configures a Linux host machine to act as a bridge between your Wi-Fi network and the PS2. Using Docker, it spins up a DHCP/DNS server and a PS2-compatible SMB share (SMBv1), while automatically handling network routing, IP forwarding, and power-management tweaks to ensure fast and reliable game loading.

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

1. **Installs Dependencies**: Installs `docker.io`, `docker-compose`, `iptables`, `iptables-persistent`, `netfilter-persistent`, and `wireless-tools` from the standard repositories.
2. **Enables IP Forwarding**: Modifies `/etc/sysctl.conf` to allow the kernel to route network traffic between your Wi-Fi and Ethernet interfaces.
3. **Configures Static IP**: Uses Netplan to assign a static IP address (`192.168.2.1`) to your specified Ethernet (LAN) interface so the PS2 can connect directly.
4. **Sets Up Iptables Routing**: Creates `MASQUERADE` and `FORWARD` rules to route PS2 internet traffic through your Wi-Fi interface. These rules are saved persistently.
5. **Disables Wi-Fi Power Management**: Turns off power-saving features on your Wi-Fi interface to fix slow SMB transfer speeds, and creates a systemd service to keep this setting applied after reboots.
6. **Configures and Starts Docker Services**: 
    * Generates a `dnsmasq.conf` file to act as a DHCP server for the PS2.
    * Generates an `smb.conf` file configured with the NT1 protocol (SMBv1), which is required for PS2 compatibility.
    * Creates a `docker-compose.yml` file and spins up the Samba and Dnsmasq containers in the background.

## Connection Details

Once the setup is complete, your PS2 can connect using the following details:
* **PS2 IP Gateway:** `192.168.2.1`
* **SMB Share Path (From PS2):** `\\192.168.2.1\share`
