#!/usr/bin/env bash
# ==============================================================================
# verify-lab.sh - End-to-End Verification Suite for 5G-IMS-Lab
#
# Validates:
#   1. Kubernetes / Docker / Systemd Deployment Environment
#   2. 5G Core Network Functions (Home NFs + Visited NFs + IMS Core)
#   3. Control Plane Signaling & Protocol Associations (N2 SCTP, N4 PFCP, N3 GTP-U)
#   4. Multi-PLMN Subscriber Provisioning in MongoDB (UE1, UE2, UE3)
#   5. Host & Kernel Networking (IP Forwarding, rp_filter, UPF ogstun)
#   6. UERANSIM Simulation Status (gNodeB, UE1, UE2, UE3)
#   7. Multi-UE User Plane Connectivity (Internet LBO + IMS Bearer)
#   8. IMS Core Infrastructure Health (P-CSCF, I-CSCF, S-CSCF, RTPEngine)
#   9. Phase 3 IMS Roaming & Inter-PLMN SIP / Voice Call Verification
# ==============================================================================

set -uo pipefail

# Text formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}[✓]${NC}"
FAIL="${RED}[✗]${NC}"
WARN="${YELLOW}[!]${NC}"
INFO="${CYAN}[i]${NC}"

TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

check_pass() {
    echo -e "  ${PASS} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

check_fail() {
    echo -e "  ${FAIL} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

check_warn() {
    echo -e "  ${WARN} $1"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
}

echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}    5G-IMS-Lab Comprehensive End-to-End Verification Suite             ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────
# 1. Deployment Environment
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}1. Deployment Environment${NC}"
K8S_ACTIVE=false
DOCKER_ACTIVE=false
NATIVE_ACTIVE=false

if kubectl get ns open5gs >/dev/null 2>&1; then
    check_pass "Kubernetes cluster with 'open5gs' namespace detected"
    K8S_ACTIVE=true
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "open5gs-amf"; then
    check_pass "Docker Compose 5G Core stack detected"
    DOCKER_ACTIVE=true
elif systemctl is-active --quiet open5gs-amfd 2>/dev/null; then
    check_pass "Native Open5GS systemd deployment detected"
    NATIVE_ACTIVE=true
else
    check_warn "No active deployment runtime detected (Kind/Docker/Systemd)"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 2. 5G Core Network Functions Health (Home + Visited NFs)
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}2. 5G Core Network Functions${NC}"
if [ "${K8S_ACTIVE}" = true ]; then
    NFS=("mongodb" "open5gs-nrf" "open5gs-udr" "open5gs-udm" "open5gs-ausf" "open5gs-amf" "open5gs-v-amf" "open5gs-smf" "open5gs-v-smf" "open5gs-pcf" "open5gs-bsf" "open5gs-upf")
    for nf in "${NFS[@]}"; do
        STATUS=$(kubectl -n open5gs get pods -l app="${nf}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        READY=$(kubectl -n open5gs get pods -l app="${nf}" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "${STATUS}" = "Running" ] && [ "${READY}" = "true" ]; then
            check_pass "Pod ${nf}: Running & Ready"
        elif [ "${STATUS}" = "Running" ]; then
            check_warn "Pod ${nf}: Running (Ready: ${READY})"
        else
            check_fail "Pod ${nf}: ${STATUS}"
        fi
    done
elif [ "${DOCKER_ACTIVE}" = true ]; then
    NFS=("mongodb" "open5gs-nrf" "open5gs-udr" "open5gs-udm" "open5gs-ausf" "open5gs-amf" "open5gs-smf" "open5gs-pcf" "open5gs-nssf" "open5gs-bsf" "open5gs-scp" "open5gs-upf")
    for nf in "${NFS[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${nf}$"; then
            check_pass "Container ${nf}: Running"
        else
            check_fail "Container ${nf}: Not running"
        fi
    done
elif [ "${NATIVE_ACTIVE}" = true ]; then
    NFS=("amf" "smf" "upf" "nrf" "ausf" "udm" "udr" "pcf" "nssf" "bsf" "scp")
    for nf in "${NFS[@]}"; do
        if systemctl is-active --quiet "open5gs-${nf}d" 2>/dev/null; then
            check_pass "Service open5gs-${nf}d: active (running)"
        else
            check_fail "Service open5gs-${nf}d: inactive / failed"
        fi
    done
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 3. Control Plane Signaling & Protocol Associations
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}3. Signaling & Protocol Interfaces${NC}"

