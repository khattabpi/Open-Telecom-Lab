# Grafana Operations Dashboard (Phase 5.3)

This document details the architecture, design, queries, and validation of the **Telecom Operations Dashboard** deployed in **Phase 5.3** of the **5G-IMS-Lab** project.

---

## 1. Overview & Architecture

Phase 5.3 establishes a centralized, operational visualization layer on top of the Prometheus scraping pipeline deployed in Phase 5.2.

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                Kubernetes Cluster (kind)                │
                  │                                                         │
                  │   ┌───────────────────┐        ┌───────────────────┐    │
                  │   │  telecom-exporter │ ◄────  │    Prometheus     │    │
                  │   │     (:9100)       │        │      (:9090)      │    │
                  │   └─────────┬─────────┘        └─────────┬─────────┘    │
                  │             │                            │              │
                  │             ▼                            ▼              │
                  │      (Host & Pod State)        ┌───────────────────┐    │
                  │                                │      Grafana      │    │
                  │                                │      (:3000)      │    │
                  │                                └─────────┬─────────┘    │
                  │                                          │              │
                  └──────────────────────────────────────────┼──────────────┘
                                                             │ (NodePort 30300)
                                                             ▼
                                                ┌───────────────────────────┐
                                                │ Telecom Operations Center │
                                                │ http://172.19.0.2:30300   │
                                                └───────────────────────────┘
```

---

## 2. Deployment Topology

All observability components reside in the `monitoring` namespace:

| Component | Kind | Namespace | Port / Target | Image | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`grafana`** | Deployment + Service | `monitoring` | `3000/TCP` (`NodePort: 30300`) | `grafana/grafana:10.4.0` | Visualization UI & operational alerting engine |
| **`prometheus`** | Deployment + Service | `monitoring` | `9090/TCP` (`NodePort: 30090`) | `prom/prometheus:v2.45.0` | Time series scraping and storage engine |
| **`telecom-exporter`** | Deployment + Service | `monitoring` | `9100/TCP` | `ims-node:latest` | Continuous 7-domain OpenMetrics exporter |

### Accessing the Dashboard:
- **URL:** `http://172.19.0.2:30300` or `http://localhost:30300`
- **Authentication:** Anonymous Admin access enabled (`GF_AUTH_ANONYMOUS_ENABLED=true`, role `Admin`). Standard credentials: `admin` / `admin`.
- **Default Home Dashboard:** `5G-IMS-Lab — Telecom Operations Overview` (UID: `5g-ims-telecom-overview`).

---

## 3. Provisioned Datasource & Dashboards

Configuration is 100% declarative and restart-safe via Kubernetes ConfigMaps:

### A. Datasource Provisioning ([`k8s/monitoring/grafana.yaml`](file:///home/abdulrhamn/5G-IMS-Lab/k8s/monitoring/grafana.yaml))
- **Name:** `Prometheus`
- **URL:** `http://prometheus.monitoring.svc.cluster.local:9090`
- **Scrape / Refresh Interval:** `5s`
- **Access Mode:** `proxy`

### B. Dashboard Provisioning ([`k8s/monitoring/grafana-dashboard-configmap.yaml`](file:///home/abdulrhamn/5G-IMS-Lab/k8s/monitoring/grafana-dashboard-configmap.yaml))
- **Folder:** `5G Core & IMS`
- **UID:** `5g-ims-telecom-overview`
- **Title:** `5G-IMS-Lab — Telecom Operations Overview`
- **Auto-Refresh:** `5s`

---

## 4. Dashboard Structure & Panel Queries

The dashboard is structured into 8 operational sections (Rows):

