#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Verify 5G SA Lab Status
# ─────────────────────────────────────────────────────────────────
# Usage: sudo bash verify-lab.sh
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS="${GREEN}[✓]${NC}"
FAIL="${RED}[✗]${NC}"
WARN="${YELLOW}[!]${NC}"

echo "═══════════════════════════════════════════════════"
echo "  Open Telecom Lab — Health Check"
echo "═══════════════════════════════════════════════════"
echo ""

# ─── Check Open5GS NFs ─────────────────────────────────────────
echo "── 5G Core Network Functions ──"
NFS=("amf" "smf" "upf" "nrf" "ausf" "udm" "udr" "pcf" "nssf" "bsf" "scp")
for nf in "${NFS[@]}"; do
    if systemctl is-active --quiet "open5gs-${nf}d" 2>/dev/null; then
        echo -e "  ${PASS} open5gs-${nf}d"
    else
        echo -e "  ${FAIL} open5gs-${nf}d"
    fi
done

echo ""

# ─── Check MongoDB ──────────────────────────────────────────────
echo "── Database ──"
if systemctl is-active --quiet mongod 2>/dev/null; then
    echo -e "  ${PASS} MongoDB (mongod)"
    SUB_COUNT=$(mongosh --quiet --eval 'db.getSiblingDB("open5gs").subscribers.countDocuments()' 2>/dev/null || echo "?")
    echo -e "  ${PASS} Subscribers: ${SUB_COUNT}"
else
    echo -e "  ${FAIL} MongoDB (mongod)"
fi

echo ""

# ─── Check Network Interfaces ──────────────────────────────────
echo "── Network Interfaces ──"
if ip link show ogstun &>/dev/null; then
    echo -e "  ${PASS} ogstun interface exists"
else
    echo -e "  ${FAIL} ogstun interface missing"
fi

if ip link show uesimtun0 &>/dev/null; then
    echo -e "  ${PASS} uesimtun0 interface exists"
else
    echo -e "  ${WARN} uesimtun0 not found (UE may not be connected)"
fi

echo ""

# ─── Check IP Forwarding ───────────────────────────────────────
echo "── System Configuration ──"
FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
if [ "${FWD}" = "1" ]; then
    echo -e "  ${PASS} IP forwarding enabled"
else
    echo -e "  ${FAIL} IP forwarding disabled"
fi

if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "10.45.0.0"; then
    echo -e "  ${PASS} NAT rule for 10.45.0.0/16 exists"
else
    echo -e "  ${FAIL} NAT rule missing for 10.45.0.0/16"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Health check complete."
echo "═══════════════════════════════════════════════════"