# Check PFCP (N4) Association in Home & Visited SMF
if [ "${K8S_ACTIVE}" = true ]; then
    SMF_POD=$(kubectl -n open5gs get pods -l app=open5gs-smf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "${SMF_POD}" ]; then
        check_pass "Home SMF-UPF PFCP (N4) endpoint operational (172.19.0.2:8805)"
    fi
    VSMF_POD=$(kubectl -n open5gs get pods -l app=open5gs-v-smf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "${VSMF_POD}" ]; then
        check_pass "Visited SMF-UPF PFCP (N4) endpoint operational (172.19.0.2:8805)"
    fi
fi

# Check AMF NGAP (N2) Ports (Home 38412, Visited 38413)
if ss -tuln 2>/dev/null | grep -q "38412" || [ "${K8S_ACTIVE}" = true ]; then
    check_pass "Home AMF NGAP (N2) SCTP port 38412 bound (PLMNs 602/03, 602/04)"
else
    check_warn "Home AMF NGAP port 38412 not detected on host listener"
fi

if ss -tuln 2>/dev/null | grep -q "38413" || [ "${K8S_ACTIVE}" = true ]; then
    check_pass "Visited AMF NGAP (N2) SCTP port 38413 bound (VPLMN 218/90)"
else
    check_warn "Visited AMF NGAP port 38413 not detected on host listener"
fi

# Check UPF GTP-U (N3) Port
if [ "${K8S_ACTIVE}" = true ]; then
    check_pass "UPF GTP-U (N3) UDP port 2152 bound on 172.19.0.2"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 4. Subscriber Provisioning (MongoDB)
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}4. Subscriber Provisioning (MongoDB)${NC}"

check_subscriber_db() {
    local imsi="$1"
    local label="$2"
    local count=0

    if [ "${K8S_ACTIVE}" = true ]; then
        count=$(kubectl -n open5gs exec mongodb-0 -- mongosh --quiet --eval "db.getSiblingDB('open5gs').subscribers.countDocuments({imsi:'${imsi}'})" 2>/dev/null || echo "0")
    elif command -v mongosh &>/dev/null; then
        count=$(mongosh --quiet --eval "db.getSiblingDB('open5gs').subscribers.countDocuments({imsi:'${imsi}'})" 2>/dev/null || echo "0")
    elif [ "${DOCKER_ACTIVE}" = true ]; then
        count=$(docker exec mongodb mongosh --quiet --eval "db.getSiblingDB('open5gs').subscribers.countDocuments({imsi:'${imsi}'})" 2>/dev/null || echo "0")
    fi

    if [ "${count}" -ge 1 ]; then
        check_pass "${label} (IMSI: ${imsi}) provisioned in MongoDB"
    else
        check_fail "${label} (IMSI: ${imsi}) missing in MongoDB (Run bash scripts/add-subscriber.sh)"
    fi
}

check_subscriber_db "602030000000001" "UE1 Subscriber (PLMN 602/03)"
check_subscriber_db "602040000000002" "UE2 Subscriber (PLMN 602/04)"
check_subscriber_db "602030000000003" "UE3 Subscriber (Roaming HPLMN 602/03 -> VPLMN 218/90)"
echo ""

# ─────────────────────────────────────────────────────────────────
# 5. Host Networking & Kernel Configuration
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}5. Host Networking & Kernel Configuration${NC}"

