#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# Open Telecom Lab — Launch UERANSIM gNodeB
# ─────────────────────────────────────────────────────────────────
# Usage: bash scripts/run-gnb.sh
# ─────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/configs/ueransim/open5gs-gnb.yaml"
GNB_BIN="${REPO_ROOT}/UERANSIM/build/nr-gnb"
LOG_FILE="/tmp/ueransim-gnb.log"

if [ ! -x "${GNB_BIN}" ]; then
    if [ -x "/home/abdulrhamn/core/UERANSIM/build/nr-gnb" ]; then
        GNB_BIN="/home/abdulrhamn/core/UERANSIM/build/nr-gnb"
    else
        echo "[-] Error: nr-gnb binary not found at ${GNB_BIN}" >&2
        exit 1
    fi
fi

echo "[+] Stopping any existing nr-gnb processes..."
pkill -9 -f 'nr-gnb' 2>/dev/null || true
sleep 1

echo "[+] Starting UERANSIM gNodeB with config ${CONFIG}..."
: > "${LOG_FILE}"
setsid "${GNB_BIN}" -c "${CONFIG}" >> "${LOG_FILE}" 2>&1 < /dev/null &
PID=$!

sleep 2
if ps -p "${PID}" > /dev/null 2>&1; then
    echo "[✓] gNodeB started successfully (PID: ${PID})"
    echo "[+] Log output: ${LOG_FILE}"
    head -n 20 "${LOG_FILE}" || true
else
    echo "[-] Failed to start gNodeB. Log output:"
    cat "${LOG_FILE}"
    exit 1
fi
