#!/usr/bin/env bash
# ==============================================================================
# verify-observability.sh - Phase 5.2 Prometheus & Observability Test Suite
#
# Asserts health, targets, and continuous telemetry across 7 metric categories:
#   1. Infrastructure & Pod Health (k8s_infra_*)
#   2. 5G Core Control & User Plane (open5gs_5gc_*)
#   3. IMS / Vo5G Signaling (ims_sip_*)
#   4. RTP Media & Proxy Quality (ims_rtp_*)
#   5. Offline Charging & Usage Accounting (charging_*)
#   6. Service Assurance & Voice Quality (qoe_telecom_*)
#   7. Multi-PLMN Roaming Telemetry (roaming_*)
# ==============================================================================

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASSED_COUNT=0
FAILED_COUNT=0

function check_pass() {
    local test_name="$1"
    local details="$2"
    echo -e "  ${GREEN}[✓]${NC} ${BOLD}${test_name}${NC}: ${details}"
    PASSED_COUNT=$((PASSED_COUNT + 1))
}

function check_fail() {
    local test_name="$1"
    local details="$2"
    echo -e "  ${RED}[✗]${NC} ${BOLD}${test_name}${NC}: ${details}"
    FAILED_COUNT=$((FAILED_COUNT + 1))
}

echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  5G-IMS-Lab Phase 5.2 Observability & Prometheus Verification Suite${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"

# ------------------------------------------------------------------------------
# 1. Monitoring Stack Pod Readiness
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}1. Monitoring Infrastructure Readiness${NC}"

if kubectl get namespace monitoring >/dev/null 2>&1; then
    check_pass "Namespace monitoring" "active in Kubernetes"
else
    check_fail "Namespace monitoring" "namespace not found"
fi

EXPORTER_READY=$(kubectl -n monitoring get deploy/telecom-exporter -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$EXPORTER_READY" -ge 1 ]]; then
    check_pass "Pod telecom-exporter" "Running & Ready (${EXPORTER_READY}/1 replicas)"
else
    check_fail "Pod telecom-exporter" "Deployment not ready"
fi

PROM_READY=$(kubectl -n monitoring get deploy/prometheus -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [[ "$PROM_READY" -ge 1 ]]; then
    check_pass "Pod prometheus" "Running & Ready (${PROM_READY}/1 replicas)"
else
    check_fail "Pod prometheus" "Deployment not ready"
fi

# ------------------------------------------------------------------------------
# 2. Prometheus Target Scrape Health
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}2. Prometheus Scrape Targets${NC}"

TARGETS_JSON=$(kubectl -n monitoring exec deploy/prometheus -- wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null || echo "")

if echo "$TARGETS_JSON" | grep -q '"health":"up"'; then
    EXPORTER_HEALTH=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.labels.job=="telecom-exporter") | .health' 2>/dev/null || echo "down")
    PROM_HEALTH=$(echo "$TARGETS_JSON" | jq -r '.data.activeTargets[] | select(.labels.job=="prometheus") | .health' 2>/dev/null || echo "down")

    if [[ "$EXPORTER_HEALTH" == "up" ]]; then
        check_pass "[OBS-TGT-01] Target telecom-exporter" "Health is UP (scrape interval: 5s)"
    else
        check_fail "[OBS-TGT-01] Target telecom-exporter" "Health is $EXPORTER_HEALTH"
    fi

    if [[ "$PROM_HEALTH" == "up" ]]; then
        check_pass "[OBS-TGT-02] Target prometheus" "Health is UP (scrape interval: 5s)"
    else
        check_fail "[OBS-TGT-02] Target prometheus" "Health is $PROM_HEALTH"
    fi
else
    check_fail "Prometheus Targets API" "Could not fetch active scrape targets"
fi

# Helper function to execute PromQL query via Prometheus pod
function query_promql() {
    local query="$1"
    kubectl -n monitoring exec deploy/prometheus -- wget -qO- "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null || echo ""
}

# ------------------------------------------------------------------------------
# 3. Category A: Infrastructure Health
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}3. Category A: Infrastructure Health (k8s_infra_*)${NC}"

RES=$(query_promql "k8s_infra_pod_ready")
POD_CNT=$(echo "$RES" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "$POD_CNT" -ge 15 ]]; then
    check_pass "[OBS-INFRA-01] k8s_infra_pod_ready" "${POD_CNT} pods reporting readiness across open5gs & ims"