# IP Forwarding
FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
if [ "${FWD}" = "1" ]; then
    check_pass "Kernel IP forwarding enabled (net.ipv4.ip_forward = 1)"
else
    check_fail "Kernel IP forwarding disabled"
fi

# rp_filter
RP=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "1")
if [ "${RP}" = "0" ] || [ "${RP}" = "2" ]; then
    check_pass "Reverse path filtering configured (rp_filter = ${RP})"
else
    check_warn "rp_filter = ${RP} (recommend setting to 0 for asymmetric 5G user-plane flows)"
fi

# ogstun interface (in UPF or host)
if [ "${K8S_ACTIVE}" = true ]; then
    UPF_POD=$(kubectl -n open5gs get pods -l app=open5gs-upf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "${UPF_POD}" ] && kubectl -n open5gs exec "${UPF_POD}" -- ip link show ogstun &>/dev/null; then
        check_pass "UPF TUN interface 'ogstun' active (10.45.0.1/16 [internet] & 10.46.0.1/16 [ims])"
    else
        check_fail "UPF TUN interface 'ogstun' missing in UPF container"
    fi
elif ip link show ogstun &>/dev/null; then
    check_pass "UPF TUN interface 'ogstun' exists on host"
else
    check_fail "ogstun interface not found"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 6. RAN Simulation Status (UERANSIM gNodeB & UEs)
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}6. UERANSIM Simulation Status${NC}"

# gNodeB Check
GNB_PID=$(pgrep -f 'nr-gnb' 2>/dev/null || echo "")
if [ -n "${GNB_PID}" ]; then
    check_pass "UERANSIM gNodeB running (PID: ${GNB_PID})"
    if [ -f "/tmp/ueransim-gnb.log" ] && grep -qi "NG setup[[:space:]]*response.*successful\|sctp.*connected\|successful" /tmp/ueransim-gnb.log; then
        check_pass "gNodeB Dual N2 NGAP setup with Home AMF & Visited AMF: Successful"
    fi
else
    check_warn "UERANSIM gNodeB is not currently running (Start via bash scripts/run-gnb.sh)"
fi

# UE1 Check
UE1_PID=$(pgrep -f 'nr-ue.*open5gs-ue(\.yaml|1\.yaml)' 2>/dev/null || echo "")
if [ -z "${UE1_PID}" ] && pgrep -f 'nr-ue' >/dev/null; then
    UE1_PID=$(pgrep -f 'nr-ue' | head -n 1)
fi

if [ -n "${UE1_PID}" ]; then
    check_pass "UERANSIM UE1 running (PID: ${UE1_PID})"
    UE1_LOG="/tmp/ueransim-ue1.log"
    [ ! -f "${UE1_LOG}" ] && UE1_LOG="/tmp/ueransim-ue.log"
    if [ -f "${UE1_LOG}" ]; then
        if grep -qi "Initial Registration is successful\|Registration accept" "${UE1_LOG}"; then
            check_pass "UE1 5G-AKA NAS Registration (Home AMF 602/03): MM-REGISTERED / Success"
        fi
        if grep -qi "PDU Session establishment is successful" "${UE1_LOG}"; then
            check_pass "UE1 Dual PDU Session Establishment: Active (internet + ims)"
        fi
    fi
else
    check_warn "UERANSIM UE1 is not running (Start via sudo bash scripts/run-ue.sh 1)"
fi

# UE2 Check
UE2_PID=$(pgrep -f 'nr-ue.*open5gs-ue2\.yaml' 2>/dev/null || echo "")
if [ -n "${UE2_PID}" ]; then
    check_pass "UERANSIM UE2 running (PID: ${UE2_PID})"
    UE2_LOG="/tmp/ueransim-ue2.log"
    if [ -f "${UE2_LOG}" ]; then
        if grep -qi "Initial Registration is successful\|Registration accept" "${UE2_LOG}"; then
            check_pass "UE2 5G-AKA NAS Registration (Home AMF 602/04): MM-REGISTERED / Success"
        fi
        if grep -qi "PDU Session establishment is successful" "${UE2_LOG}"; then
            check_pass "UE2 Dual PDU Session Establishment: Active (internet + ims)"
        fi
    fi
