# Busted: WiFi Network Traffic Sniffer 🚨

**Busted** is a network traffic monitoring tool that passively captures **visited websites** from all devices on a WiFi network using **ARP spoofing** and **TLS SNI / DNS sniffing**.

---

## Features
**Passive sniffing** – Captures visited websites without breaking connections  
**Filters out the router** – Only logs traffic from connected devices  
**Displays IP → Website** – Easy-to-read output format  
**Silent mode** – No extra clutter from ARP spoofing  
**Automatic network detection** – No need to manually enter device details  
**Restores network when stopped** – Cleans up everything on exit  

---

## Requirements
Before running **Busted**, install the following dependencies:

```sh
sudo apt update
sudo apt install dsniff tshark arp-scan -y
