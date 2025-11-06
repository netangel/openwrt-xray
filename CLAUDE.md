# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**openwrt-xray** is an OpenWRT router configuration package that transforms a router into a transparent proxy using Xray. It provides:
- Transparent TCP/UDP traffic interception via nftables
- Smart routing based on domain/IP geolocation (Russian IPs/domains direct, others proxied)
- Integrated DNS interception with custom resolution
- Selective traffic bypass and blocking rules
- Modern nftables firewall rules (not legacy iptables)

**Type:** Configuration and deployment package (Bash scripts, JSONC config files)
**License:** MIT
**Requirements:** OpenWRT 22.03+, router in 192.168.0.0/16 subnet

## Architecture Overview

The system works as follows:

```
[Router LAN Traffic]
        ↓
[nftables rules intercept TCP/UDP via tproxy on port 61219]
        ↓
[Xray inbound (dokodemo-door) receives traffic with sniffed domains]
        ↓
[Xray routing engine applies rules:]
  - DNS traffic → Google DoH
  - QUIC/ads → blocked
  - Russian domains/IPs → direct connection
  - Everything else → VLESS/Reality proxy
        ↓
[Outbounds: direct, proxied, or blocked]
```

### Directory Structure

```
root/                          # Installation and utility scripts
├── install_xray.sh           # Installs Xray and all dependencies (must be run first)
├── restart_xray.sh           # Quick restart shortcut
└── fwd_manual.sh             # Example manual rule application

etc/
├── config/xray              # UCI service configuration
├── init.d/xray              # OpenWRT procd service manager
├── logrotate.d/xray         # Log rotation (hourly, 24-hour retention)
└── xray/                    # Xray runtime directory
    ├── config/              # Configuration files (modular JSONC)
    │   ├── inbounds.jsonc   # Single tproxy listener (port 61219)
    │   ├── outbounds.jsonc  # vless-reality, direct, block, dns-out outbounds
    │   ├── routing.jsonc    # 8+ routing rules (DNS, QUIC, geosite, geoip)
    │   ├── dns.jsonc        # DNS config (Google DoH + .lan override)
    │   ├── log.jsonc        # Logging configuration
    │   └── policy.jsonc     # Connection policies
    ├── nft.conf             # nftables firewall rules
    ├── startup.sh           # Called on service start (loads nftables)
    ├── fwd_functions.sh     # Function library for adding forwarding rules
    ├── custom_rules.sh      # User-editable custom rules (empty by default)
    ├── revert.sh            # Cleanup/revert script
    └── *.dat                # geoip.dat, geosite.dat, LoyalsoldierSite.dat

usr/share/xray/             # Xray data files (geoip/geosite databases)
```

## Common Development Tasks

### Installation and Setup
```bash
# Full installation (run first on target router)
chmod +x /root/install_xray.sh && /root/install_xray.sh

# Enable and start service
/etc/init.d/xray enable && /etc/init.d/xray start
```

### Service Management
```bash
# Start, stop, restart, status
/etc/init.d/xray start
/etc/init.d/xray stop
/etc/init.d/xray restart          # Faster than stop+start
/etc/init.d/xray status

# Quick restart (shortcut)
/root/restart_xray.sh

# Revert changes (cleanup firewall rules)
/etc/xray/revert.sh
```

### Configuration Changes
```bash
# Edit Xray outbound details (proxy credentials/server)
vi /etc/xray/config/outbounds.jsonc

# Add custom forwarding rules (use fwd_functions.sh for helpers)
vi /etc/xray/custom_rules.sh

# Then restart to apply changes
/etc/init.d/xray restart
```

### Debugging and Verification
```bash
# Check service status and logs
/etc/init.d/xray status
logread -f -e xray              # Follow Xray logs

# Verify nftables rules are loaded
nft list table ip xray

# Check routing configuration
ip route show
ip rule list

# View nftables packet counters
nft list table ip xray | grep counter

# Test DNS resolution
nslookup example.com 127.0.0.1  # Should use Xray DNS
```

### Recommended Crontab Entries
```bash
0 20 * * 0 /sbin/reboot                                    # Weekly reboot
59 19 * * * /bin/bash /root/restart_xray.sh              # Daily restart
0 * * * * /usr/sbin/logrotate -s /usr/share/logrotate/status /etc/logrotate.conf  # Hourly
```

## Key Files and Their Roles

| File | Purpose | Editable | Notes |
|------|---------|----------|-------|
| `/root/install_xray.sh` | Installation orchestrator | Yes | Install xray package and all dependencies |
| `/etc/init.d/xray` | OpenWRT service control | No | Managed by system; uses procd |
| `/etc/config/xray` | UCI service config | Yes | Minimal config (mostly defaults) |
| `/etc/xray/startup.sh` | Runtime setup | No | Auto-called on service start |
| `/etc/xray/nft.conf` | nftables rules | No | Auto-generated; defines firewall chains |
| `/etc/xray/fwd_functions.sh` | Rule function library | No | Helper functions for custom_rules.sh |
| `/etc/xray/custom_rules.sh` | User rules | Yes | Only place for custom forwarding rules |
| `/etc/xray/revert.sh` | Cleanup script | No | Reverts nftables and routing changes |
| `/etc/xray/config/inbounds.jsonc` | Inbound config | No | Single tproxy listener; usually unchanged |
| `/etc/xray/config/outbounds.jsonc` | Outbound config | Yes | **Must edit:** add proxy server credentials |
| `/etc/xray/config/routing.jsonc` | Routing rules | Yes | Customizable traffic routing logic |
| `/etc/xray/config/dns.jsonc` | DNS config | Yes | Configure DNS resolution behavior |
| `/etc/logrotate.d/xray` | Log rotation | No | Hourly rotation, 24-hour retention |