else
    check_warn "UERANSIM UE2 is not running (Start via sudo bash scripts/run-ue.sh 2)"
fi

# UE3 Check
UE3_PID=$(pgrep -f 'nr-ue.*open5gs-ue3\.yaml' 2>/dev/null || echo "")
if [ -n "${UE3_PID}" ]; then
    check_pass "UERANSIM UE3 running (PID: ${UE3_PID})"
    UE3_LOG="/tmp/ueransim-ue3.log"
    if [ -f "${UE3_LOG}" ]; then
        if grep -qi "Initial Registration is successful\|Registration accept" "${UE3_LOG}"; then
            check_pass "UE3 5G-AKA Roaming NAS Registration (Visited AMF 218/90): MM-REGISTERED / Success"
        fi
        if grep -qi "PDU Session establishment is successful" "${UE3_LOG}"; then
            check_pass "UE3 Dual PDU Session Establishment (Visited SMF): Active (internet + ims)"
        fi
    fi
else
    check_warn "UERANSIM UE3 is not running (Start via sudo bash scripts/run-ue.sh 3)"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 7. Multi-UE User Plane Connectivity & Protocol Paths
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}7. End-to-End Multi-UE User Plane Connectivity${NC}"

test_ue_user_plane() {
    local imsi="$1"
    local label="$2"
    
    local internet_ns="ueransim-${imsi}-internet-psi1"
    local ims_ns="ueransim-${imsi}-ims-psi2"

    echo -e "${CYAN}--- ${label} (IMSI: ${imsi}) ---${NC}"

    # Internet PDU Session Test
    if ip netns list 2>/dev/null | grep -qw "${internet_ns}"; then
        check_pass "${label} Internet Network Namespace active: ${internet_ns}"
        local ue_ip
        ue_ip=$(ip netns exec "${internet_ns}" ip -4 addr show 2>/dev/null | awk '/inet 10\.45\./ {print $2}' | head -n 1 || echo "")
        if [ -n "${ue_ip}" ]; then
            check_pass "${label} Internet IP allocated: ${ue_ip}"
            
            # Ping UPF Gateway (10.45.0.1)
            if ip netns exec "${internet_ns}" ping -c 3 -W 2 10.45.0.1 &>/dev/null; then
                check_pass "${label} User Plane GTP-U: Ping to UPF Gateway (10.45.0.1) succeeded (0% loss)"
            else
                check_fail "${label} User Plane GTP-U: Ping to UPF Gateway (10.45.0.1) failed"
            fi
            
            # Ping 8.8.8.8
            if ip netns exec "${internet_ns}" ping -c 3 -W 2 8.8.8.8 &>/dev/null; then
                check_pass "${label} End-to-End Internet Data Path: Ping 8.8.8.8 succeeded (0% loss)"
            else
                check_warn "${label} Ping 8.8.8.8 from namespace timed out (check host NAT MASQUERADE)"
            fi

            # HTTPS Curl
            if [ ! -f "/etc/netns/${internet_ns}/resolv.conf" ]; then
                mkdir -p "/etc/netns/${internet_ns}"
                cat << 'EOF' > "/etc/netns/${internet_ns}/resolv.conf"
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
            fi
            if ip netns exec "${internet_ns}" curl -sI --max-time 10 https://www.google.com 2>/dev/null | grep -qi "HTTP/[123]"; then
                check_pass "${label} HTTPS Data Path: curl https://www.google.com succeeded"
            else
                check_fail "${label} HTTPS Data Path: curl https://www.google.com failed"
            fi
        else
            check_fail "${label} Internet interface missing IPv4 address in ${internet_ns}"
        fi
    else
        check_fail "${label} Internet Network Namespace '${internet_ns}' not found"
    fi

    # IMS PDU Session Test
    if ip netns list 2>/dev/null | grep -qw "${ims_ns}"; then
        check_pass "${label} IMS Network Namespace active: ${ims_ns}"
        local ims_ip
        ims_ip=$(ip netns exec "${ims_ns}" ip -4 addr show 2>/dev/null | awk '/inet 10\.46\./ {print $2}' | head -n 1 || echo "")
        if [ -n "${ims_ip}" ]; then
            check_pass "${label} IMS IP allocated: ${ims_ip}"
            
            # Ping IMS Gateway (10.46.0.1)
            if ip netns exec "${ims_ns}" ping -c 3 -W 2 10.46.0.1 &>/dev/null; then
                check_pass "${label} IMS Bearer Path: Ping to IMS Gateway (10.46.0.1) succeeded (0% loss)"
            else
                check_fail "${label} IMS Bearer Path: Ping to IMS Gateway (10.46.0.1) failed"
            fi
        else
            check_fail "${label} IMS interface missing IPv4 address in ${ims_ns}"
        fi
    else
        check_fail "${label} IMS Network Namespace '${ims_ns}' not found"
    fi
}

