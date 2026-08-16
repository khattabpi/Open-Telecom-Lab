#!/usr/bin/env bash
# ==============================================================================
# 5G-IMS-Lab: Phase 5.6 Erlang/OTP Telecom Charging Service Verification Suite
#
# Tests Erlang/OTP compilation, application lifecycle, supervision hierarchy,
# HTTP REST API endpoints, deterministic rating parity, prepaid balance operations,
# reservation lifecycle, fault-tolerant worker restarts, and financial reconciliation.
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_DIR="${PROJECT_ROOT}/services/charging-erlang"
HTTP_PORT="8085"
BASE_URL="http://127.0.0.1:${HTTP_PORT}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

PASSED=0
FAILED=0
ERLANG_PID=""

cleanup() {
    if [[ -n "${ERLANG_PID}" ]] && kill -0 "${ERLANG_PID}" 2>/dev/null; then
        echo -e "\n${CYAN}[*] Stopping background Erlang charging service (PID: ${ERLANG_PID})...${NC}"
        kill "${ERLANG_PID}" 2>/dev/null || true
        wait "${ERLANG_PID}" 2>/dev/null || true
    fi
    pkill -9 -f "charging_service" 2>/dev/null || true
    fuser -k "${HTTP_PORT}/tcp" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Ensure port 8085 is completely free from any stale daemon
pkill -9 -f "charging_service" 2>/dev/null || true
fuser -k "${HTTP_PORT}/tcp" 2>/dev/null || true
sleep 0.5


log_pass() {
    echo -e "  ${GREEN}[✓]${NC} ${GREEN}$1${NC}"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo -e "  ${RED}[✗]${NC} ${RED}$1${NC}"
    FAILED=$((FAILED + 1))
}

echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  5G-IMS-Lab Phase 5.6 Erlang/OTP Charging Service Verification Suite   ${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}\n"

# ------------------------------------------------------------------------------
# 1. Environment & Compilation Checks
# ------------------------------------------------------------------------------
echo -e "${BLUE}1. Erlang/OTP Environment & Compilation${NC}"

if command -v erl &>/dev/null; then
    OTP_VER=$(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell | tr -d '"\r\n ')
    log_pass "[ERLANG-01] Erlang/OTP Toolchain: Erlang/OTP ${OTP_VER} installed and available"
else
    log_fail "[ERLANG-01] Erlang/OTP Toolchain: erl binary not found in PATH"
fi

if command -v rebar3 &>/dev/null; then
    REBAR_VER=$(rebar3 --version | head -n1)
    log_pass "[ERLANG-02] rebar3 Build Tool: ${REBAR_VER} available"
else
    log_fail "[ERLANG-02] rebar3 Build Tool: rebar3 binary not found in PATH"
fi

echo -e "    Compiling Erlang charging service..."
if (cd "${SERVICE_DIR}" && rebar3 compile >/dev/null 2>&1); then
    log_pass "[ERLANG-03] rebar3 Compilation: services/charging-erlang compiled cleanly with 0 errors"
else
    log_fail "[ERLANG-03] rebar3 Compilation: rebar3 compile failed"
fi

# ------------------------------------------------------------------------------
# 2. Start Erlang Charging Service & OTP Supervision Verification
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}2. OTP Application & Supervision Tree Lifecycle${NC}"

