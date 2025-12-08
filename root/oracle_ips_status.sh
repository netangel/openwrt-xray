#!/bin/sh
# Check Oracle Cloud IPs fail-safe blocking status

echo "=== Oracle IPs Fail-Safe Blocking Status ==="
echo ""

# Check UCI firewall config
UCI_ENABLED=$(uci get firewall.oracle_block.enabled 2>/dev/null || echo "not configured")
echo "UCI Firewall Block Rule: $UCI_ENABLED"

# Check if blocking rules are loaded in fw4
if nft list chain inet fw4 forward 2>/dev/null | grep -q "Oracle IPs"; then
    echo "fw4 Forward Chain: BLOCKING ACTIVE"

    # Count blocked packets
    BLOCKED=$(nft list chain inet fw4 forward 2>/dev/null | grep "Oracle IPs" | grep -oP 'packets \K\d+' || echo "0")
    echo "  - Blocked packets: $BLOCKED"
else
    echo "fw4 Forward Chain: NO BLOCKING RULES"
fi

# Check if blocking rules are in output
if nft list chain inet fw4 output 2>/dev/null | grep -q "Oracle IPs"; then
    echo "fw4 Output Chain: BLOCKING ACTIVE"
else
    echo "fw4 Output Chain: NO BLOCKING RULES"
fi

echo ""

# Check xray routing rule
if grep -q "Force Oracle Cloud IPs through proxy" /etc/xray/config/routing.jsonc 2>/dev/null; then
    echo "Xray Routing Rule: CONFIGURED"
    echo "  - Location: /etc/xray/config/routing.jsonc"
    echo "  - Outbound: vless-reality (108 IP ranges)"
else
    echo "Xray Routing Rule: NOT CONFIGURED"
fi

echo ""

# Check xray service status
if pgrep -x xray >/dev/null 2>&1; then
    echo "Xray Service: RUNNING"

    # Check if xray tproxy is active
    if nft list table ip xray 2>/dev/null | grep -q "tproxy"; then
        echo "  - Tproxy: ACTIVE"
        echo "  - Oracle IPs can reach proxy via tproxy (bypassing fw4 block)"
    fi
else
    echo "Xray Service: STOPPED"
fi

echo ""
echo "=== Summary ==="

if [ "$UCI_ENABLED" = "1" ]; then
    if pgrep -x xray >/dev/null 2>&1; then
        echo "✓ PROTECTED MODE ACTIVE"
        echo "  - Oracle IPs blocked by default in fw4"
        echo "  - Xray tproxy intercepts in prerouting (before fw4 block)"
        echo "  - Oracle IPs accessible ONLY via proxy"
        echo ""
        echo "  Traffic flow:"
        echo "  1. Packet to Oracle IP arrives"
        echo "  2. Xray prerouting (mangle) → tproxy + mark 1"
        echo "  3. Packet redirected to xray proxy (never reaches fw4 forward)"
        echo "  4. Xray routes to vless-reality outbound"
    else
        echo "⚠ FAIL-SAFE MODE ACTIVE"
        echo "  - Oracle IPs blocked by default in fw4"
        echo "  - Xray is NOT running"
        echo "  - Oracle IPs are COMPLETELY BLOCKED (no access)"
        echo ""
        echo "  This is the fail-safe state - Oracle IPs cannot be reached until xray starts"
    fi
elif [ "$UCI_ENABLED" = "0" ]; then
    echo "○ BLOCKING DISABLED"
    echo "  - Oracle IPs are NOT blocked"
    echo "  - Traffic follows normal xray routing (routing.jsonc)"
    echo "  - SECURITY WARNING: If xray fails, Oracle IPs may be accessible directly!"
else
    echo "○ NOT CONFIGURED"
    echo "  - Oracle IPs blocking not configured"
fi

echo ""
echo "To disable blocking: /root/oracle_ips_disable.sh"
