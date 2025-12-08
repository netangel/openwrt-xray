#!/bin/sh
# Check Oracle Cloud IPs fail-safe blocking status

echo "=== Oracle IPs Fail-Safe Blocking Status ==="
echo ""

# Check UCI firewall config
UCI_ENABLED=$(uci get firewall.oracle_block.enabled 2>/dev/null || echo "not configured")
echo "UCI Firewall Block Rule: $UCI_ENABLED"

# Check if blocking rules are loaded in xray_oracle table
if nft list table inet xray_oracle 2>/dev/null >/dev/null; then
    # Check forward chain
    if nft list chain inet xray_oracle oracle_forward 2>/dev/null | grep -q "drop"; then
        echo "Oracle Forward Chain: BLOCKING ACTIVE"
    else
        echo "Oracle Forward Chain: NO BLOCKING RULES"
    fi

    # Check output chain
    if nft list chain inet xray_oracle oracle_output 2>/dev/null | grep -q "drop"; then
        echo "Oracle Output Chain: BLOCKING ACTIVE"
    else
        echo "Oracle Output Chain: NO BLOCKING RULES"
    fi
else
    echo "Oracle nftables Table: NOT LOADED"
    echo "  - Forward Chain: NO BLOCKING RULES"
    echo "  - Output Chain: NO BLOCKING RULES"
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
if [ -f "/usr/bin/xray" ] && pgrep -x /usr/bin/xray >/dev/null 2>&1; then
    echo "Xray Service: RUNNING"
    echo "  - Binary: /usr/bin/xray"

    # Check if xray tproxy is active
    if nft list table ip xray 2>/dev/null | grep -q "tproxy"; then
        echo "  - Tproxy: ACTIVE"
        echo "  - Oracle IPs can reach proxy via tproxy (bypassing oracle block)"
    fi
elif [ -f "/usr/bin/xray" ]; then
    echo "Xray Service: STOPPED"
    echo "  - Binary: /usr/bin/xray (exists but not running)"
else
    echo "Xray Service: NOT INSTALLED"
    echo "  - Binary: /usr/bin/xray (missing)"
fi

echo ""
echo "=== Summary ==="

# Check if nftables table exists
NFTABLES_LOADED=0
if nft list table inet xray_oracle 2>/dev/null >/dev/null; then
    NFTABLES_LOADED=1
fi

if [ "$UCI_ENABLED" = "1" ] && [ "$NFTABLES_LOADED" = "1" ]; then
    if [ -f "/usr/bin/xray" ] && pgrep -x xray >/dev/null 2>&1; then
        echo "✓ PROTECTED MODE ACTIVE"
        echo "  - Oracle IPs blocked by default in xray_oracle table"
        echo "  - Xray tproxy intercepts in prerouting (before forward)"
        echo "  - Oracle IPs accessible ONLY via proxy"
        echo ""
        echo "  Traffic flow:"
        echo "  1. Packet to Oracle IP arrives"
        echo "  2. Xray prerouting (mangle) → tproxy + mark 1"
        echo "  3. Packet redirected to xray proxy (never reaches oracle_forward)"
        echo "  4. Xray routes to vless-reality outbound"
    else
        echo "⚠ FAIL-SAFE MODE ACTIVE"
        echo "  - Oracle IPs blocked by default in xray_oracle table"
        echo "  - Xray is NOT running"
        echo "  - Oracle IPs are COMPLETELY BLOCKED (no access)"
        echo ""
        echo "  This is the fail-safe state - Oracle IPs cannot be reached until xray starts"
    fi
elif [ "$UCI_ENABLED" = "0" ] || [ "$NFTABLES_LOADED" = "0" ]; then
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
echo "To manually reload blocking: nft -f /etc/xray/oracle_ips_block.nft"
