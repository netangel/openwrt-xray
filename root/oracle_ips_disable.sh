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

# Reload firewall to remove blocking rules
echo "Reloading firewall..."
fw4 reload 2>/dev/null || /etc/init.d/firewall reload

echo ""
echo "=== Oracle IPs Fail-Safe Blocking DISABLED ==="
echo ""
echo "Status: INACTIVE"
echo "  - Oracle IPs are NO LONGER blocked by default"
echo "  - Traffic will follow xray routing rules in routing.jsonc"
echo "  - If xray fails, Oracle IPs may be accessible directly (SECURITY RISK!)"
echo ""
echo "To re-enable protection:"
echo "  uci set firewall.oracle_block.enabled='1'"
echo "  uci commit firewall"
echo "  fw4 reload"
