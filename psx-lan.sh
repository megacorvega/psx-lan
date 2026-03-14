#!/bin/bash

# ==============================================================================
# psx-lan - Unified Setup, Status, and Uninstall Utility
# ==============================================================================

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Helper function for interactive prompts used in setup and uninstall
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

# Helper function for printing status
print_status() {
    if [ "$2" = "OK" ]; then
        echo -e "$1 \e[32m[RUNNING/OK]\e[0m"
    elif [ "$2" = "WARN" ]; then
        echo -e "$1 \e[33m[WARNING]\e[0m"
    else
        echo -e "$1 \e[31m[STOPPED/ERROR]\e[0m"
    fi
}

# ==============================================================================
# STATUS FUNCTION
# ==============================================================================
do_status() {
    echo -e "\e[34m"
    cat << "EOF"
 ____  _____  __  __      _      _    _   _ 
|  _ \/ ___ \ \ \/ /     | |    / \  | \ | |
| |_) \___ \   \  /____  | |   / _ \ |  \| |
|  __/ ___) |  /  \____| | |___/ ___ \| |\  |
|_|   |____/  /_/\_\     |_____/_/   \_\_| \_|

EOF
    echo -e "\e[0m"
    echo "================================================="
    echo "             PSX-LAN Status Checker              "
    echo "================================================="
    echo ""

    # 1. Check Docker Service
    if systemctl is-active --quiet docker; then
        print_status "Docker Engine:      " "OK"
    else
        print_status "Docker Engine:      " "ERROR"
    fi

    # 2. Check Samba Container
    if [ "$(sudo docker inspect -f '{{.State.Running}}' psx-samba 2>/dev/null)" = "true" ]; then
        print_status "Samba (SMBv1):      " "OK"
    else
        print_status "Samba (SMBv1):      " "ERROR"
    fi

    # 3. Check DHCP Container
    if [ "$(sudo docker inspect -f '{{.State.Running}}' psx-dhcp 2>/dev/null)" = "true" ]; then
        print_status "DHCP (Dnsmasq):     " "OK"
    else
        print_status "DHCP (Dnsmasq):     " "ERROR"
    fi

    # 4. Check LAN IP (192.168.2.1)
    if ip addr show | grep -q "192.168.2.1/24"; then
        LAN_IF=$(ip -o -4 addr show | grep "192.168.2.1/24" | awk '{print $2}')
        print_status "LAN IP Configured:  " "OK"
        echo "  -> Interface: $LAN_IF (192.168.2.1)"
    else
        print_status "LAN IP Configured:  " "ERROR"
        echo "  -> Could not find 192.168.2.1 assigned to any interface."
    fi

    # 5. Check Wi-Fi Power Management Service
    if systemctl is-active --quiet wifi-power-save-off.service; then
        print_status "Wi-Fi Power Mngt:   " "OK"
        echo "  -> Service is active (Power Saving OFF)"
    else
        print_status "Wi-Fi Power Mngt:   " "WARN"
        echo "  -> Service is inactive or not found (Transfer speeds may be slow)"
    fi

    echo ""
    echo "================================================="
}

# ==============================================================================
# SETUP FUNCTION
# ==============================================================================
do_setup() {
    echo "======================================"
    echo "   psx-lan - Docker Setup script      "
    echo "======================================"
    echo ""

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
    echo "Running status check..."
    do_status
}

