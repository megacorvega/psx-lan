#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

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

# Interactive Prompts for paths and interfaces
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