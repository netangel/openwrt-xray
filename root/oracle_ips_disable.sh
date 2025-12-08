#!/bin/sh
# Manually disable Oracle Cloud IPs fail-safe blocking
# WARNING: This allows Oracle IPs to be accessed directly (not through proxy)

set -e

echo "=== Disabling Oracle IPs Fail-Safe Blocking ==="
echo ""
echo "WARNING: Oracle IPs will become accessible without proxy protection!"
echo ""
read -p "Are you sure you want to disable? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Disabling Oracle IPs blocking..."

# Disable in UCI config
uci set firewall.oracle_block.enabled='0'
uci commit firewall

# Remove nftables blocking rules
echo "Removing nftables blocking rules..."
if nft list table inet xray_oracle 2>/dev/null >/dev/null; then
    nft delete table inet xray_oracle
    echo "  - Removed inet xray_oracle table"
else
    echo "  - Table inet xray_oracle not found (already removed)"
fi

# Reload firewall to ensure UCI changes are applied
echo "Reloading firewall..."
fw4 reload 2>/dev/null || /etc/init.d/firewall reload

echo ""
echo "=== Oracle IPs Fail-Safe Blocking DISABLED ==="
echo ""

# Verify removal
if nft list table inet xray_oracle 2>/dev/null >/dev/null; then
    echo "Status: FAILED TO DISABLE"
    echo "  - ERROR: xray_oracle table still exists!"
    echo "  - Try manually: nft delete table inet xray_oracle"
    exit 1
else
    echo "Status: INACTIVE"
    echo "  - Oracle IPs are NO LONGER blocked by default"
    echo "  - Traffic will follow xray routing rules in routing.jsonc"
    echo "  - If xray fails, Oracle IPs may be accessible directly (SECURITY RISK!)"
fi

echo ""
echo "To re-enable protection:"
echo "  uci set firewall.oracle_block.enabled='1'"
echo "  uci commit firewall"
echo "  fw4 reload"
echo "  # or manually: nft -f /etc/xray/oracle_ips_block.nft"
