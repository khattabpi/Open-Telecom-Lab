# Prometheus Metrics Collection & Exporter Deployment (Phase 5.2)

This document details the production-grade Prometheus telemetry collection layer implemented in **Phase 5.2** of the **5G-IMS-Lab** project.

---

## 1. Overview & Architecture

Phase 5.2 operationalizes the telemetry model defined in Phase 5.1 by deploying a continuous metric scraping pipeline inside Kubernetes:

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                Kubernetes Cluster (kind)                │
                  │                                                         │
                  │   ┌───────────────────┐        ┌───────────────────┐    │
                  │   │  telecom-exporter │ ◄────  │    Prometheus     │    │
                  │   │     (:9100)       │        │      (:9090)      │    │
                  │   └─────────┬─────────┘        └───────────────────┘    │
                  │             │ (Periodic Scrapes every 5s)               │
                  └─────────────┼───────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌──────────────────┐    ┌───────────────────┐   ┌───────────────────────────┐
│ Kubernetes API   │    │ Kamailio S-CSCF   │   │ RTPEngine NG Protocol     │
│ Pod Status /     │    │ USRLOC / Dialogs  │   │ UDP :22222 Bencode        │
│ Readiness        │    │ SQLite CDR DB     │   │ Relayed Pkts / Errors     │
└──────────────────┘    └───────────────────┘   └───────────────────────────┘
```

---

## 2. Kubernetes Deployment Topology

All observability components are isolated inside the `monitoring` namespace:

| Component | Kind | Namespace | Port / Target | Base Image | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`telecom-exporter`** | Deployment + Service | `monitoring` | `9100/TCP` | `ims-node:latest` | Samples K8s API, S-CSCF, RTPEngine, CDRs, NetNS counters, & QoE KPIs |
| **`prometheus`** | Deployment + Service | `monitoring` | `9090/TCP` (`NodePort: 30090`) | `prom/prometheus:v2.45.0` | TSDB scraping engine evaluating rules and storing time series |
| **`telecom-monitoring`** | ServiceAccount + RBAC | `monitoring` | N/A | N/A | ClusterRole granting get/list/watch access to pods, endpoints, nodes |

---

## 3. Scrape Configuration

Prometheus is configured via ConfigMap [`k8s/monitoring/prometheus.yaml`](file:///home/abdulrhamn/5G-IMS-Lab/k8s/monitoring/prometheus.yaml) with high-frequency scraping:

```yaml
global:
  scrape_interval: 5s
  evaluation_interval: 5s
  scrape_timeout: 4s
  external_labels:
    environment: '5g-ims-lab'
    cluster: 'open5gs-cluster'

scrape_configs:
  - job_name: 'telecom-exporter'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['telecom-exporter.monitoring.svc.cluster.local:9100']
        labels:
          app: 'telecom-exporter'
          layer: '5g-ims-telemetry'

  - job_name: 'prometheus'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          app: 'prometheus'
```

---

## 4. Continuous Telemetry across 7 Domains

The exporter provides continuous, strictly formatted Prometheus exposition metrics across 7 telecom domains:

### Category A: Infrastructure & Pod Health (`k8s_infra_*`)
- `k8s_infra_pod_ready{namespace, pod_name, app}`
- `k8s_infra_pod_status{namespace, pod_name, app}`
- `k8s_infra_container_restarts_total{namespace, pod_name, container}`

### Category B: 5G Core Control & User Plane (`open5gs_5gc_*`)
- `open5gs_5gc_nf_status{nf_name, role}`
- `open5gs_5gc_registered_ues{plmn, role}`
- `open5gs_5gc_active_pdu_sessions{ue_id, dnn, role}`
- `open5gs_5gc_ngap_n2_associations{gnb_instance, target_amf, plmn}`
- `open5gs_5gc_pfcp_n4_status{smf_instance, endpoint}`
- `open5gs_5gc_gtpu_n3_bytes_total{direction, interface}`

### Category C: IMS / Vo5G Signaling (`ims_sip_*`)
- `ims_sip_server_status{component}`
- `ims_sip_registered_subscribers{domain, component}`
- `ims_sip_subscriber_reg_status{ue_id, domain}`
- `ims_sip_requests_total{sip_method, component}`
- `ims_sip_active_dialogs{component}`

### Category D: RTP Media & Proxy Quality (`ims_rtp_*`)
- `ims_rtp_proxy_status{endpoint}`
- `ims_rtp_managed_sessions_total{proxy}`
- `ims_rtp_active_sessions{proxy}`
- `ims_rtp_packets_relayed_total{proxy}`
- `ims_rtp_bytes_relayed_total{proxy}`
- `ims_rtp_packet_errors_total{proxy}`

### Category E: Offline Charging & Usage Accounting (`charging_*`)
- `charging_cdr_records_total{call_type, sip_code}`
- `charging_call_duration_seconds_total{call_type}`
- `charging_last_call_duration_seconds{call_type, caller, callee}`

### Category F: Service Assurance & Voice Quality (`qoe_telecom_*`)
- `qoe_telecom_pdd_seconds{call_type}`
- `qoe_telecom_cst_seconds{call_type}`
- `qoe_telecom_cssr_percent{call_type}`
- `qoe_telecom_packet_loss_ratio{call_type, direction}`
- `qoe_telecom_jitter_ms{call_type, direction}`
- `qoe_telecom_r_factor{call_type}`
- `qoe_telecom_mos_estimated{call_type}`

### Category G: Multi-PLMN Roaming Specific Telemetry (`roaming_*`)
- `roaming_ue_attached_status{ue_id, hplmn, vplmn}`
- `roaming_lbo_user_plane_status{vplmn, vupf_ip}`
- `roaming_inter_plmn_calls_total{origin_plmn, target_plmn}`
- `roaming_inter_plmn_success_rate{origin_plmn, target_plmn}`

---

## 5. Verification & Validation Commands

### Run Dedicated Observability Suite
```bash
./scripts/verify-observability.sh
```

**Output**:
```text
═══════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Phase 5.2 Observability & Prometheus Verification Suite
═══════════════════════════════════════════════════════════════════════

