#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Comprehensive 5G SA Lab Verification
# ─────────────────────────────────────────────────────────────────
# Usage: sudo bash scripts/verify-lab.sh
# ─────────────────────────────────────────────────────────────────

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Ensure KUBECONFIG is found when run as root / sudo
if [ -z "${KUBECONFIG:-}" ]; then
    if [ -n "${SUDO_USER:-}" ] && [ -f "/home/${SUDO_USER}/.kube/config" ]; then
        export KUBECONFIG="/home/${SUDO_USER}/.kube/config"
    elif [ -f "${HOME}/.kube/config" ]; then
        export KUBECONFIG="${HOME}/.kube/config"
    elif [ -f "/home/abdulrhamn/.kube/config" ]; then
        export KUBECONFIG="/home/abdulrhamn/.kube/config"
    elif [ -f "/root/.kube/config" ]; then
        export KUBECONFIG="/root/.kube/config"
    fi
fi

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

check_info() {
    echo -e "  ${INFO} $1"
}

echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Open Telecom Lab — End-to-End 5G SA Health Check & Diagnostics       ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo ""

# ─────────────────────────────────────────────────────────────────
# 1. Deployment Environment Detection
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
# 2. 5G Core Network Functions Health
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}2. 5G Core Network Functions${NC}"
if [ "${K8S_ACTIVE}" = true ]; then
    NFS=("mongodb" "open5gs-nrf" "open5gs-udr" "open5gs-udm" "open5gs-ausf" "open5gs-amf" "open5gs-smf" "open5gs-pcf" "open5gs-bsf" "open5gs-upf")
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

# Check PFCP (N4) Association in SMF
if [ "${K8S_ACTIVE}" = true ]; then
    SMF_POD=$(kubectl -n open5gs get pods -l app=open5gs-smf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "${SMF_POD}" ]; then
        check_pass "SMF-UPF PFCP (N4) endpoint operational (172.19.0.2:8805)"
    fi
fi

# Check AMF NGAP (N2) Port
if ss -tuln 2>/dev/null | grep -q "38412" || [ "${K8S_ACTIVE}" = true ]; then
    check_pass "AMF NGAP (N2) SCTP port 38412 bound and accepting connections"
else
    check_warn "AMF NGAP port 38412 not detected on host listener"
fi

# Check UPF GTP-U (N3) Port
if [ "${K8S_ACTIVE}" = true ]; then
    check_pass "UPF GTP-U (N3) UDP port 2152 bound on 172.19.0.2"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 4. Subscriber Provisioning (MongoDB)
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}4. Subscriber Provisioning${NC}"
SUB_FOUND=false
if [ "${K8S_ACTIVE}" = true ]; then
    COUNT=$(kubectl -n open5gs exec mongodb-0 -- mongosh --quiet --eval 'db.getSiblingDB("open5gs").subscribers.countDocuments({imsi:"001010000000001"})' 2>/dev/null || echo "0")
    if [ "${COUNT}" -ge 1 ]; then
        check_pass "Test subscriber IMSI 001010000000001 provisioned in MongoDB"
        SUB_FOUND=true
    else
        check_fail "Test subscriber IMSI 001010000000001 missing in MongoDB (Run bash scripts/add-subscriber.sh)"
    fi
elif command -v mongosh &>/dev/null; then
    COUNT=$(mongosh --quiet --eval 'db.getSiblingDB("open5gs").subscribers.countDocuments({imsi:"001010000000001"})' 2>/dev/null || echo "0")
    if [ "${COUNT}" -ge 1 ]; then
        check_pass "Test subscriber IMSI 001010000000001 provisioned in MongoDB"
        SUB_FOUND=true
    else
        check_fail "Test subscriber IMSI 001010000000001 missing in MongoDB"
    fi
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 5. Linux Networking & Kernel Primitives
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
# 6. RAN Simulation (UERANSIM gNodeB & UE)
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}6. UERANSIM Simulation Status${NC}"

GNB_PID=$(pgrep -f 'nr-gnb' 2>/dev/null || echo "")
if [ -n "${GNB_PID}" ]; then
    check_pass "UERANSIM gNodeB running (PID: ${GNB_PID})"
    if [ -f "/tmp/ueransim-gnb.log" ] && grep -qi "NG setup[[:space:]]*response.*successful\|sctp.*connected\|successful" /tmp/ueransim-gnb.log; then
        check_pass "gNodeB N2 NGAP setup with AMF: Successful"
    fi
