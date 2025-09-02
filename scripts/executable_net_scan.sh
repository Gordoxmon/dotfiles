#!/bin/bash

# Network range (change to your local network)
NETWORK="192.168.1.0/24"
INTERVAL=10  # seconds

while true; do
    clear
    echo "Scanning network $NETWORK..."
    nmap -sn $NETWORK | grep -E "Nmap scan report for|MAC Address"
    echo ""
    echo "Next scan in $INTERVAL seconds..."
    sleep $INTERVAL
done

