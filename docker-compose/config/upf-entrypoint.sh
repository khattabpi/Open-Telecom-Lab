#!/bin/bash
set -e

# Enable IP Forwarding
sysctl -w net.ipv4.ip_forward=1

# Ensure ogstun device exists and is brought UP
ip tuntap add dev ogstun mode tun || true
ip addr add 10.45.0.1/16 dev ogstun || true
ip addr add 10.46.0.1/16 dev ogstun || true
ip link set dev ogstun up || true

# NAT Rules
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -t nat -A POSTROUTING -s 10.46.0.0/16 ! -o ogstun -j MASQUERADE

exec open5gs-upfd -c /usr/local/etc/open5gs/upf.yaml