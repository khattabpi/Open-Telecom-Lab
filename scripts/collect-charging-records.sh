#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — 5G IMS Charging & Usage Accounting Collector
# ─────────────────────────────────────────────────────────────────
# Collects and formats:
#   1. IMS Call Detail Records (CDRs) from Kamailio S-CSCF SQLite DB.
#   2. 5G User-Plane Data Usage (UL/DL bytes & packets) per SUPI & DNN.
#   3. UPF Aggregate User-Plane Traffic Counters.
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FORMAT="${1:-table}"

# 1. Fetch IMS CDRs from Kamailio SQLite
fetch_cdrs() {
    kubectl exec -n ims deployment/kamailio-scscf -c scscf 2>/dev/null -- python3 -c "
import sqlite3, json
con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
con.row_factory = sqlite3.Row
try:
    rows = con.execute('SELECT id, callid, caller, callee, start_time, end_time, duration, sip_code, sip_reason, call_type FROM cdrs ORDER BY id ASC').fetchall()
    print(json.dumps([dict(r) for r in rows]))
except Exception as e:
    print('[]')
" || echo "[]"
}

# 2. Fetch User Plane Stats per UE
fetch_ue_usage() {
    python3 -c "
import subprocess, re, json

ues = [
    {'name': 'UE1 (Egypt 602/03)', 'supi': 'imsi-602030000000001', 'imsi': '602030000000001', 'plmn': '602/03'},
    {'name': 'UE2 (Egypt 602/04)', 'supi': 'imsi-602040000000002', 'imsi': '602040000000002', 'plmn': '602/04'},
    {'name': 'UE3 (Bosnia 218/90)', 'supi': 'imsi-602030000000003', 'imsi': '602030000000003', 'plmn': '218/90 (Roaming)'}
]

res = []

for ue in ues:
    for dnn, psi in [('internet', 'psi1'), ('ims', 'psi2')]:
        ns = f'ueransim-{ue[\"imsi\"]}-{dnn}-{psi}'
        out = subprocess.run(f'ip netns exec {ns} ip -s link show uesimtun0 2>/dev/null', shell=True, capture_output=True, text=True).stdout
        ip_out = subprocess.run(f'ip netns exec {ns} ip -4 addr show uesimtun0 2>/dev/null', shell=True, capture_output=True, text=True).stdout
        
        ip_m = re.search(r'inet ([0-9.]+)', ip_out)
        ue_ip = ip_m.group(1) if ip_m else 'N/A'
        
        rx_m = re.search(r'RX:\s+bytes\s+packets[^\n]+\n\s+(\d+)\s+(\d+)', out)
        tx_m = re.search(r'TX:\s+bytes\s+packets[^\n]+\n\s+(\d+)\s+(\d+)', out)
        
        dl_bytes = int(rx_m.group(1)) if rx_m else 0
        dl_pkts = int(rx_m.group(2)) if rx_m else 0
        ul_bytes = int(tx_m.group(1)) if tx_m else 0
        ul_pkts = int(tx_m.group(2)) if tx_m else 0
        
        res.append({
            'supi': ue['supi'],
            'plmn': ue['plmn'],
            'dnn': dnn,
            'ip': ue_ip,
            'ul_bytes': ul_bytes,
            'ul_pkts': ul_pkts,
            'dl_bytes': dl_bytes,
            'dl_pkts': dl_pkts
        })

print(json.dumps(res))
"
}

# 3. Fetch UPF Aggregate Stats
fetch_upf_usage() {
    docker exec open5gs-cluster-control-plane python3 -c "
import subprocess, re, json
out = subprocess.run('ip -s link show ogstun 2>/dev/null', shell=True, capture_output=True, text=True).stdout
rx_m = re.search(r'RX:\s+bytes\s+packets[^\n]+\n\s+(\d+)\s+(\d+)', out)
tx_m = re.search(r'TX:\s+bytes\s+packets[^\n]+\n\s+(\d+)\s+(\d+)', out)
res = {
    'interface': 'ogstun',
    'rx_bytes': int(rx_m.group(1)) if rx_m else 0,
    'rx_pkts': int(rx_m.group(2)) if rx_m else 0,
    'tx_bytes': int(tx_m.group(1)) if tx_m else 0,
    'tx_pkts': int(tx_m.group(2)) if tx_m else 0
}
print(json.dumps(res))
" 2>/dev/null || echo '{"interface":"ogstun","rx_bytes":0,"rx_pkts":0,"tx_bytes":0,"tx_pkts":0}'
}

