#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Launch UERANSIM UE(s)
# ─────────────────────────────────────────────────────────────────
# Usage:
#   sudo bash scripts/run-ue.sh          # Launch both UE1 & UE2
#   sudo bash scripts/run-ue.sh all      # Launch both UE1 & UE2
#   sudo bash scripts/run-ue.sh 1        # Launch UE1 (IMSI 001010000000001)
#   sudo bash scripts/run-ue.sh 2        # Launch UE2 (IMSI 001010000000002)
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

cleanup_namespaces_for_imsi() {
    local imsi="$1"
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep "${imsi}" || true); do
        ip netns delete "${ns}" 2>/dev/null || true
    done
}

stop_ue() {
    local id="$1"
    case "${id}" in
        1|ue1)
            echo "[+] Stopping UE1 (IMSI 001010000000001)..."
            pkill -9 -f 'nr-ue.*open5gs-ue(\.yaml|1\.yaml)' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "001010000000001"
            ;;
        2|ue2)
            echo "[+] Stopping UE2 (IMSI 001010000000002)..."
            pkill -9 -f 'nr-ue.*open5gs-ue2\.yaml' 2>/dev/null || true
            sleep 1
            cleanup_namespaces_for_imsi "001010000000002"
            ;;
        all|"")
            echo "[+] Stopping all nr-ue instances..."
            pkill -9 -f 'nr-ue' 2>/dev/null || true
            sleep 1
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

    sleep 3
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
    sleep 1
    for ns in $(ip netns list 2>/dev/null | awk '{print $1}'); do
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
        start_single_ue "UE1 (001010000000001)" "${UE1_CONFIG}" "/tmp/ueransim-ue1.log" "001010000000001"
        cp -f "/tmp/ueransim-ue1.log" "/tmp/ueransim-ue.log" 2>/dev/null || true
        setup_netns_dns
        ;;
    2|ue2)
        stop_ue 2
        start_single_ue "UE2 (001010000000002)" "${UE2_CONFIG}" "/tmp/ueransim-ue2.log" "001010000000002"
        setup_netns_dns
        ;;
    all)
        stop_ue all
        start_single_ue "UE1 (001010000000001)" "${UE1_CONFIG}" "/tmp/ueransim-ue1.log" "001010000000001"
        cp -f "/tmp/ueransim-ue1.log" "/tmp/ueransim-ue.log" 2>/dev/null || true
        sleep 1
        start_single_ue "UE2 (001010000000002)" "${UE2_CONFIG}" "/tmp/ueransim-ue2.log" "001010000000002"
        setup_netns_dns
        ;;
    *)
        if [ -f "${TARGET}" ]; then
            stop_ue "${TARGET}"
            start_single_ue "UE (${TARGET})" "${TARGET}" "/tmp/ueransim-ue.log" ""
            setup_netns_dns
        else
            echo "[-] Error: Unknown target or configuration file '${TARGET}'" >&2
            echo "Usage: sudo bash scripts/run-ue.sh [1|2|all|stop|<config-file>]" >&2
            exit 1
        fi
        ;;
esac