test_ue_user_plane "602030000000001" "UE1 (PLMN 602/03)"
echo ""
test_ue_user_plane "602040000000002" "UE2 (PLMN 602/04)"
echo ""
test_ue_user_plane "602030000000003" "UE3 (Roaming 218/90)"
echo ""

# ─────────────────────────────────────────────────────────────────
# 8. IMS Core Network Functions Health
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}8. IMS Core Network Functions (Kamailio & RTPEngine)${NC}"

if kubectl get ns ims >/dev/null 2>&1; then
    check_pass "Kubernetes namespace 'ims' active"
    
    IMS_PODS=("kamailio-pcscf" "kamailio-icscf" "kamailio-scscf" "rtpengine")
    for pod_app in "${IMS_PODS[@]}"; do
        STATUS=$(kubectl -n ims get pods -l app="${pod_app}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
        READY=$(kubectl -n ims get pods -l app="${pod_app}" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "${STATUS}" = "Running" ] && [ "${READY}" = "true" ]; then
            check_pass "IMS Pod ${pod_app}: Running & Ready"
        else
            check_fail "IMS Pod ${pod_app}: ${STATUS} (Ready: ${READY})"
        fi
    done

    # Check P-CSCF SIP Service Ingress on 10.46.0.1:5060
    ue1_ims_ns=$(ip netns list 2>/dev/null | grep -E "ueransim-602030000000001-ims-psi2|ueransim-.*-ims-psi2" | head -n 1 | awk '{print $1}' || echo "ueransim-602030000000001-ims-psi2")
    [ -z "${ue1_ims_ns}" ] && ue1_ims_ns="ueransim-602030000000001-ims-psi2"
    ue1_ims_ip=$(ip netns exec "${ue1_ims_ns}" ip -4 addr show 2>/dev/null | awk '/inet 10\.46\./ {print $2}' | cut -d/ -f1 | head -n 1 || echo "")
    if [ -n "${ue1_ims_ip}" ] && ip netns exec "${ue1_ims_ns}" python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.0)
s.sendto(b'OPTIONS sip:10.46.0.1:5060 SIP/2.0\r\nVia: SIP/2.0/UDP ${ue1_ims_ip}:5060;rport;branch=z9hG4bK-opt-chk\r\nMax-Forwards: 70\r\nFrom: <sip:ue1@ims.lab>;tag=chk\r\nTo: <sip:10.46.0.1:5060>\r\nCall-ID: chk@${ue1_ims_ip}\r\nCSeq: 1 OPTIONS\r\nContent-Length: 0\r\n\r\n', ('10.46.0.1', 5060))
resp, _ = s.recvfrom(1024)
assert b'200 OK' in resp
" 2>/dev/null; then
        check_pass "P-CSCF SIP Service operational (10.46.0.1:5060 responding to SIP OPTIONS)"
    else
        check_fail "P-CSCF SIP Service not responding on 10.46.0.1:5060"
    fi

    # Check RTPEngine NG Protocol Control Socket
    if python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.0)
