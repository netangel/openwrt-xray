#!/bin/sh

. /etc/xray/fwd_functions.sh

# Get WAN device name first
WAN_DEVICE=$(uci get network.wan.device)

if [ -z "$WAN_DEVICE" ]; then
    echo "Error: Could not determine WAN device"
    exit 1
fi

# Get WAN interface IP address using the device name, excluding localhost and private IPs
# Comment this out, if it doesn't work for you

# Try to get WAN IP with retries
MAX_RETRIES=30
RETRY_INTERVAL=2
for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i to get WAN IP..."
    WAN_IP=$(ip addr show $WAN_DEVICE | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | grep -v '^127\.' | grep -v '^192\.168\.')
    if [ ! -z "$WAN_IP" ]; then
        echo "Successfully got WAN IP: $WAN_IP"
        break
    fi
    if [ $i -lt $MAX_RETRIES ]; then
        echo "No WAN IP found, retrying in $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
    fi
done

# WAN_IP="1.1.1.1"

if [ -z "$WAN_IP" ]; then
    echo "Error: Could not determine WAN IP address for device $WAN_DEVICE"
    exit 1
fi

if [ -f /tmp/xray_startup_executed ]; then
  sh /etc/xray/revert.sh
fi

# Create routing table and rules
ip route add local default dev lo table 100
ip rule add fwmark 1 table 100

# Load nftables rules from nft.conf
nft -f /etc/xray/nft.conf

# Execute custom rules if they exist
if [ -f /etc/xray/custom_rules.sh ]; then
    sh /etc/xray/custom_rules.sh
fi

# Add rules to bypass the firewall for the WAN IP
direct_ip "$WAN_IP"

# required for check above
touch /tmp/xray_startup_executed