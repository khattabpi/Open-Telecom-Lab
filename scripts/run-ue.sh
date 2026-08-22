#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Launch UERANSIM UE(s)
# ─────────────────────────────────────────────────────────────────
# Usage:
#   sudo bash scripts/run-ue.sh          # Launch both UE1 & UE2
#   sudo bash scripts/run-ue.sh all      # Launch both UE1 & UE2
#   sudo bash scripts/run-ue.sh 1        # Launch UE1 (IMSI 602030000000001)
#   sudo bash scripts/run-ue.sh 2        # Launch UE2 (IMSI 602040000000002)
#   sudo bash scripts/run-ue.sh stop     # Stop all running UEs
#   sudo bash scripts/run-ue.sh stop 1   # Stop UE1 only
#   sudo bash scripts/run-ue.sh stop 2   # Stop UE2 only
#   sudo bash scripts/run-ue.sh <config> # Launch custom UE config
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

UE1_CONFIG="${REPO_ROOT}/configs/ueransim/open5gs-ue.yaml"
UE2_CONFIG="${REPO_ROOT}/configs/ueransim/open5gs-ue2.yaml"
UE3_CONFIG="${REPO_ROOT}/configs/ueransim/open5gs-ue3.yaml"
UE_BIN="${REPO_ROOT}/UERANSIM/build/nr-ue"

if [ "${EUID}" -ne 0 ]; then
    echo "[-] Error: nr-ue requires root privileges for TUN/netns creation. Run with sudo." >&2
    exit 1
fi

if [ ! -x "${UE_BIN}" ]; then
    if [ -x "/home/abdulrhamn/core/UERANSIM/build/nr-ue" ]; then
        UE_BIN="/home/abdulrhamn/core/UERANSIM/build/nr-ue"
    else
        echo "[-] Error: nr-ue binary not found at ${UE_BIN}" >&2
        exit 1
    fi
fi

ensure_bridge_ips() {
    local bridge_dev
    bridge_dev=$(ip -4 addr show 2>/dev/null | grep -B 2 "172.19.0.1" | awk '/^[0-9]+:/ {print $2}' | tr -d ':' | head -n 1 || echo "")
    if [ -n "${bridge_dev}" ]; then
        if ! ip -4 addr show dev "${bridge_dev}" | grep -q "172.19.0.3"; then
            ip addr add 172.19.0.3/16 dev "${bridge_dev}" 2>/dev/null || true
        fi
    fi
}

ensure_gnb_running() {
    ensure_bridge_ips
    if ! pgrep -f 'nr-gnb.*(open5gs-gnb-home|gnb-home)\.yaml' >/dev/null 2>&1 || \
       ! pgrep -f 'nr-gnb.*(open5gs-gnb-visited|gnb-visited)\.yaml' >/dev/null 2>&1; then
        echo "[+] Starting gNodeB-Home and gNodeB-Visited..."
        bash "${SCRIPT_DIR}/run-gnb.sh" all
    fi
}

cleanup_namespaces_for_imsi() {
    local imsi="$1"
    for ns in $(ip netns list 2>/dev/null | awk -v imsi="${imsi}" '$1 ~ imsi {print $1}'); do
        ip netns delete "${ns}" 2>/dev/null || true
    done
}

stop_ue() {
    local id="$1"
    case "${id}" in
        1|ue1)
            echo "[+] Stopping UE1 (IMSI 602030000000001)..."
            pkill -9 -f 'nr-ue.*open5gs-ue(\.yaml|1\.yaml)' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "602030000000001"
            cleanup_namespaces_for_imsi "001010000000001"
            ;;
        2|ue2)
            echo "[+] Stopping UE2 (IMSI 602040000000002)..."
            pkill -9 -f 'nr-ue.*open5gs-ue2\.yaml' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "602040000000002"
            cleanup_namespaces_for_imsi "001010000000002"
            ;;
        3|ue3)
            echo "[+] Stopping UE3 (IMSI 602030000000003 - Roaming VPLMN 218/90)..."
            pkill -9 -f 'nr-ue.*open5gs-ue3\.yaml' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "602030000000003"
            ;;
        all|"")
            echo "[+] Stopping all nr-ue instances..."
            pkill -9 -f 'nr-ue' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "602030000000001"
            cleanup_namespaces_for_imsi "602040000000002"
            cleanup_namespaces_for_imsi "602030000000003"
            cleanup_namespaces_for_imsi "001010000000001"
            cleanup_namespaces_for_imsi "001010000000002"
            ;;
        *)
            echo "[+] Stopping nr-ue instance for config ${id}..."
            pkill -9 -f "nr-ue.*${id}" 2>/dev/null || true
            sleep 1
            ;;
    esac
}