1. Monitoring Infrastructure Readiness
  [✓] Namespace monitoring: active in Kubernetes
  [✓] Pod telecom-exporter: Running & Ready (1/1 replicas)
  [✓] Pod prometheus: Running & Ready (1/1 replicas)

2. Prometheus Scrape Targets
  [✓] [OBS-TGT-01] Target telecom-exporter: Health is UP (scrape interval: 5s)
  [✓] [OBS-TGT-02] Target prometheus: Health is UP (scrape interval: 5s)

3. Category A: Infrastructure Health (k8s_infra_*)
  [✓] [OBS-INFRA-01] k8s_infra_pod_ready: 16 pods reporting readiness across open5gs & ims

4. Category B: 5G Core Control & User Plane (open5gs_5gc_*)
  [✓] [OBS-5GC-01] open5gs_5gc_registered_ues: 3 UEs active across PLMNs 602/03, 602/04, 218/90
  [✓] [OBS-5GC-02] open5gs_5gc_active_pdu_sessions: 6 Dual PDU sessions active (internet + ims per UE)
  [✓] [OBS-5GC-03] open5gs_5gc_ngap_n2_associations: Dual N2 SCTP associations connected (gNodeB-Home & gNodeB-Visited)

5. Category C: IMS / Vo5G Signaling (ims_sip_*)
  [✓] [OBS-IMS-01] ims_sip_registered_subscribers: 3 SIP subscribers registered in S-CSCF USRLOC (ue1, ue2, ue3)
  [✓] [OBS-IMS-02] ims_sip_server_status: P-CSCF SIP service operational (10.46.0.1:5060 probe OK)

6. Category D: RTP Media & Proxy Quality (ims_rtp_*)
  [✓] [OBS-RTP-01] ims_rtp_proxy_status: RTPEngine NG UDP control socket operational (22222/UDP pong OK)
  [✓] [OBS-RTP-02] ims_rtp_packets_relayed_total: 9550 RTP packets relayed with 0% loss

7. Category E: Offline Charging & Usage Accounting (charging_*)
  [✓] [OBS-CHG-01] charging_cdr_records_total: Domestic (35 CDRs) & Roaming (35 CDRs) recorded
  [✓] [OBS-CHG-02] charging_call_duration_seconds_total: Cumulative call durations tracked per call type

8. Category F: Service Assurance & Voice Quality (qoe_telecom_*)
  [✓] [OBS-QOE-01] qoe_telecom_mos_estimated: Domestic estimated MOS = 4.4 (Target: >= 4.0)
  [✓] [OBS-QOE-02] qoe_telecom_cssr_percent: Roaming CSSR = 100.0%

9. Category G: Multi-PLMN Roaming Telemetry (roaming_*)
  [✓] [OBS-ROAM-01] roaming_ue_attached_status: UE3 roaming attachment active (HPLMN: 602/03 -> VPLMN: 218/90)
  [✓] [OBS-ROAM-02] roaming_inter_plmn_calls_total: 35 inter-PLMN calls recorded

═══════════════════════════════════════════════════════════════════════
  Observability Verification Summary: 19 Passed, 0 Failed
═══════════════════════════════════════════════════════════════════════
  >>> All Phase 5.2 Prometheus Observability & Telemetry Tests Passed! <<<
```

### Full System Regression Verification
```bash
sudo ./scripts/verify-lab.sh
```
Result: **91 Passed, 0 Failed, 0 Warnings**.