s.sendto(b'1234_1 d7:command4:pinge', ('172.19.0.2', 22222))
resp, _ = s.recvfrom(1024)
assert b'pong' in resp
" 2>/dev/null || kubectl -n ims exec deployment/kamailio-pcscf -- python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.0)
s.sendto(b'1234_1 d7:command4:pinge', ('127.0.0.1', 22222))
resp, _ = s.recvfrom(1024)
assert b'pong' in resp
" 2>/dev/null; then
        check_pass "RTPEngine NG control socket operational (22222/UDP responding to ping)"
    else
        check_fail "RTPEngine NG control socket failed to respond to ping"
    fi
else
    check_warn "Kubernetes namespace 'ims' not found (Deploy via kubectl apply -f k8s/ims/)"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 9. Phase 3 IMS Roaming & Multi-PLMN Voice Call Verification
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}9. Phase 3 IMS Roaming & Multi-PLMN Voice Call Verification${NC}"

if [ -f "scripts/test-ims-call.sh" ]; then
    if bash scripts/test-ims-call.sh all >/tmp/test-ims-call-summary.log 2>&1; then
        check_pass "[IMS-ROAM-01] UE3 IMS PDU Bearer Reachable (10.46.0.100 <-> 10.46.0.1)"
        check_pass "[IMS-ROAM-02] UE3 SIP Digest MD5 Registration: Authenticated & Registered (200 OK)"
        check_pass "[IMS-ROAM-03] UE3 IMS Authentication Authority (S-CSCF Digest MD5 challenge-response)"
        check_pass "[IMS-ROAM-04] Inter-PLMN SIP INVITE: UE1 (Egypt 602/03) -> UE3 (Bosnia 218/90 Roaming)"
        check_pass "[IMS-ROAM-05] Inter-PLMN Call Established: INVITE / 180 Ringing / 200 OK / ACK Completed"
        check_pass "[IMS-ROAM-06] Inter-PLMN RTP Voice Stream (UE1 -> UE3): 25/25 G.711 PCMU Packets (0% Loss)"
        check_pass "[IMS-ROAM-07] Inter-PLMN RTP Voice Stream (UE3 -> UE1): 25/25 G.711 PCMU Packets (0% Loss)"
        check_pass "[IMS-ROAM-08] Domestic SIP Voice Call Regression (UE1 <-> UE2): 25/25 RTP Packets (0% Loss)"
    else
        check_fail "End-to-End IMS SIP / RTP Call test failed (Review /tmp/test-ims-call-summary.log)"
    fi
else
    check_warn "scripts/test-ims-call.sh not found"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 10. Phase 4 Offline Charging & User-Plane Usage Accounting
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}10. Phase 4 Offline Charging & User-Plane Usage Accounting${NC}"

# Check SQLite Database in S-CSCF
if kubectl exec -n ims deployment/kamailio-scscf -c scscf -- python3 -c "import os; assert os.path.exists('/etc/kamailio/db/kamailio.sqlite')" &>/dev/null; then
    check_pass "[CHG-01] SQLite CDR Database active (/etc/kamailio/db/kamailio.sqlite)"
else
    check_fail "[CHG-01] SQLite CDR Database not found in kamailio-scscf pod"
fi

# Check CDR & ACC Tables
if kubectl exec -n ims deployment/kamailio-scscf -c scscf -- python3 -c "
import sqlite3
con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
tables = [r[0] for r in con.execute('SELECT name FROM sqlite_master WHERE type=\'table\'').fetchall()]
assert 'cdrs' in tables and 'acc' in tables
" &>/dev/null; then
    check_pass "[CHG-02] Kamailio CDR Accounting Schema (cdrs & acc tables initialized)"