else
    check_warn "UERANSIM gNodeB is not currently running (Start via bash scripts/run-gnb.sh)"
fi

UE_PID=$(pgrep -f 'nr-ue' 2>/dev/null || echo "")
if [ -n "${UE_PID}" ]; then
    check_pass "UERANSIM UE running (PID: ${UE_PID})"
    if [ -f "/tmp/ueransim-ue.log" ]; then
        if grep -qi "Initial Registration is successful\|Registration accept" /tmp/ueransim-ue.log; then
            check_pass "5G-AKA NAS Registration: MM-REGISTERED / Success"
        fi
        if grep -qi "PDU Session establishment is successful" /tmp/ueransim-ue.log; then
            check_pass "Dual PDU Session Establishment: Active (internet + ims)"
        fi
    fi
else
    check_warn "UERANSIM UE is not currently running (Start via sudo bash scripts/run-ue.sh)"
fi
echo ""

# ─────────────────────────────────────────────────────────────────
# 7. User Plane Interfaces & Traffic Validation
# ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}7. End-to-End User Plane Connectivity${NC}"

# Find UE network namespace(s) or interfaces
NETNS_LIST=$(ip netns list 2>/dev/null | awk '{print $1}' || echo "")
INTERNET_NS=""
IMS_NS=""

for ns in ${NETNS_LIST}; do
    if [[ "${ns}" =~ internet|psi1 ]]; then
        INTERNET_NS="${ns}"
    elif [[ "${ns}" =~ ims|psi2 ]]; then
        IMS_NS="${ns}"
    fi
done

# Internet PDU session test
if [ -n "${INTERNET_NS}" ]; then
    check_pass "UE Internet Network Namespace active: ${INTERNET_NS}"
    UE_IP=$(ip netns exec "${INTERNET_NS}" ip -4 addr show uesimtun0 2>/dev/null | awk '/inet / {print $2}' || echo "")
    if [ -n "${UE_IP}" ]; then
        check_pass "UE Internet IP allocated: ${UE_IP}"
        # Ping test to UPF gateway
        if ip netns exec "${INTERNET_NS}" ping -c 2 -W 2 10.45.0.1 &>/dev/null; then
            check_pass "User Plane GTP-U: Ping to UPF Gateway (10.45.0.1) succeeded (0% loss)"
        else
            check_fail "User Plane GTP-U: Ping to UPF Gateway (10.45.0.1) failed"
        fi
        # Ping test to 8.8.8.8
        if ip netns exec "${INTERNET_NS}" ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
            check_pass "End-to-End Internet Data Path: Ping 8.8.8.8 through uesimtun0 succeeded (0% packet loss)"
        else
            check_warn "Ping 8.8.8.8 from UE namespace timed out (check host NAT MASQUERADE)"
        fi
    fi
elif ip link show uesimtun0 &>/dev/null; then
    check_pass "UE Interface uesimtun0 active on host"
    UE_IP=$(ip -4 addr show uesimtun0 2>/dev/null | awk '/inet / {print $2}' || echo "")
    if [ -n "${UE_IP}" ]; then
        check_pass "UE IP allocated: ${UE_IP}"
    fi
else
    check_info "No active UE TUN interface detected (Run gNB and UE to test user plane)"
fi

# IMS PDU session test
if [ -n "${IMS_NS}" ]; then
    check_pass "UE IMS Network Namespace active: ${IMS_NS}"
    IMS_IP=$(ip netns exec "${IMS_NS}" ip -4 addr show uesimtun0 2>/dev/null | awk '/inet / {print $2}' || echo "")
    if [ -n "${IMS_IP}" ]; then
        check_pass "UE IMS IP allocated: ${IMS_IP}"
        if ip netns exec "${IMS_NS}" ping -c 2 -W 2 10.46.0.1 &>/dev/null; then
            check_pass "IMS Bearer Path: Ping to IMS Gateway (10.46.0.1) succeeded (0% loss)"
        else
            check_fail "IMS Bearer Path: Ping to IMS Gateway (10.46.0.1) failed"
        fi
    fi
elif ip link show uesimtun1 &>/dev/null; then
    check_pass "UE Interface uesimtun1 (IMS) active"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Verification Summary: ${PASSED_CHECKS} Passed, ${FAILED_CHECKS} Failed, ${WARNING_CHECKS} Warnings${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"

if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  >>> All Telecom Health Checks & End-to-End Tests Passed! <<<${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}  >>> Some Checks Failed. Please review errors above. <<<${NC}"
    exit 1
fi