### Section A: Executive Service Health
High-level KPIs for NOC overview:
1. **5G Registered UEs:** `sum(open5gs_5gc_registered_ues)` (Target: 3)
2. **Active PDU Sessions:** `sum(open5gs_5gc_active_pdu_sessions)` (Target: 6)
3. **IMS Registered Subscribers:** `ims_sip_registered_subscribers{component="scscf"}` (Target: 3)
4. **Call Setup Success (CSSR):** `avg(qoe_telecom_cssr_percent)` (Target: $\ge 99.0\%$)
5. **Voice Quality (Estimated MOS):** `avg(qoe_telecom_mos_estimated)` (Target: $\ge 4.0$)
6. **RTP Packet Loss Ratio:** `max(qoe_telecom_packet_loss_ratio)` (Target: $0.0\%$)
7. **Roaming UE3 Status:** `roaming_ue_attached_status{ue_id="ue3"}` (ATTACHED / DETACHED)
8. **Inter-PLMN Roaming Calls:** `roaming_inter_plmn_calls_total`

### Section B: Kubernetes & Infrastructure Health
1. **Open5GS 5GC Pods Ready:** `sum(k8s_infra_pod_ready{namespace="open5gs"})` / 12
2. **Kamailio IMS Pods Ready:** `sum(k8s_infra_pod_ready{namespace="ims"})` / 4
3. **Observability Targets Health:** `up{job="telecom-exporter"}`, `up{job="prometheus"}`
4. **Pod Readiness Matrix:** Table listing all pod statuses and restart counts across namespaces.

### Section C: 5G Core Control & User Plane
1. **Registered UEs by PLMN & Role:** `open5gs_5gc_registered_ues` (602/03 Home, 602/04 Home, 218/90 Visited)
2. **Active Dual PDU Sessions:** `open5gs_5gc_active_pdu_sessions` (Internet & IMS sessions per UE)
3. **N2 NGAP & N4 PFCP Interface Associations:** `open5gs_5gc_ngap_n2_associations`, `open5gs_5gc_pfcp_n4_status`

### Section D: IMS / Vo5G Signaling
1. **Kamailio SIP Server Functions:** `ims_sip_server_status` (P-CSCF, I-CSCF, S-CSCF)
2. **Subscriber SIP Digest Registrations:** `ims_sip_subscriber_reg_status` (`ue1`, `ue2`, `ue3`)
3. **SIP Signaling Traffic by Method:** Time series of `ims_sip_requests_total` (REGISTER, INVITE, ACK, BYE)

### Section E: RTP Media & Proxy Quality
1. **RTPEngine Control Socket:** `ims_rtp_proxy_status`
2. **Relayed RTP Voice Audio Packets:** `ims_rtp_packets_relayed_total`
3. **Relayed RTP Voice Audio Bandwidth:** `ims_rtp_bytes_relayed_total` (Bytes)

### Section F: Service Assurance & Voice Quality (QoE)
1. **Post-Dial Delay (PDD):** `qoe_telecom_pdd_seconds * 1000` (ms) [Target: $< 200\text{ ms}$]
2. **Call Setup Time (CST):** `qoe_telecom_cst_seconds * 1000` (ms) [Target: $< 500\text{ ms}$]
3. **RFC 3550 RTP Jitter:** `qoe_telecom_jitter_ms` (ms) [Target: $< 20\text{ ms}$]
4. **ITU-T G.107 Transmission Rating:** `qoe_telecom_r_factor` [0–100 scale]

### Section G: Offline Charging & Usage Accounting
1. **Recorded Voice Call CDRs:** Time series of `charging_cdr_records_total` by call type (Domestic / Roaming)
2. **Cumulative Billed Duration:** `charging_call_duration_seconds_total` (Seconds)
3. **User-Plane Data Accounting:** `charging_usage_uplink_bytes_total`, `charging_usage_downlink_bytes_total`

### Section H: Multi-PLMN Roaming Telemetry
1. **UE3 Roaming Attachment State:** `roaming_ue_attached_status` (HPLMN: 602/03 $\rightarrow$ VPLMN: 218/90)
2. **Local Breakout (LBO) VUPF Data Path:** `roaming_lbo_user_plane_status`
3. **Inter-PLMN Roaming Calls Attempted:** `roaming_inter_plmn_calls_total`
4. **Inter-PLMN Call Success Rate:** `roaming_inter_plmn_success_rate` (%)