## Configuration Details

### outbounds.jsonc (MUST EDIT)
The vless-reality outbound defines the proxy connection:
```jsonc
// Example structure (fill in your values):
{
  "tag": "vless-reality",
  "protocol": "vless",
  "settings": {
    "vnodes": [{
      "address": "proxy.example.com",    // Your proxy server
      "port": 443,
      "users": [{
        "id": "uuid-here",               // Your UUID
        "encryption": "none"
      }]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",               // Reality TLS (avoid detection)
    "realitySettings": {
      "show": false,
      "fingerprint": "chrome",
      "serverName": "www.example.com",   // SNI server
      "publicKey": "your-public-key",    // Reality key
      "shortId": "your-short-id"         // Reality short ID
    },
    "sockOpt": {
      "mark": 255                        // Required for proper routing
    }
  }
}
```

### routing.jsonc
Main routing rules apply in order:
1. DNS traffic (port 53, all domains) → dns-out
2. QUIC protocol (port 443 UDP) → blocked
3. Russian domains (geosite:ru) → direct
4. Russian IPs (geoip:ru) → direct
5. Ad domains (geosite:category-ads) → blocked
6. BitTorrent → direct
7. Fallback → vless-reality (proxied)

Modify rules here to change traffic behavior.

### custom_rules.sh
User-defined rules using function library from `fwd_functions.sh`. Examples:
```bash
#!/bin/bash
# Custom forwarding rules - these are sourced and executed on startup

# Exclude a specific IP from proxy
# exclude_ip "192.168.0.100"

# Block all P2P traffic
# block_p2p

# Force specific domain to direct
# force_direct_domain "example.com"

# See fwd_functions.sh for available functions
```

## Important Implementation Notes

### Traffic Interception Flow
1. nftables marks packets entering `xray` table
2. Packets matching rules are redirected to tproxy on 127.0.0.1:61219
3. Xray inbound (dokodemo-door) receives marked packets
4. HTTPS/QUIC sniffing extracts domain names
5. Routing rules match against sniffed domains and GeoIP
6. Outbound selection determines: direct, proxied, or blocked

### Configuration Merging
All `/etc/xray/config/*.jsonc` files are merged at runtime:
- Each file is a valid JSONC fragment
- Comments are preserved
- Files are processed in alphabetical order
- The result is a complete Xray config JSON

### Service Boot Order
- Service priority is 99 (near end of boot sequence)
- Depends on: network (interface up)
- Calls `/etc/xray/startup.sh` which:
  1. Loads nftables rules
  2. Creates routing tables and rules
  3. Starts Xray binary

### Log Rotation
- Logs are rotated hourly
- 24 hours of logs retained
- `/usr/share/logrotate/status` tracks state
- Set up via `/etc/logrotate.d/xray`

## Troubleshooting Guide

**Service won't start:**
- Check: `logread -e xray` for errors
- Verify nftables module loaded: `modprobe nf_tables`
- Check Xray binary exists: `which xray`

**Traffic not being intercepted:**
- Verify nftables rules: `nft list table ip xray`
- Check tproxy support: `modprobe nf_conntrack_ipv4`
- Test with: `nslookup example.com 127.0.0.1`

**Xray not starting:**
- Check config syntax: `xray test -c /etc/xray/config/inbounds.jsonc` (etc)
- Review logs: `logread -f -e xray`
- Verify all `.jsonc` files are valid JSON

**Custom rules not applying:**
- Ensure `custom_rules.sh` is executable
- Check syntax against `fwd_functions.sh`
- Verify called after service starts
- Test manually: `bash /etc/xray/custom_rules.sh`

**Performance issues:**
- Check log rotation is working: `/usr/sbin/logrotate -f /etc/logrotate.d/xray`
- Monitor memory: `free -h`
- Check nftables counter growth: `nft list table ip xray`

## Development Workflow

When modifying this project:

1. **Configuration changes:** Edit JSONC files in `/etc/xray/config/`, then `restart`
2. **Routing changes:** Edit `routing.jsonc`, test with `logread -f -e xray`
3. **Custom rules:** Add to `custom_rules.sh`, test with `bash /etc/xray/custom_rules.sh`
4. **Firewall changes:** Never edit `nft.conf` directly; modify startup.sh or custom rules
5. **Testing:** Always `restart` service and verify with debug commands above
6. **Reverting:** Use `/etc/xray/revert.sh` if things break

## Dependencies

Installed by `install_xray.sh`:
- `xray-core` (main proxy binary)
- 10+ iptables kernel modules (kmod-ipt-*, kmod-nf-*)
- nftables kernel modules
- nft command-line tool
- logrotate package

## References

- Xray documentation: https://xtls.github.io/
- OpenWRT service management: https://openwrt.org/docs/guide/services/start_stop_restart_services
- nftables syntax: https://wiki.nftables.org/
- DNS sniffing in Xray: https://xtls.github.io/config/inbound/dokodemo-door.html
