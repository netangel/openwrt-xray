#!/bin/sh

nft delete table ip xray
ip route del local default dev lo table 100
ip rule del table 100
rm -f /tmp/xray_startup_executed