#!/bin/sh

# Function to add nftables rules for a specific IP and port
direct_port_for_ip() {
    ip=$1
    port=$2

    nft insert rule ip xray prerouting ip daddr "$ip" tcp dport "$port" counter return
    nft insert rule ip xray prerouting ip daddr "$ip" udp dport "$port" counter return
    nft insert rule ip xray output ip daddr "$ip" tcp dport "$port" counter return
    nft insert rule ip xray output ip daddr "$ip" udp dport "$port" counter return
}

# Function to add nftables rules for a single port without specifying IP
direct_port() {
    port=$1

    nft insert rule ip xray prerouting tcp dport "$port" counter return
    nft insert rule ip xray prerouting udp dport "$port" counter return
    nft insert rule ip xray output tcp dport "$port" counter return
    nft insert rule ip xray output udp dport "$port" counter return
}

# Function to add nftables rules for a range of ports for a specific IP
direct_port_range_for_ip() {
    ip=$1
    start_port=$2
    end_port=$3

    nft insert rule ip xray prerouting ip daddr "$ip" tcp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray prerouting ip daddr "$ip" udp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray output ip daddr "$ip" tcp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray output ip daddr "$ip" udp dport { "$start_port"-"$end_port" } counter return
}

# Function to add nftables rules for a range of ports without specifying IP
direct_port_range() {
    start_port=$1
    end_port=$2

    nft insert rule ip xray prerouting tcp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray prerouting udp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray output tcp dport { "$start_port"-"$end_port" } counter return
    nft insert rule ip xray output udp dport { "$start_port"-"$end_port" } counter return
}

# Function to add nftables rules for an IP without specifying ports
direct_ip() {
    ip=$1

    nft insert rule ip xray prerouting ip saddr "$ip" counter return
    nft insert rule ip xray output ip saddr "$ip" counter return
    nft insert rule ip xray prerouting ip daddr "$ip" counter return
    nft insert rule ip xray output ip daddr "$ip" counter return
}

# Function to add nftables rules for blocking IP
block_ip() {
    ip=$1

    # Block in prerouting chain
    nft insert rule ip xray prerouting ip daddr "$ip" counter drop
    nft insert rule ip xray prerouting ip saddr "$ip" counter drop
    
    # Block in output chain
    nft insert rule ip xray output ip daddr "$ip" counter drop
    nft insert rule ip xray output ip saddr "$ip" counter drop
}