---

## 5. Dashboard Variables & Filters

Low-cardinality template variables allow filtering panels by:
- **`$plmn`:** `All`, `602_03`, `602_04`, `218_90`
- **`$ue_id`:** `All`, `ue1`, `ue2`, `ue3`
- **`$role`:** `All`, `home`, `visited`
- **`$call_type`:** `All`, `domestic`, `roaming`
- **`$dnn`:** `All`, `internet`, `ims`

---

## 6. Automated Validation & Test Suite

Run the dedicated Grafana test suite:
```bash
./scripts/verify-grafana.sh
```

**Verification Output:**
```text
═══════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Phase 5.3 Grafana Operations Dashboard Verification Suite
═══════════════════════════════════════════════════════════════════════

1. Grafana Deployment & Infrastructure Readiness
  [✓] [GRAFANA-01] Monitoring Namespace: active in Kubernetes cluster
  [✓] [GRAFANA-02] Grafana Pod Status: Phase is Running
  [✓] [GRAFANA-03] Grafana Readiness: 1/1 replicas Ready
  [✓] [GRAFANA-04] Grafana Service: NodePort 30300 exposed
  [✓] [GRAFANA-05] Grafana HTTP Endpoint: HTTP API healthy (version: 10.4.0)
  [✓] [GRAFANA-06] Prometheus Pod Health: Running & Ready (1/1 replicas)

2. Prometheus Datasource Provisioning
  [✓] [GRAFANA-07] Prometheus Datasource: Provisioned automatically (Prometheus -> http://prometheus.monitoring.svc.cluster.local:9090)
  [✓] [GRAFANA-08] Datasource Proxy Connectivity: Grafana proxy successfully queries Prometheus (3 series returned)

3. Dashboard Provisioning & Structure
  [✓] [GRAFANA-09] Telecom Operations Dashboard: Dashboard provisioned with title '5G-IMS-Lab — Telecom Operations Overview'
  [✓] [GRAFANA-10] Dashboard Panels & Rows: 40 visual panels and category rows configured across Sections A-H

4. Telemetry Metrics Availability via Grafana Proxy
  [✓] [GRAFANA-11] Core Metrics Query: 5G Core registered UEs queryable via Grafana
  [✓] [GRAFANA-12] Domestic Call Telemetry: Domestic voice CDRs visible in Grafana (40 CDRs)
  [✓] [GRAFANA-13] Roaming Call Telemetry: Roaming voice CDRs visible in Grafana (40 CDRs)
  [✓] [GRAFANA-14] Charging Counters: Cumulative billed durations visible in Grafana
  [✓] [GRAFANA-15] RTP Media Telemetry: RTP audio packets relayed visible in Grafana (10050 pkts)
  [✓] [GRAFANA-16] QoE Service Assurance: Estimated MOS visible in Grafana (4.4 / 4.50)
  [✓] [GRAFANA-17] Roaming Telemetry: UE3 roaming attachment state visible in Grafana (ATTACHED)

5. Grafana Restart & Persistence Validation
  [✓] [GRAFANA-18] Restart-Recovery Verification: Grafana restarted successfully with datasource & dashboard intact

═══════════════════════════════════════════════════════════════════════
  Grafana Verification Summary: 18 Passed, 0 Failed
═══════════════════════════════════════════════════════════════════════
  >>> All Phase 5.3 Grafana Operations Dashboard Tests Passed! <<<
```

---

## 7. Full Regression Suite Results
- **Grafana Suite:** `./scripts/verify-grafana.sh` $\rightarrow$ **18 Passed, 0 Failed**
- **Observability Suite:** `./scripts/verify-observability.sh` $\rightarrow$ **19 Passed, 0 Failed**
- **Full Lab Regression:** `sudo ./scripts/verify-lab.sh` $\rightarrow$ **91 Passed, 0 Failed, 0 Warnings**