# ==============================================================================
# UNINSTALL FUNCTION
# ==============================================================================
do_uninstall() {
    echo "======================================"
    echo "   psx-lan - Uninstall Script         "
    echo "======================================"
    echo ""
    echo "WARNING: This script will stop the PS2 networking services,"
    echo "remove the static IP configuration, and delete the generated"
    echo "configuration files."
    echo "Your game storage folder will NOT be deleted."
    echo ""

    # Are you sure prompt
    read -p "Are you absolutely sure you want to uninstall psx-lan? [y/N]: " confirm_uninstall
    case "$confirm_uninstall" in 
      [yY][eE][sS]|[yY]) 
        echo "Proceeding with uninstall..."
        ;;
      *)
        echo "Uninstall cancelled. Exiting."
        exit 0
        ;;
    esac

    RECOMMENDED_WLAN=$(ls /sys/class/net | grep -E '^wl|^wlan' | head -n 1)

    read -p "Enter your WLAN interface to restore power management [Default: ${RECOMMENDED_WLAN:-wlan0}]: " WLAN_IF
    WLAN_IF=${WLAN_IF:-${RECOMMENDED_WLAN:-wlan0}}

    read -p "Enter the absolute path where your CONFIGURATION files were stored (e.g., /opt/psx-server): " CONFIG_PATH

    # STEP 1: Stop and remove containers
    if prompt_step "[1/5] Stopping and Removing Docker Containers" "This will stop and delete the psx-samba and psx-dhcp containers."; then
      echo "Stopping containers..."
      docker stop psx-samba psx-dhcp > /dev/null 2>&1
      echo "Removing containers..."
      docker rm psx-samba psx-dhcp > /dev/null 2>&1
      echo "Containers removed."
    else
      echo "Skipping container removal."
    fi

    # STEP 2: Undo Static IP
    if prompt_step "[2/5] Removing Static IP (Netplan)" "This will delete the 99-psx-lan.yaml netplan config and re-apply network settings."; then
      if [ -f "/etc/netplan/99-psx-lan.yaml" ]; then
        rm -f /etc/netplan/99-psx-lan.yaml
        netplan apply
        echo "Static IP configuration removed."
      else
        echo "Netplan configuration file not found. Skipping."
      fi
    else
      echo "Skipping Static IP removal."
    fi

    # STEP 3: Undo Wi-Fi Power Management
    if prompt_step "[3/5] Restoring Wi-Fi Power Management" "This disables the systemd service and turns Wi-Fi power saving back ON for $WLAN_IF."; then
      if systemctl is-active --quiet wifi-power-save-off.service || systemctl is-enabled --quiet wifi-power-save-off.service; then
        systemctl stop wifi-power-save-off.service
        systemctl disable wifi-power-save-off.service > /dev/null 2>&1
        rm -f /etc/systemd/system/wifi-power-save-off.service
        systemctl daemon-reload
      fi
      
      # Turn power save back on
      if iw dev "$WLAN_IF" info >/dev/null 2>&1; then
        iw dev "$WLAN_IF" set power_save on
        echo "Wi-Fi power saving turned ON for $WLAN_IF."
      else
        echo "Interface $WLAN_IF not found. Could not restore power management."
      fi
    else
      echo "Skipping Wi-Fi Power Management restore."
    fi

    # STEP 4: Remove Configuration Files
    if prompt_step "[4/5] Removing Configuration Files" "This deletes the samba, dnsmasq, and docker-compose files located in $CONFIG_PATH."; then
      if [ -d "$CONFIG_PATH" ] && [ "$CONFIG_PATH" != "/" ]; then
        rm -rf "$CONFIG_PATH/samba"
        rm -rf "$CONFIG_PATH/dnsmasq"
        rm -f "$CONFIG_PATH/docker-compose.yml"
        echo "Configuration files removed."
        
        # Check if dir is empty and offer to delete it
        if [ -z "$(ls -A "$CONFIG_PATH" 2>/dev/null)" ]; then
            rmdir "$CONFIG_PATH"
            echo "Removed empty configuration directory: $CONFIG_PATH"
        fi
      else
        echo "Invalid path or path not found. Skipping."
      fi
    else
      echo "Skipping Configuration File removal."
    fi

    # STEP 5: Uninstall Docker (Optional)
    if prompt_step "[5/5] Uninstall Docker and Dependencies? (OPTIONAL)" "WARNING: Choose 'Yes' ONLY if you do not use Docker for any other projects on this machine."; then
      echo "Uninstalling Docker and related packages..."
      apt-get remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      apt-get autoremove -y
      
      read -p "Do you also want to delete all Docker images, containers, and volumes system-wide? (Destructive) [y/N]: " purge_docker
      case "$purge_docker" in 
        [yY][eE][sS]|[yY]) 
          rm -rf /var/lib/docker
          rm -rf /var/lib/containerd
          echo "Docker data purged."
          ;;
        *)
          echo "Keeping Docker data in /var/lib/docker."
          ;;
      esac
    else
      echo "Skipping Docker uninstallation."
    fi

    echo ""
    echo "=========================================================="
    echo " Uninstall Complete! "
    echo "=========================================================="
    echo "The psx-lan services have been successfully removed."
    echo "Your game storage directory was left untouched."
    echo "=========================================================="
}

# ==============================================================================
# MAIN MENU / ARGUMENT PARSING
# ==============================================================================

show_menu() {
    echo "======================================"
    echo "   psx-lan - Unified Utility Tool     "
    echo "======================================"
    echo "1) Run Setup / Install"
    echo "2) Check Status"
    echo "3) Run Uninstall"
    echo "4) Exit"
    echo ""
    read -p "Select an option [1-4]: " option
    case $option in
        1) do_setup ;;
        2) do_status ;;
        3) do_uninstall ;;
        4) exit 0 ;;
        *) echo "Invalid option. Please try again." ; echo "" ; show_menu ;;
    esac
}

case "$1" in
    setup|install)
        do_setup
        ;;
    status)
        do_status
        ;;
    uninstall)
        do_uninstall
        ;;
    *)
        show_menu
        ;;
esac