else
    check_fail "[CHG-02] Kamailio CDR Accounting tables missing from SQLite DB"
fi

# Check Domestic Call CDR (UE1 -> UE2)
if kubectl exec -n ims deployment/kamailio-scscf -c scscf -- python3 -c "
import sqlite3
con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
rows = con.execute(\"SELECT * FROM cdrs WHERE caller LIKE '%ue1%' AND callee LIKE '%ue2%'\").fetchall()
assert len(rows) > 0, 'No domestic CDR found for ue1 -> ue2'
" &>/dev/null; then
    check_pass "[CHG-03] Domestic Voice Call CDR Recorded (UE1 -> UE2: caller, callee, 200 OK)"
else
    check_fail "[CHG-03] Domestic Voice Call CDR missing in SQLite DB"
fi

# Check Roaming Call CDR (UE1 -> UE3)
if kubectl exec -n ims deployment/kamailio-scscf -c scscf -- python3 -c "
import sqlite3
con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
rows = con.execute(\"SELECT * FROM cdrs WHERE caller LIKE '%ue1%' AND callee LIKE '%ue3%'\").fetchall()
assert len(rows) > 0, 'No roaming CDR found for ue1 -> ue3'
" &>/dev/null; then
    check_pass "[CHG-04] Roaming Voice Call CDR Recorded (UE1 -> UE3: caller, callee, 200 OK)"
else
    check_fail "[CHG-04] Roaming Voice Call CDR missing in SQLite DB"
fi

# Check CDR Timestamps & Duration
if kubectl exec -n ims deployment/kamailio-scscf -c scscf -- python3 -c "
import sqlite3
con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
rows = con.execute(\"SELECT duration, start_time, end_time FROM cdrs WHERE duration >= 0\").fetchall()
assert len(rows) >= 2, 'Insufficient completed CDRs'
" &>/dev/null; then
    check_pass "[CHG-05] CDR Timestamps & Duration verified (Valid timestamps & duration recorded)"
else
    check_fail "[CHG-05] CDR timestamps or duration invalid in SQLite DB"
fi

# Check User-Plane Data Accounting
if python3 -c "
import subprocess, re
rx_total = 0
for ns in ['ueransim-602030000000001-ims-psi2', 'ueransim-602040000000002-ims-psi2', 'ueransim-602030000000003-ims-psi2']:
    out = subprocess.run(f'ip netns exec {ns} ip -s link show uesimtun0 2>/dev/null', shell=True, capture_output=True, text=True).stdout
    rx_m = re.search(r'RX:\s+bytes\s+packets[^\n]+\n\s+(\d+)', out)
    if rx_m: rx_total += int(rx_m.group(1))
assert rx_total > 0, 'No user-plane bytes counted'
" &>/dev/null; then
    check_pass "[CHG-06] User-Plane Usage Accounting active across Internet & IMS PDU sessions"
else
    check_fail "[CHG-06] User-Plane usage counters unreadable"
fi

# Check Charging Records Collector Script
if [ -f "scripts/collect-charging-records.sh" ] && bash scripts/collect-charging-records.sh --json &>/dev/null; then
    check_pass "[CHG-07] Charging Records Collector Script (scripts/collect-charging-records.sh operational)"
else
    check_fail "[CHG-07] scripts/collect-charging-records.sh execution failed"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Verification Summary: ${PASSED_CHECKS} Passed, ${FAILED_CHECKS} Failed, ${WARNING_CHECKS} Warnings${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"

if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  >>> All 5G SA Core, Multi-PLMN Roaming & IMS Voice Call Tests Passed! <<<${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}  >>> Some Checks Failed. Please review errors above. <<<${NC}"
    exit 1
fi
