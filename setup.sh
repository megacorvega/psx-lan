#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

echo "======================================"
echo "   psx-lan - Docker Setup script      "
echo "======================================"
echo ""

prompt_step() {
    local step_title="$1"
    local step_desc="$2"
    echo ""
    echo "$step_title"
    echo "Description: $step_desc"
    while true; do
        read -p "Do you want to proceed with this step? [Y/n]: " consent
        consent=${consent:-Y}
        case "$consent" in
            [Yy]* ) return 0 ;;
            [Nn]* ) return 1 ;;
            * ) echo "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# 1. Interactive Prompts
AVAILABLE_INTERFACES=$(ls /sys/class/net | grep -v 'lo' | tr '\n' ' ' | sed 's/ $//')
RECOMMENDED_LAN=$(ls /sys/class/net | grep -E '^en|^eth' | head -n 1)
RECOMMENDED_WLAN=$(ls /sys/class/net | grep -E '^wl|^wlan' | head -n 1)

echo "Available network interfaces: $AVAILABLE_INTERFACES"

read -p "Enter your LAN interface [Default: ${RECOMMENDED_LAN:-eth0}]: " LAN_IF
LAN_IF=${LAN_IF:-${RECOMMENDED_LAN:-eth0}}

read -p "Enter your WLAN interface [Default: ${RECOMMENDED_WLAN:-wlan0}]: " WLAN_IF
WLAN_IF=${WLAN_IF:-${RECOMMENDED_WLAN:-wlan0}}
read -p "Enter the absolute path for your shared STORAGE (e.g., /mnt/games): " STORAGE_PATH
read -p "Enter the absolute path for your CONFIGURATION files (e.g., /opt/psx-server): " CONFIG_PATH

# Ensure directories exist
for dir in "$STORAGE_PATH" "$CONFIG_PATH/samba" "$CONFIG_PATH/dnsmasq"; do
    if [ ! -d "$dir" ]; then
        echo "Creating directory $dir..."
        mkdir -p "$dir"
        chmod 777 "$dir"
    fi
done

if prompt_step "[1/4] Installing dependencies" "This will install Docker via the official Docker apt repository, along with wireless-tools."; then
  # Uninstall any conflicting unofficial packages just in case
  apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc > /dev/null 2>&1

  apt-get update
  apt-get install -y ca-certificates curl wireless-tools

  # Add Docker's official GPG key
  install -m 0755 -d /etc/apt/keyrings
  . /etc/os-release
  curl -fsSL https://download.docker.com/linux/$ID/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Add the repository to Apt sources
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID \
    $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine and the Compose plugin
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "Skipping dependency installation."
fi

if prompt_step "[2/4] Configuring static IP on $LAN_IF" "This will configure $LAN_IF with a static IP of 192.168.2.1 using Netplan, so the PS2 can connect directly."; then
  cat <<EOF > /etc/netplan/99-psx-lan.yaml
network:
  version: 2
  ethernets:
    $LAN_IF:
      addresses: [192.168.2.1/24]
EOF
  netplan apply
else
  echo "Skipping static IP configuration."
fi

if prompt_step "[3/4] Disabling Wi-Fi Power Management for $WLAN_IF" "This turns off Wi-Fi power saving to fix slow SMB transfer speeds, and creates a systemd service to persist this setting. Recommended."; then
  iw dev $WLAN_IF set power_save off
  # Create a systemd service to ensure power management stays off after reboots
  cat <<EOF > /etc/systemd/system/wifi-power-save-off.service
[Unit]
Description=Disable WiFi Power Management
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iw dev $WLAN_IF set power_save off

[Install]
WantedBy=multi-user.target
EOF
  systemctl enable wifi-power-save-off.service > /dev/null
  systemctl start wifi-power-save-off.service
else
  echo "Skipping Wi-Fi Power Management changes."
fi

if prompt_step "[4/4] Creating Configuration Files and Starting Docker" "This creates DNS/DHCP (dnsmasq) and SMB config files, generates a docker-compose.yml file, and starts the background services."; then
  cd "$CONFIG_PATH"

  # Create dnsmasq.conf
  cat <<EOF > "$CONFIG_PATH/dnsmasq/dnsmasq.conf"
interface=$LAN_IF
bind-dynamic
domain-needed
bogus-priv
dhcp-range=192.168.2.2,192.168.2.100,12h
EOF

  # Create smb.conf
  cat <<EOF > "$CONFIG_PATH/samba/smb.conf"
[global]
server min protocol = NT1
workgroup = WORKGROUP
usershare allow guests = yes
map to guest = bad user
allow insecure wide links = yes

[share]
Comment = shared folder
Path = /share
Browseable = yes
Writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
Public = yes
Guest ok = yes
force user = root
follow symlinks = yes
wide links = yes
EOF

  # Create docker-compose.yml
  cat <<EOF > "$CONFIG_PATH/docker-compose.yml"
services:
  samba:
    image: dperson/samba
    container_name: psx-samba
    network_mode: "host"
    volumes:
      - $STORAGE_PATH:/share
      - ./samba/smb.conf:/etc/samba/smb.conf:ro
    restart: unless-stopped

  dnsmasq:
    image: strm/dnsmasq
    
    container_name: psx-dhcp
    network_mode: "host"
    cap_add:
      - NET_ADMIN
    volumes:
      - ./dnsmasq/dnsmasq.conf:/etc/dnsmasq.conf:ro
    restart: unless-stopped
EOF

  echo "Starting Docker containers..."
  docker compose up -d
else
  echo "Skipping Configuration and Docker setup."
fi

echo ""
echo "=========================================================="
echo " Setup Complete! "
echo "=========================================================="
echo "Services are now running in Docker."
echo "Configuration files are accessible at: $CONFIG_PATH"
echo "Game Storage folder is at:             $STORAGE_PATH"
echo ""
echo "PS2 IP Gateway: 192.168.2.1"
echo "SMB Share Path: \\\\<Ubuntu_WLAN_IP>\\share  (or \\\\192.168.2.1\\share from PS2)"
echo "=========================================================="