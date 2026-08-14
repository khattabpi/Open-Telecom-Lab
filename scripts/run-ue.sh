#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Launch UERANSIM UE
# ─────────────────────────────────────────────────────────────────
# Usage: sudo bash scripts/run-ue.sh
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/configs/ueransim/open5gs-ue.yaml"
UE_BIN="${REPO_ROOT}/UERANSIM/build/nr-ue"
LOG_FILE="/tmp/ueransim-ue.log"

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

echo "[+] Stopping any existing nr-ue processes..."
pkill -9 -f 'nr-ue' 2>/dev/null || true
sleep 1

echo "[+] Starting UERANSIM UE with config ${CONFIG}..."
: > "${LOG_FILE}"
setsid "${UE_BIN}" -c "${CONFIG}" >> "${LOG_FILE}" 2>&1 < /dev/null &
PID=$!

sleep 3
if ps -p "${PID}" > /dev/null 2>&1; then
    echo "[✓] UE started successfully (PID: ${PID})"
    echo "[+] Log output: ${LOG_FILE}"
    tail -n 25 "${LOG_FILE}" || true
else
    echo "[-] Failed to start UE. Log output:"
    cat "${LOG_FILE}"
    exit 1
fi