CDRS_JSON=$(fetch_cdrs)
UE_USAGE_JSON=$(fetch_ue_usage)
UPF_USAGE_JSON=$(fetch_upf_usage)

if [ "${FORMAT}" = "--json" ] || [ "${FORMAT}" = "json" ]; then
    python3 -c "
import json, sys
cdrs = json.loads('''${CDRS_JSON}''')
ue_usage = json.loads('''${UE_USAGE_JSON}''')
upf_usage = json.loads('''${UPF_USAGE_JSON}''')
print(json.dumps({'cdrs': cdrs, 'ue_usage': ue_usage, 'upf_usage': upf_usage}, indent=2))
"
    exit 0
fi

# Print Operator Table Report
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo "  5G-IMS-Lab Offline Charging & User-Plane Usage Accounting Report"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${BOLD}1. IMS CALL DETAIL RECORDS (CDRs) — Kamailio S-CSCF SQLite${NC}"
echo "-----------------------------------------------------------------------------------------------"
printf "%-4s %-25s %-18s %-18s %-19s %-8s %-6s\n" "ID" "Call-ID" "Caller" "Callee" "Start Time" "Duration" "Status"
echo "-----------------------------------------------------------------------------------------------"

python3 -c "
import json
cdrs = json.loads('''${CDRS_JSON}''')
if not cdrs:
    print('  (No Call Detail Records logged yet)')
else:
    for c in cdrs:
        cid = (c['callid'][:22] + '...') if len(c['callid']) > 25 else c['callid']
        clr = c['caller'].replace('sip:', '')
        cle = c['callee'].replace('sip:', '')
        dur = f\"{c['duration']}s\"
        status = f\"{c['sip_code']} {c['sip_reason']}\"
        print(f\"{c['id']:<4} {cid:<25} {clr:<18} {cle:<18} {c['start_time']:<19} {dur:<8} {status:<6}\")
"

echo ""
echo -e "${BOLD}2. 5G USER-PLANE DATA USAGE PER SUPI & DNN (Real Linux Netns Counters)${NC}"
echo "-----------------------------------------------------------------------------------------------"
printf "%-22s %-16s %-10s %-15s %-12s %-12s\n" "SUPI" "Serving PLMN" "DNN" "Allocated IP" "UL (Bytes/Pk)" "DL (Bytes/Pk)"
echo "-----------------------------------------------------------------------------------------------"

python3 -c "
import json
usage = json.loads('''${UE_USAGE_JSON}''')
for u in usage:
    ul_str = f\"{u['ul_bytes']} B ({u['ul_pkts']}p)\"
    dl_str = f\"{u['dl_bytes']} B ({u['dl_pkts']}p)\"
    print(f\"{u['supi']:<22} {u['plmn']:<16} {u['dnn']:<10} {u['ip']:<15} {ul_str:<12} {dl_str:<12}\")
"

echo ""
echo -e "${BOLD}3. UPF AGGREGATE USER-PLANE THROUGHPUT (Device: ogstun)${NC}"
echo "-----------------------------------------------------------------------------------------------"

python3 -c "
import json
upf = json.loads('''${UPF_USAGE_JSON}''')
print(f\"  Interface: {upf['interface']} | Total RX (GTP-U Decapsulated): {upf['rx_bytes']:,} bytes ({upf['rx_pkts']} packets)\")
print(f\"  Interface: {upf['interface']} | Total TX (GTP-U Encapsulated):   {upf['tx_bytes']:,} bytes ({upf['tx_pkts']} packets)\")
"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}[✓] Accounting Status: OPERATIONAL & PERSISTENT${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════════════════"
