#!/bin/sh
opkg update

# Core proxy binary
opkg install xray-core

# nftables kernel modules (required for /etc/xray/nft.conf)
opkg install kmod-nft-core          # nftables core functionality
opkg install kmod-nft-tproxy        # nftables tproxy support

# Kernel networking modules (required for transparent proxy)
opkg install kmod-nf-conntrack      # Connection tracking
opkg install kmod-nf-tproxy         # Kernel tproxy support
opkg install kmod-nf-socket         # Socket matching

# Log rotation (for /etc/logrotate.d/xray)
opkg install logrotate

chmod +x /etc/xray/fwd_functions.sh
chmod +x /etc/xray/startup.sh
chmod +x /etc/init.d/xray
chmod +x /root/restart_xray.sh
chmod +x /root/fwd_manual.sh

# Oracle IPs management scripts
chmod +x /root/oracle_ips_disable.sh
chmod +x /root/oracle_ips_status.sh
chmod +x /etc/xray/oracle_ips_block.nft