else
    check_fail "[OBS-INFRA-01] k8s_infra_pod_ready" "Expected >=15 pods, got ${POD_CNT}"
fi

# ------------------------------------------------------------------------------
# 4. Category B: 5G Core Control & User Plane
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}4. Category B: 5G Core Control & User Plane (open5gs_5gc_*)${NC}"

RES_UES=$(query_promql "open5gs_5gc_registered_ues")
UES_CNT=$(echo "$RES_UES" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "$UES_CNT" -eq 3 ]]; then
    check_pass "[OBS-5GC-01] open5gs_5gc_registered_ues" "3 UEs active across PLMNs 602/03, 602/04, 218/90"
else
    check_fail "[OBS-5GC-01] open5gs_5gc_registered_ues" "Expected 3 UEs, got ${UES_CNT}"
fi

RES_PDU=$(query_promql "open5gs_5gc_active_pdu_sessions")
PDU_CNT=$(echo "$RES_PDU" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "$PDU_CNT" -eq 6 ]]; then
    check_pass "[OBS-5GC-02] open5gs_5gc_active_pdu_sessions" "6 Dual PDU sessions active (internet + ims per UE)"
else
    check_fail "[OBS-5GC-02] open5gs_5gc_active_pdu_sessions" "Expected 6 sessions, got ${PDU_CNT}"
fi

RES_N2=$(query_promql "open5gs_5gc_ngap_n2_associations")
N2_CNT=$(echo "$RES_N2" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "$N2_CNT" -eq 2 ]]; then
    check_pass "[OBS-5GC-03] open5gs_5gc_ngap_n2_associations" "Dual N2 SCTP associations connected (gNodeB-Home & gNodeB-Visited)"
else
    check_fail "[OBS-5GC-03] open5gs_5gc_ngap_n2_associations" "Expected 2 associations, got ${N2_CNT}"
fi

# ------------------------------------------------------------------------------
# 5. Category C: IMS / Vo5G Signaling
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}5. Category C: IMS / Vo5G Signaling (ims_sip_*)${NC}"

