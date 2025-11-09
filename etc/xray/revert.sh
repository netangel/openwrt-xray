#!/bin/sh

# Check if startup has been executed
if [ ! -f /tmp/xray_startup_executed ]; then
    echo "Xray startup was not executed, nothing to revert"
    exit 0
fi

nft delete table ip xray
ip route del local default dev lo table 100
ip rule del table 100
rm -f /tmp/xray_startup_executed