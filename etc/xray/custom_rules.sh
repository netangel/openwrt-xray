#!/bin/sh

# Source the function definitions
. /etc/xray/fwd_functions.sh

# Add your custom rules here
# See the fwd_functions.sh for the available functions
# Example: Exclude traefik HTTP+HTTPS
# direct_port_range_for_ip "192.168.1.165" 80 443