wait_for_ue_netns() {
    local imsi="$1"
    local timeout_secs="${2:-10}"
    local netns_internet="ueransim-${imsi}-internet-psi1"
    local netns_ims="ueransim-${imsi}-ims-psi2"
    local elapsed=0

    while [ "${elapsed}" -lt "$((timeout_secs * 10))" ]; do
        if ip netns list 2>/dev/null | grep -qw "${netns_internet}" && \
           ip netns list 2>/dev/null | grep -qw "${netns_ims}"; then
            if ip netns exec "${netns_internet}" ip link show uesimtun0 >/dev/null 2>&1 && \
               ip netns exec "${netns_ims}" ip link show uesimtun0 >/dev/null 2>&1; then
                return 0
            fi
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done

    echo "[-] Warning: Timeout waiting for namespaces (${netns_internet}, ${netns_ims}) after ${timeout_secs}s" >&2
    return 1
}

start_single_ue() {
    local name="$1"
    local config="$2"
    local log_file="$3"
    local imsi="$4"

    echo "─────────────────────────────────────────────────────────────────"
    echo "[+] Starting ${name} with config ${config}..."
    : > "${log_file}"
    setsid "${UE_BIN}" -c "${config}" >> "${log_file}" 2>&1 < /dev/null &
    local pid=$!

    if [ -n "${imsi}" ]; then
        wait_for_ue_netns "${imsi}" 10 || true
    else
        sleep 3
    fi

    if ps -p "${pid}" > /dev/null 2>&1; then
        echo "[✓] ${name} started successfully (PID: ${pid})"
        echo "[+] Log output: ${log_file}"
        tail -n 25 "${log_file}" || true
    else
        echo "[-] Failed to start ${name}. Log output:"
        cat "${log_file}"
        return 1
    fi
}

setup_netns_dns() {
    # Ensure known UE namespaces and any active namespaces have valid DNS config
    local known_ns=(
        "ueransim-602030000000001-internet-psi1"
        "ueransim-602030000000001-ims-psi2"
        "ueransim-602040000000002-internet-psi1"
        "ueransim-602040000000002-ims-psi2"
        "ueransim-602030000000003-internet-psi1"
        "ueransim-602030000000003-ims-psi2"
    )
    for ns in "${known_ns[@]}" $(ip netns list 2>/dev/null | awk '{print $1}'); do
        mkdir -p "/etc/netns/${ns}"
        cat << 'EOF' > "/etc/netns/${ns}/resolv.conf"
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
    done
}

TARGET="${1:-all}"

if [ "${TARGET}" = "stop" ]; then
    STOP_ID="${2:-all}"
    stop_ue "${STOP_ID}"
    exit 0
fi

case "${TARGET}" in
    1|ue1)
        stop_ue 1
        ensure_gnb_running
        start_single_ue "UE1 (602030000000001)" "${UE1_CONFIG}" "/tmp/ueransim-ue1.log" "602030000000001"
        cp -f "/tmp/ueransim-ue1.log" "/tmp/ueransim-ue.log" 2>/dev/null || true
        setup_netns_dns
        ;;
    2|ue2)
        stop_ue 2
        ensure_gnb_running
        start_single_ue "UE2 (602040000000002)" "${UE2_CONFIG}" "/tmp/ueransim-ue2.log" "602040000000002"
        setup_netns_dns
        ;;
    3|ue3)
        stop_ue 3
        ensure_gnb_running
        start_single_ue "UE3 (602030000000003 - Roaming 218/90)" "${UE3_CONFIG}" "/tmp/ueransim-ue3.log" "602030000000003"
        setup_netns_dns
        ;;
    all)
        stop_ue all
        ensure_gnb_running
        start_single_ue "UE1 (602030000000001)" "${UE1_CONFIG}" "/tmp/ueransim-ue1.log" "602030000000001"
        cp -f "/tmp/ueransim-ue1.log" "/tmp/ueransim-ue.log" 2>/dev/null || true
        start_single_ue "UE2 (602040000000002)" "${UE2_CONFIG}" "/tmp/ueransim-ue2.log" "602040000000002"
        start_single_ue "UE3 (602030000000003 - Roaming 218/90)" "${UE3_CONFIG}" "/tmp/ueransim-ue3.log" "602030000000003"
        setup_netns_dns
        ;;
    *)
        if [ -f "${TARGET}" ]; then
            stop_ue "${TARGET}"
            start_single_ue "UE (${TARGET})" "${TARGET}" "/tmp/ueransim-ue.log" ""
            setup_netns_dns
        else
            echo "[-] Error: Unknown target or configuration file '${TARGET}'" >&2
            echo "Usage: sudo bash scripts/run-ue.sh [1|2|3|all|stop|<config-file>]" >&2
            exit 1
        fi
        ;;
esac