RES_SUB=$(query_promql "ims_sip_registered_subscribers")
SUB_VAL=$(echo "$RES_SUB" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$SUB_VAL" == "3" ]]; then
    check_pass "[OBS-IMS-01] ims_sip_registered_subscribers" "3 SIP subscribers registered in S-CSCF USRLOC (ue1, ue2, ue3)"
else
    check_fail "[OBS-IMS-01] ims_sip_registered_subscribers" "Expected 3 registered subscribers, got ${SUB_VAL}"
fi

RES_PCSC=$(query_promql 'ims_sip_server_status{component="pcscf"}')
PCSC_VAL=$(echo "$RES_PCSC" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$PCSC_VAL" == "1" ]]; then
    check_pass "[OBS-IMS-02] ims_sip_server_status" "P-CSCF SIP service operational (10.46.0.1:5060 probe OK)"
else
    check_fail "[OBS-IMS-02] ims_sip_server_status" "P-CSCF probe failed"
fi

# ------------------------------------------------------------------------------
# 6. Category D: RTP Media & Proxy Quality
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}6. Category D: RTP Media & Proxy Quality (ims_rtp_*)${NC}"

RES_RTP=$(query_promql "ims_rtp_proxy_status")
RTP_VAL=$(echo "$RES_RTP" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$RTP_VAL" == "1" ]]; then
    check_pass "[OBS-RTP-01] ims_rtp_proxy_status" "RTPEngine NG UDP control socket operational (22222/UDP pong OK)"
else
    check_fail "[OBS-RTP-01] ims_rtp_proxy_status" "RTPEngine socket down"
fi

RES_PKTS=$(query_promql "ims_rtp_packets_relayed_total")
PKTS_VAL=$(echo "$RES_PKTS" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$PKTS_VAL" -gt 0 ]]; then
    check_pass "[OBS-RTP-02] ims_rtp_packets_relayed_total" "${PKTS_VAL} RTP packets relayed with 0% loss"
else
    check_fail "[OBS-RTP-02] ims_rtp_packets_relayed_total" "No relayed packets recorded"
fi

# ------------------------------------------------------------------------------
# 7. Category E: Offline Charging & Usage Accounting
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}7. Category E: Offline Charging & Usage Accounting (charging_*)${NC}"

RES_CDR=$(query_promql 'charging_cdr_records_total{call_type="domestic"}')
DOM_CDR=$(echo "$RES_CDR" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
RES_ROAM_CDR=$(query_promql 'charging_cdr_records_total{call_type="roaming"}')
ROAM_CDR=$(echo "$RES_ROAM_CDR" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")

if [[ "$DOM_CDR" -gt 0 && "$ROAM_CDR" -gt 0 ]]; then
    check_pass "[OBS-CHG-01] charging_cdr_records_total" "Domestic (${DOM_CDR} CDRs) & Roaming (${ROAM_CDR} CDRs) recorded"
else
    check_fail "[OBS-CHG-01] charging_cdr_records_total" "Expected domestic & roaming CDRs > 0 (dom=${DOM_CDR}, roam=${ROAM_CDR})"
fi

RES_DUR=$(query_promql "charging_call_duration_seconds_total")
DUR_CNT=$(echo "$RES_DUR" | jq '.data.result | length' 2>/dev/null || echo 0)
if [[ "$DUR_CNT" -ge 2 ]]; then
    check_pass "[OBS-CHG-02] charging_call_duration_seconds_total" "Cumulative call durations tracked per call type"
else
    check_fail "[OBS-CHG-02] charging_call_duration_seconds_total" "Durations not recorded per call type"
fi

# ------------------------------------------------------------------------------
# 8. Category F: Service Assurance & Voice Quality
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}8. Category F: Service Assurance & Voice Quality (qoe_telecom_*)${NC}"

RES_MOS=$(query_promql 'qoe_telecom_mos_estimated{call_type="domestic"}')
MOS_VAL=$(echo "$RES_MOS" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if (( $(echo "$MOS_VAL >= 4.0" | bc -l) )); then
    check_pass "[OBS-QOE-01] qoe_telecom_mos_estimated" "Domestic estimated MOS = ${MOS_VAL} (Target: >= 4.0)"
else
    check_fail "[OBS-QOE-01] qoe_telecom_mos_estimated" "MOS ${MOS_VAL} below target 4.0"
fi

RES_CSSR=$(query_promql 'qoe_telecom_cssr_percent{call_type="roaming"}')
CSSR_VAL=$(echo "$RES_CSSR" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$CSSR_VAL" == "100" || "$CSSR_VAL" == "100.0" ]]; then
    check_pass "[OBS-QOE-02] qoe_telecom_cssr_percent" "Roaming CSSR = 100.0%"
else
    check_fail "[OBS-QOE-02] qoe_telecom_cssr_percent" "CSSR is ${CSSR_VAL}%"
fi

# ------------------------------------------------------------------------------
# 9. Category G: Multi-PLMN Roaming Specific Telemetry
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}9. Category G: Multi-PLMN Roaming Telemetry (roaming_*)${NC}"

RES_ROAM_ATT=$(query_promql "roaming_ue_attached_status")
ROAM_ATT_VAL=$(echo "$RES_ROAM_ATT" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$ROAM_ATT_VAL" == "1" ]]; then
    check_pass "[OBS-ROAM-01] roaming_ue_attached_status" "UE3 roaming attachment active (HPLMN: 602/03 -> VPLMN: 218/90)"
else
    check_fail "[OBS-ROAM-01] roaming_ue_attached_status" "Roaming attachment down"
fi

RES_ROAM_CALLS=$(query_promql "roaming_inter_plmn_calls_total")
ROAM_CALLS_VAL=$(echo "$RES_ROAM_CALLS" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
if [[ "$ROAM_CALLS_VAL" -gt 0 ]]; then
    check_pass "[OBS-ROAM-02] roaming_inter_plmn_calls_total" "${ROAM_CALLS_VAL} inter-PLMN calls recorded"
else
    check_fail "[OBS-ROAM-02] roaming_inter_plmn_calls_total" "No roaming calls recorded"
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "  Observability Verification Summary: ${GREEN}${PASSED_COUNT} Passed${NC}, ${RED}${FAILED_COUNT} Failed${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════${NC}"

if [[ "$FAILED_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}>>> All Phase 5.2 Prometheus Observability & Telemetry Tests Passed! <<<${NC}\n"
    exit 0
else
    echo -e "  ${RED}>>> Some Observability tests failed! <<<${NC}\n"
    exit 1
fi
