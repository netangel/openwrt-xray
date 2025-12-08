## Oracle Cloud IPs - Fail-Safe Blocking

This extension implements **fail-safe blocking** for Oracle Cloud infrastructure IPs. Oracle IPs are **blocked by default** and only accessible when xray successfully proxies them.

## Security Model

**Fail-safe principle**: Oracle IPs should be completely inaccessible if xray fails to start or crashes.

### How It Works

The solution uses **layered packet filtering** with different nftables priorities:

```
┌─────────────────────────────────────────────────┐
│  Packet to Oracle IP enters router              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│  PREROUTING HOOK (priority: mangle, -150)       │
│  → Xray table processes packet                  │
│  → If xray running: tproxy + mark 1             │
│  → Packet redirected to 127.0.0.1:61219         │
│  → Never reaches forward chain ✓                │
└─────────────────┬───────────────────────────────┘
                  │
                  │ (only if xray NOT running)
                  ▼
┌─────────────────────────────────────────────────┐
│  FORWARD HOOK (priority: filter, 0)             │
│  → fw4 firewall processes packet                │
│  → Oracle IPs BLOCKED ✗                         │
│  → Packet dropped                               │
└─────────────────────────────────────────────────┘
```

**Result:**
- **Xray running** → Packets tproxied in prerouting, never reach forward chain → Oracle IPs accessible via proxy
- **Xray stopped** → Packets reach forward chain → Oracle IPs blocked → No access (fail-safe)

## Files

```
/etc/config/firewall             # UCI firewall config (includes oracle_ips_block.nft)
/etc/xray/oracle_ips_block.nft   # nftables blocking rules (loaded by fw4)
/etc/xray/config/routing.jsonc   # Xray routing rule (lines 92-126, forces to proxy)
/root/oracle_ips_disable.sh      # Manual disable script (with confirmation)
/root/oracle_ips_status.sh       # Check current status
```

## Installation

The blocking rules are **enabled by default** after you deploy the configuration:

```bash
# On the router, after deploying all files:
chmod +x /root/oracle_ips_*.sh
chmod +x /etc/xray/oracle_ips_block.nft

# Reload firewall to activate blocking
fw4 reload

# Start or restart xray
/etc/init.d/xray restart
```

## Automatic Startup Behavior

### Boot Sequence

1. **OpenWRT boot** → fw4 firewall starts (priority ~20)
2. **fw4 loads** `/etc/xray/oracle_ips_block.nft` via UCI config
3. **Oracle IPs BLOCKED** in forward/output chains
4. **Xray service starts** (priority 99)
5. **Xray loads** `/etc/xray/nft.conf` with tproxy rules
6. **Xray routing** applies rules from `routing.jsonc`
7. **Oracle IPs now accessible** via tproxy → proxy

### To Your Questions

#### Q1: Will Oracle IPs rules apply automatically on startup?

**Yes, automatically.** The blocking rules are loaded by fw4 on every boot (enabled by default in `/etc/config/firewall`). When xray starts, its tproxy rules intercept Oracle traffic before the blocking rules apply.

**Boot timeline:**
- `T+0s`: fw4 starts → Oracle IPs BLOCKED
- `T+30s`: xray starts → Oracle IPs accessible via proxy
- If xray fails: Oracle IPs remain BLOCKED (fail-safe)

#### Q2: Will Oracle IPs be blocked if xray fails to start?

**Yes, completely blocked.** This is the fail-safe design:

- Blocking rules are in **fw4 forward chain** (separate from xray)
- If xray never starts or crashes:
  - Packets are NOT tproxied in prerouting
  - Packets reach fw4 forward chain
  - Oracle IPs are BLOCKED by fw4 rules
  - **No access** to Oracle IPs

**Test this:**
```bash
# Stop xray
/etc/init.d/xray stop

# Try to access Oracle IP
ping 52.84.151.1  # Should FAIL (blocked)

# Check status
/root/oracle_ips_status.sh
# Output: "FAIL-SAFE MODE ACTIVE - Oracle IPs are COMPLETELY BLOCKED"

# Start xray
/etc/init.d/xray start

# Now Oracle IPs accessible via proxy
```

## Usage

### Check Status

```bash
/root/oracle_ips_status.sh
```

Shows:
- UCI firewall configuration
- fw4 blocking rules status
- Xray service status
- Tproxy status
- Current protection mode

### Disable Blocking (Manual)

```bash
/root/oracle_ips_disable.sh
```

This script:
- Asks for confirmation (typing "yes")
- Disables UCI firewall rule
- Reloads fw4 to remove blocking
- **WARNING**: Oracle IPs may be accessible directly if xray fails!

### Re-enable Blocking

```bash
uci set firewall.oracle_block.enabled='1'
uci commit firewall
fw4 reload
```

## Traffic Flow Examples

### Normal Operation (Xray Running)

```
[Client] → [Oracle IP: 52.84.151.1]
         ↓
[Router prerouting] → xray table (mangle priority)
         ↓
[Tproxy to 127.0.0.1:61219] + [mark 1]
         ↓
[Xray process] → routing.jsonc → "Force Oracle IPs" rule
         ↓
[vless-reality outbound] → Proxy server
         ↓
[Oracle IP via proxy] ✓
```

### Fail-Safe Mode (Xray Stopped)

