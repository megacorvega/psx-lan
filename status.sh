#!/bin/bash

# ASCII Art Logo
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
# Using 'ip addr' to check if the static IP is actively assigned
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