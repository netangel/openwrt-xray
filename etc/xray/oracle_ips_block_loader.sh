#!/bin/sh
# Oracle Cloud IPs Fail-Safe Blocking Loader
# This script loads the independent oracle nftables table

nft -f /etc/xray/oracle_ips_block.nft