```
[Client] → [Oracle IP: 52.84.151.1]
         ↓
[Router prerouting] → xray table NOT ACTIVE
         ↓
[Packet continues to forward chain]
         ↓
[fw4 forward] → Oracle IPs blocking rule
         ↓
[DROP] ✗ (no access)
```

## Verification

### Verify Blocking Rules Loaded

```bash
# Check fw4 forward chain
nft list chain inet fw4 forward | grep Oracle

# Should show:
# ip daddr { 52.84.151.0/24, ... } counter packets X bytes Y drop comment "Block Oracle IPs unless xray tproxy active"
```

### Verify Xray Tproxy

```bash
# Check xray table
nft list table ip xray

# Should show tproxy rules:
# ip protocol tcp tproxy to 127.0.0.1:61219 meta mark set 1
# ip protocol udp tproxy to 127.0.0.1:61219 meta mark set 1
```

### Verify Routing Rule

```bash
# Check xray routing config
grep -A 30 "Force Oracle Cloud IPs" /etc/xray/config/routing.jsonc
```

### Test Fail-Safe

```bash
# Stop xray
/etc/init.d/xray stop

# Try to connect to Oracle IP (should fail)
curl -m 5 http://52.84.151.1
# Expected: timeout or connection refused

# Check blocked packets counter
nft list chain inet fw4 forward | grep Oracle
# Counter should increment

# Start xray
/etc/init.d/xray start

# Now should work (via proxy)
```

## Updating the IP List

To add/remove Oracle IPs:

1. **Edit the IP list**:
   ```bash
   vi /etc/xray/oracle_vpn_ips_list
   ```

2. **Update nftables blocking rules**:
   ```bash
   vi /etc/xray/oracle_ips_block.nft
   # Update the ORACLE_IPS define section
   ```

3. **Update xray routing rules**:
   ```bash
   vi /etc/xray/config/routing.jsonc
   # Update lines 97-125 (the "ip" array)
   ```

4. **Apply changes**:
   ```bash
   fw4 reload                    # Reload blocking rules
   /etc/init.d/xray restart      # Reload xray routing
   ```

## Troubleshooting

### Oracle IPs are accessible even when xray is stopped

**Diagnosis**: Blocking rules not loaded

```bash
# Check fw4 rules
nft list chain inet fw4 forward | grep Oracle

# If empty, check UCI config
uci show firewall.oracle_block

# Reload firewall
fw4 reload
```

### Oracle IPs are blocked even when xray is running

**Diagnosis**: Tproxy not working, packets reaching forward chain

```bash
# Check if xray table exists
nft list table ip xray

# Check if xray process is running
pgrep -x xray

# Check xray logs
logread -e xray | tail -50

# Restart xray
/etc/init.d/xray restart
```

### High packet drop counter

**Diagnosis**: Normal if you have devices trying to reach Oracle IPs when xray is stopped

```bash
# Check counter
nft list chain inet fw4 forward | grep Oracle

# Example output:
# counter packets 1523 bytes 91380 drop
# This shows 1523 packets were blocked (fail-safe working correctly)
```

### Blocking rules not removed after disable script

```bash
# Manually remove
nft delete rule inet fw4 forward <handle>

# Or reload entire firewall
/etc/init.d/firewall restart
```

## Performance Impact

- **nftables sets**: O(1) lookup, negligible overhead
- **108 IP ranges**: Minimal memory (~2KB)
- **fw4 forward chain**: Only processes packets NOT tproxied by xray
- **Expected overhead**: < 0.1% CPU, < 1ms latency

## Security Considerations

### Threat Model

**Protected against:**
- ✓ Xray service failure (Oracle IPs blocked)
- ✓ Xray crash during runtime (packets no longer tproxied → blocked by fw4)
- ✓ Configuration errors (safe default: blocked)
- ✓ Accidental direct connections (forced through proxy)

**Not protected against:**
- ✗ Firewall bypass (requires root access)
- ✗ Kernel vulnerabilities
- ✗ Proxy server compromise

### Best Practices

1. **Keep blocking enabled** unless you have a specific reason to disable
2. **Monitor packet counters** to detect blocking events
3. **Check xray logs** regularly for routing errors
4. **Test fail-safe** periodically by stopping xray
5. **Update IP list** when Oracle adds new ranges

## Integration with Existing Setup

This extension integrates seamlessly:

- ✓ Works with existing `/etc/xray/nft.conf` (separate tables)
- ✓ Coexists with fw4 zones/rules (standard UCI firewall)
- ✓ Compatible with xray routing rules (routing.jsonc)
- ✓ No changes to xray service files (startup.sh just has comments)
- ✓ LED monitor works normally (monitors xray, not Oracle rules)

## Advanced: Understanding nftables Priority

Tables/chains execute in priority order (lower number = earlier):

```
Hook: prerouting
  -300: raw (connection tracking)
  -150: mangle (packet mangling, xray tproxy) ← Oracle packets tproxied here
     0: nat (DNAT)

Hook: forward
     0: filter (fw4 rules, Oracle blocking) ← Only reached if NOT tproxied
```

**Key insight**: Xray tproxy (mangle priority) runs **before** fw4 forward (filter priority), so tproxied packets never reach the blocking rules.

## References

- Source IP list: `/etc/xray/oracle_vpn_ips_list` (108 ranges)
- nftables priority: https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks
- OpenWRT fw4: https://openwrt.org/docs/guide-user/firewall/firewall_configuration
- Tproxy documentation: https://docs.kernel.org/networking/tproxy.html