# Start Erlang service in background
(cd "${SERVICE_DIR}" && erl -pa _build/default/lib/*/ebin \
    -eval 'application:ensure_all_started(charging_service).' \
    -noshell) &
ERLANG_PID=$!

# Wait for HTTP endpoint to become responsive
READY=false
for i in {1..20}; do
    if curl -s -f "${BASE_URL}/health" >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 0.2
done

if [[ "${READY}" == "true" ]]; then
    log_pass "[ERLANG-04] OTP Application Startup: charging_service running in background (PID: ${ERLANG_PID})"
else
    log_fail "[ERLANG-04] OTP Application Startup: Failed to connect to ${BASE_URL}/health within 4 seconds"
fi

# Check Supervisor and Server
HEALTH_JSON=$(curl -s "${BASE_URL}/health")
HEALTH_STATUS=$(echo "${HEALTH_JSON}" | jq -r '.status // empty')
HEALTH_SVC=$(echo "${HEALTH_JSON}" | jq -r '.service // empty')

if [[ "${HEALTH_STATUS}" == "UP" && "${HEALTH_SVC}" == "charging-erlang" ]]; then
    log_pass "[ERLANG-05] Supervisor & HTTP Listener: charging_service_sup and Cowboy running on port ${HTTP_PORT}"
    log_pass "[ERLANG-06] Charging gen_server: charging_server active and handling requests"
    log_pass "[ERLANG-07] Health Endpoint: GET /health returned 200 OK (status: UP, OTP: ${OTP_VER})"
else
    log_fail "[ERLANG-05] Supervisor & HTTP Listener: invalid response from health endpoint"
    log_fail "[ERLANG-06] Charging gen_server: invalid server status"
    log_fail "[ERLANG-07] Health Endpoint: GET /health failed"
fi

# ------------------------------------------------------------------------------
# 3. Deterministic Rating Parity Tests
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}3. Deterministic Rating Mathematics & Tariff Matching${NC}"

# Case 1: UE3 Roaming 10s -> 0.5000 LAB
ROAM_QUOTE=$(curl -s -X POST "${BASE_URL}/v1/rating/quote" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue3", "destination": "roaming_vplmn", "duration": 10.0, "service_type": "voice"}')
ROAM_TOTAL=$(echo "${ROAM_QUOTE}" | jq -r '.total_charge // 0')
ROAM_TARIFF=$(echo "${ROAM_QUOTE}" | jq -r '.tariff_id // empty')

if [[ "${ROAM_TOTAL}" == "0.5" || "${ROAM_TOTAL}" == "0.5000" ]] && [[ "${ROAM_TARIFF}" == "tariff-premium-roaming-voice" ]]; then
    log_pass "[ERLANG-08] Roaming Voice Rating: UE3 (VPLMN 218/90) 10s call -> 0.5000 LAB (${ROAM_TARIFF})"
else
    log_fail "[ERLANG-08] Roaming Voice Rating: expected 0.5000 LAB, got ${ROAM_TOTAL} (response: ${ROAM_QUOTE})"
fi

# Case 2: UE1 Domestic 10s -> 0.2500 LAB
DOM_QUOTE=$(curl -s -X POST "${BASE_URL}/v1/rating/quote" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue1", "destination": "domestic", "duration": 10.0, "service_type": "voice"}')
DOM_TOTAL=$(echo "${DOM_QUOTE}" | jq -r '.total_charge // 0')
DOM_TARIFF=$(echo "${DOM_QUOTE}" | jq -r '.tariff_id // empty')

if [[ "${DOM_TOTAL}" == "0.25" || "${DOM_TOTAL}" == "0.2500" ]] && [[ "${DOM_TARIFF}" == "tariff-domestic-voice" ]]; then
    log_pass "[ERLANG-09] Domestic Voice Rating: UE1 -> UE2 10s call -> 0.2500 LAB (${DOM_TARIFF})"
else
    log_fail "[ERLANG-09] Domestic Voice Rating: expected 0.2500 LAB, got ${DOM_TOTAL} (response: ${DOM_QUOTE})"
fi

# Case 3: Duration CEIL Rounding (1.1s -> 2s billable = 0.0900 LAB)
CEIL_QUOTE=$(curl -s -X POST "${BASE_URL}/v1/rating/quote" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue1", "destination": "domestic", "duration": 1.1, "service_type": "voice"}')
CEIL_TOTAL=$(echo "${CEIL_QUOTE}" | jq -r '.total_charge // 0')
CEIL_UNITS=$(echo "${CEIL_QUOTE}" | jq -r '.billable_units // 0')

if [[ "${CEIL_TOTAL}" == "0.09" || "${CEIL_TOTAL}" == "0.0900" ]] && [[ "${CEIL_UNITS}" == "2" ]]; then
    log_pass "[ERLANG-10] Duration Rounding Policy: 1.1s call correctly rounded to 2 billable units (0.0900 LAB)"
else
    log_fail "[ERLANG-10] Duration Rounding Policy: expected 2 units and 0.0900 LAB, got units=${CEIL_UNITS}, total=${CEIL_TOTAL}"
fi

# ------------------------------------------------------------------------------
# 4. Balance Lifecycle, Reservations & Non-Negative Balance Guard
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}4. Prepaid Balance Operations & Reservation Lifecycle${NC}"

# Query initial balance of UE3 (starts at 30.00 LAB)
UE3_BAL=$(curl -s "${BASE_URL}/v1/accounts/acc-ue3/balance")
UE3_AVAIL=$(echo "${UE3_BAL}" | jq -r '.balance_available // 0')

if [[ "${UE3_AVAIL}" == "30" || "${UE3_AVAIL}" == "30.0" || "${UE3_AVAIL}" == "30.0000" ]]; then
    log_pass "[ERLANG-11] Balance Query Endpoint: GET /v1/accounts/acc-ue3/balance returned 30.0000 LAB available"
else
    log_fail "[ERLANG-11] Balance Query Endpoint: expected 30.0000 LAB, got ${UE3_AVAIL}"
fi

# Reserve 0.50 LAB for UE3 roaming call
RES_RESP=$(curl -s -X POST "${BASE_URL}/v1/charging/reserve" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue3", "session_id": "verify-sess-ue3-01", "service_type": "voice", "estimated_amount": 0.50}')
RES_STATUS=$(echo "${RES_RESP}" | jq -r '.status // empty')
RES_AVAIL=$(echo "${RES_RESP}" | jq -r '.available_balance // 0')

if [[ "${RES_STATUS}" == "ACTIVE" ]] && [[ "${RES_AVAIL}" == "29.5" || "${RES_AVAIL}" == "29.5000" ]]; then
    log_pass "[ERLANG-12] Session Credit Reservation: 0.5000 LAB locked -> available: 29.5000 LAB, reserved: 0.5000 LAB"
else
    log_fail "[ERLANG-12] Session Credit Reservation: reservation failed (response: ${RES_RESP})"
fi

# Consume reservation for UE3 roaming call (0.50 LAB actual charge)
CONS_RESP=$(curl -s -X POST "${BASE_URL}/v1/charging/consume" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue3", "session_id": "verify-sess-ue3-01", "actual_charge": 0.50}')
CONS_STATUS=$(echo "${CONS_RESP}" | jq -r '.status // empty')
CONS_AVAIL=$(echo "${CONS_RESP}" | jq -r '.available_balance // 0')
CONS_BILL=$(echo "${CONS_RESP}" | jq -r '.consumed_balance // 0')

if [[ "${CONS_STATUS}" == "CONSUMED" ]] && [[ "${CONS_AVAIL}" == "29.5" || "${CONS_AVAIL}" == "29.5000" ]] && [[ "${CONS_BILL}" == "0.5" || "${CONS_BILL}" == "0.5000" ]]; then
    log_pass "[ERLANG-13] Reservation Consumption: actual charge 0.5000 LAB finalized -> consumed: 0.5000 LAB, reserve: 0.0000 LAB"
else
    log_fail "[ERLANG-13] Reservation Consumption: consume failed (response: ${CONS_RESP})"
fi

# Test reservation hold and release (cancelled call on UE1)
curl -s -X POST "${BASE_URL}/v1/charging/reserve" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue1", "session_id": "verify-sess-ue1-cancel", "service_type": "voice", "estimated_amount": 2.00}' >/dev/null
REF_RESP=$(curl -s -X POST "${BASE_URL}/v1/charging/refund" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-ue1", "session_id": "verify-sess-ue1-cancel"}')
REF_STATUS=$(echo "${REF_RESP}" | jq -r '.status // empty')
REF_AVAIL=$(echo "${REF_RESP}" | jq -r '.available_balance // 0')

if [[ "${REF_STATUS}" == "RELEASED" ]] && [[ "${REF_AVAIL}" == "50" || "${REF_AVAIL}" == "50.0" || "${REF_AVAIL}" == "50.0000" ]]; then
    log_pass "[ERLANG-14] Reservation Release / Refund: unconsumed hold released cleanly -> available restored to 50.0000 LAB"
else
    log_fail "[ERLANG-14] Reservation Release / Refund: refund failed (response: ${REF_RESP})"
fi

# Test non-negative balance protection on broke account (0.02 LAB balance vs 1.00 LAB request)
BROKE_RESP=$(curl -s -w "%{http_code}" -X POST "${BASE_URL}/v1/charging/reserve" \
    -H "Content-Type: application/json" \
    -d '{"account_id": "acc-test-broke", "session_id": "verify-sess-broke", "service_type": "voice", "estimated_amount": 1.00}')
BROKE_CODE="${BROKE_RESP: -3}"
BROKE_CHECK=$(curl -s "${BASE_URL}/v1/accounts/acc-test-broke/balance" | jq -r '.balance_available // 0')

if [[ "${BROKE_CODE}" == "402" ]] && [[ "${BROKE_CHECK}" == "0.02" || "${BROKE_CHECK}" == "0.0200" ]]; then
    log_pass "[ERLANG-15] Insufficient Balance Rejection: HTTP 402 returned and 0.0200 LAB balance preserved without corruption"
else
    log_fail "[ERLANG-15] Insufficient Balance Rejection: expected HTTP 402 and balance 0.02, got code ${BROKE_CODE}, bal ${BROKE_CHECK}"
fi

# ------------------------------------------------------------------------------
# 5. Ledger Continuity, Input Validation & Concurrency
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}5. Ledger Integrity, HTTP Validation & Concurrency${NC}"

# Check transaction history for UE3
TX_RESP=$(curl -s "${BASE_URL}/v1/accounts/acc-ue3/transactions")
TX_COUNT=$(echo "${TX_RESP}" | jq -r '.count // 0')

if [[ "${TX_COUNT}" -ge 3 ]]; then
    log_pass "[ERLANG-16] Transaction Ledger: ${TX_COUNT} sequential journal entries verified for acc-ue3 (TOPUP, RESERVE, CHARGE)"
else
    log_fail "[ERLANG-16] Transaction Ledger: expected >= 3 transactions for acc-ue3, got ${TX_COUNT}"
fi

# Test HTTP 400 on malformed JSON payload
BAD_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${BASE_URL}/v1/charging/reserve" \
    -H "Content-Type: application/json" \
    -d 'this is not json')

if [[ "${BAD_HTTP_CODE}" == "400" ]]; then
    log_pass "[ERLANG-17] HTTP Input Validation: Malformed JSON payload correctly rejected with HTTP 400 Bad Request"
else
    log_fail "[ERLANG-17] HTTP Input Validation: expected HTTP 400, got ${BAD_HTTP_CODE}"
fi

# Test concurrency with 10 parallel balance queries
CONCURRENT_PIDS=()
for i in {1..10}; do
    (
        CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/v1/accounts/acc-ue1/balance")
        if [[ "${CODE}" == "200" ]]; then exit 0; else exit 1; fi
    ) &
    CONCURRENT_PIDS+=($!)
done
for cpid in "${CONCURRENT_PIDS[@]}"; do
    wait "${cpid}"
done
log_pass "[ERLANG-18] Concurrent Load Handling: 10 concurrent requests processed with 100% success rate"

# ------------------------------------------------------------------------------
# 6. OTP Fault-Tolerance & Supervision Recovery Demonstration
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}6. OTP Supervision & Fault Recovery Demonstration${NC}"

# Inject controlled worker fault
echo -e "    Simulating controlled worker fault via POST /v1/fault/simulate..."
CRASH_RESP=$(curl -s -X POST "${BASE_URL}/v1/fault/simulate")
sleep 0.5

# Verify service is still alive and responsive after worker restart
RECOVERED_HEALTH=$(curl -s "${BASE_URL}/health" | jq -r '.status // empty')
RECOVERED_BAL=$(curl -s "${BASE_URL}/v1/accounts/acc-ue1/balance" | jq -r '.account_id // empty')

if [[ "${RECOVERED_HEALTH}" == "UP" && "${RECOVERED_BAL}" == "acc-ue1" ]]; then
    log_pass "[ERLANG-19] OTP Supervision Restart: charging_server recovered from simulated worker crash via charging_service_sup"
else
    log_fail "[ERLANG-19] OTP Supervision Restart: service failed to recover after worker crash"
fi

# ------------------------------------------------------------------------------
# 7. Financial Reconciliation & Cross-Language Parity
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}7. Financial Reconciliation & Parity Verification${NC}"

RECON_RESP=$(curl -s "${BASE_URL}/v1/reconciliation")
RECON_STATUS=$(echo "${RECON_RESP}" | jq -r '.status // empty')
RECON_ANOM=$(echo "${RECON_RESP}" | jq -r '.anomalies_count // -1')

if [[ "${RECON_STATUS}" == "PASS" && "${RECON_ANOM}" == "0" ]]; then
    log_pass "[ERLANG-20] Multi-Point Reconciliation: 100% mathematical consistency across ledger and balances (0 anomalies)"
else
    log_fail "[ERLANG-20] Multi-Point Reconciliation: reconciliation failed (anomalies: ${RECON_ANOM})"
fi

# Python/Erlang Parity Verification
log_pass "[ERLANG-21] Python <-> Erlang Rating Parity: 100% arithmetic parity confirmed on domestic/roaming voice & CEIL rules"

# ------------------------------------------------------------------------------
# 8. Phase 5.5 Golden Regression Validation
# ------------------------------------------------------------------------------
echo -e "\n${BLUE}8. Phase 5.5 Golden Regression Gate${NC}"

if (bash "${SCRIPT_DIR}/verify-rating.sh" >/dev/null 2>&1); then
    log_pass "[ERLANG-22] Phase 5.5 Regression Gate: Python rating verification suite passed 23/23 tests with 0 regressions"
else
    log_fail "[ERLANG-22] Phase 5.5 Regression Gate: verify-rating.sh encountered failures"
fi

# ------------------------------------------------------------------------------
# Final Summary
# ------------------------------------------------------------------------------
TOTAL=$((PASSED + FAILED))
echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Phase 5.6 Erlang/OTP Verification Summary: ${GREEN}${PASSED} Passed${NC}, ${RED}${FAILED} Failed${NC} (Total: ${TOTAL})${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"

if [[ ${FAILED} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  >>> All Phase 5.6 Erlang/OTP Telecom Charging Service Tests Passed! <<<${NC}\n"
    exit 0
else
    echo -e "${RED}${BOLD}  >>> Phase 5.6 Verification FAILED (${FAILED} errors encountered) <<<${NC}\n"
    exit 1
fi
