# Prometheus Alerting & Incident Detection (Phase 5.4)

This document details the architecture, alert rules, severity model, incident lifecycle, and automated fault-injection validation for **Phase 5.4** of the **5G-IMS-Lab** project.

---

## 1. Architecture & Alerting Pipeline

Phase 5.4 introduces production-style alerting and incident detection on top of the Prometheus scraping pipeline and Grafana operations dashboard:

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                Kubernetes Cluster (kind)                │
                  │                                                         │
                  │   ┌───────────────────┐                                 │
                  │   │  telecom-exporter │ (:9100)                         │
                  │   └─────────┬─────────┘                                 │
                  │             │ (Scrape every 5s)                         │
                  │             ▼                                           │
                  │   ┌───────────────────┐                                 │
                  │   │    Prometheus     │ (:9090 / NodePort 30090)        │
                  │   │   (Rule Engine)   │                                 │
                  │   └─────────┬─────────┘                                 │
                  │             │ (Alert dispatch when condition true)      │
                  │             ▼                                           │
                  │   ┌───────────────────┐                                 │
                  │   │   Alertmanager    │ (:9093 / NodePort 30093)        │
                  │   │ (Routing/Grouping)│                                 │
                  │   └─────────┬─────────┘                                 │
                  │             │                                           │
                  │             ▼                                           │
                  │   ┌───────────────────┐                                 │
                  │   │      Grafana      │ (:3000 / NodePort 30300)        │
                  │   │ (Incident Center) │                                 │
                  │   └───────────────────┘                                 │
                  └─────────────────────────────────────────────────────────┘
```

---

## 2. Severity Model & Label Taxonomy

All alert definitions conform to standardized labels and annotations:

### Severity Levels:
- **`critical`**: Outage or severe degradation impacting core connectivity, radio signaling, user-plane data path, or voice registration. Immediate operational response required.
- **`warning`**: Degradation of service quality (MOS $< 4.0$, PDD $> 200\text{ ms}$, jitter $> 20\text{ ms}$) or non-critical subscriber registration drops.

### Metadata Schema:
- **`layer`**: `infra`, `5gc-control-plane`, `5gc-user-plane`, `ran-5gc-n2`, `ims-signaling`, `rtp-media`, `qoe-assurance`, `roaming-vplmn`, `roaming-inter-plmn`, `observability`.
- **`component`**: Specific network function or service (e.g. `amf`, `smf-upf`, `kamailio-cscf`, `rtpengine`, `kpi-engine`, `e-model`).
- **`annotations`**:
  - `summary`: Short human-readable summary of the incident.
  - `description`: Detailed technical explanation with dynamic template variables.
  - `runbook`: Triage command or script for the on-call engineer.

---

## 3. Declarative Alert Rules Registry

All 21 alert rules are declaratively managed in [`k8s/monitoring/prometheus-alert-rules.yaml`](file:///home/abdulrhamn/5G-IMS-Lab/k8s/monitoring/prometheus-alert-rules.yaml):

| Alert Name | Severity | Group / Layer | PromQL Condition | Operational Meaning |
| :--- | :--- | :--- | :--- | :--- |
| **`Open5gsCorePodsDegraded`** | `critical` | `telecom_infra_alerts` | `sum(k8s_infra_pod_ready{namespace="open5gs"}) < 12` | One or more 5G Core Network Functions are missing or NotReady |
| **`ImsCorePodsDegraded`** | `critical` | `telecom_infra_alerts` | `sum(k8s_infra_pod_ready{namespace="ims"}) < 4` | One or more Kamailio IMS or RTPEngine pods are down |
| **`K8sPodNotReady`** | `critical` | `telecom_infra_alerts` | `k8s_infra_pod_ready == 0` | Specific Kubernetes pod is in NotReady / CrashLoop state |
| **`TelecomExporterDown`** | `critical` | `telecom_infra_alerts` | `up{job="telecom-exporter"} == 0` | Telemetry exporter endpoint unreachable |
| **`PrometheusScrapeFailed`** | `critical` | `telecom_infra_alerts` | `up{job="prometheus"} == 0` | Prometheus self-monitoring target failed |
| **`Open5gsRegisteredUeDrop`**| `critical` | `telecom_5g_core_alerts` | `open5gs_5gc_registered_ues < 1` | Registered UEs dropped to 0 for a specific PLMN |
| **`Open5gsPduSessionInactive`**| `critical` | `telecom_5g_core_alerts` | `open5gs_5gc_active_pdu_sessions == 0` | Dual PDU session failed or terminated for a UE |
| **`Open5gsNgapN2Failure`** | `critical` | `telecom_5g_core_alerts` | `open5gs_5gc_ngap_n2_associations == 0` | gNodeB lost N2 SCTP association to AMF |
| **`Open5gsPfcpN4Failure`** | `critical` | `telecom_5g_core_alerts` | `open5gs_5gc_pfcp_n4_status == 0` | SMF lost N4 PFCP association to UPF |
| **`ImsSipServerDown`** | `critical` | `telecom_ims_sip_alerts` | `ims_sip_server_status == 0` | P/I/S-CSCF SIP probe failed (OPTIONS / socket timeout) |
| **`ImsSubscriberUnregistered`**| `warning` | `telecom_ims_sip_alerts` | `ims_sip_subscriber_reg_status == 0` | Specific UE AoR unregistered in S-CSCF USRLOC |
| **`ImsRegisteredSubscribersLow`**| `warning` | `telecom_ims_sip_alerts`| `ims_sip_registered_subscribers < 3` | Active IMS registrations below expected baseline of 3 |
| **`RtpEngineControlDown`** | `critical` | `telecom_rtp_media_alerts`| `ims_rtp_proxy_status == 0` | RTPEngine NG UDP control socket :22222 unreachable |
| **`QoEMosDegraded`** | `warning` | `telecom_service_assurance_alerts` | `qoe_telecom_mos_estimated < 4.0` | Voice Quality estimated MOS dropped below 4.0 |
| **`QoECssrLow`** | `critical` | `telecom_service_assurance_alerts` | `qoe_telecom_cssr_percent < 99.0` | Call Setup Success Rate dropped below 99% SLA |
| **`QoEPacketLossHigh`** | `critical` | `telecom_service_assurance_alerts` | `qoe_telecom_packet_loss_ratio > 0.01` | RTP packet loss ratio exceeded 1.0% |
| **`QoEPddHigh`** | `warning` | `telecom_service_assurance_alerts` | `qoe_telecom_pdd_seconds > 0.200` | Post-Dial Delay exceeded 200ms threshold |
| **`QoEJitterHigh`** | `warning` | `telecom_service_assurance_alerts` | `qoe_telecom_jitter_ms > 20.0` | RFC 3550 RTP jitter exceeded 20ms threshold |
| **`RoamingUeDetached`** | `critical` | `telecom_roaming_alerts` | `roaming_ue_attached_status == 0` | UE3 detached from Visited PLMN 218/90 |
| **`RoamingLboUserPlaneDown`**| `critical`| `telecom_roaming_alerts` | `roaming_lbo_user_plane_status == 0` | Local Breakout (LBO) VUPF data path unreachable |
| **`RoamingSuccessRateLow`** | `critical` | `telecom_roaming_alerts` | `roaming_inter_plmn_success_rate < 99.0` | Inter-PLMN roaming voice call completion rate $< 99\%$ |

---

## 4. Alertmanager Deployment & Routing

- **Manifest:** [`k8s/monitoring/alertmanager.yaml`](file:///home/abdulrhamn/5G-IMS-Lab/k8s/monitoring/alertmanager.yaml)
- **Image:** `prom/alertmanager:v0.25.0`
- **Service:** `NodePort: 30093` (`9093/TCP`)
- **Routing:** Grouping by `['alertname', 'component', 'layer']`, `group_wait: 5s`, `group_interval: 10s`, `repeat_interval: 1h`.
- **Local Receiver:** Zero external credentials required for local deterministic validation.

---

## 5. Fault Injection & Incident Lifecycle Validation

The alerting system is validated through real, automated fault-injection cycles:

1. **Steady State:** `curl http://172.19.0.2:30090/api/v1/alerts` $\rightarrow$ `0 active alerts`.
2. **Fault Injection:** Scale `deployment/open5gs-bsf` to `0` replicas.
3. **Detection & Firing:** Within 15 seconds, Prometheus evaluates `sum(k8s_infra_pod_ready{namespace="open5gs"}) < 12` and transitions `Open5gsCorePodsDegraded` to `FIRING`.
4. **Dispatch:** Prometheus dispatches the alert to Alertmanager, which records it as `ACTIVE`.
5. **Restoration:** Scale `deployment/open5gs-bsf` back to `1` replica.
6. **Automatic Resolution:** Prometheus detects pod readiness (12/12), automatically marks the alert `RESOLVED`, and returns to `0 active alerts`.

---

## 6. Automated Verification Suite

Execute the dedicated verification suite:
```bash
./scripts/verify-alerting.sh
```

**Verification Results (19/19 PASS):**
```text
═══════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Phase 5.4 Prometheus Alerting & Incident Detection Suite  
═══════════════════════════════════════════════════════════════════════

1. Alerting Infrastructure Readiness
  [✓] [ALERT-01] Monitoring Namespace: active in Kubernetes cluster
  [✓] [ALERT-02] Alertmanager Pod: Running & Ready (1/1 replicas)
  [✓] [ALERT-03] Alertmanager Service: NodePort 30093 exposed
  [✓] [ALERT-04] Alertmanager HTTP API: HTTP endpoint healthy (/-/ready returned OK)
  [✓] [ALERT-05] Prometheus Pod: Running & Ready (1/1 replicas)
  [✓] [ALERT-06] Prometheus Alertmanager Channel: Connected to active Alertmanager (http://alertmanager.monitoring.svc.cluster.local:9093/api/v2/alerts)

2. Declarative Alert Rules Provisioning across Domains
  [✓] [ALERT-07] Alert Rule Groups: 6 alert rule groups loaded in Prometheus
  [✓] [ALERT-08] Infra Alert Rules: Open5gsCorePodsDegraded, ImsCorePodsDegraded, TelecomExporterDown active
  [✓] [ALERT-09] 5G Core Alert Rules: Open5gsRegisteredUeDrop, Open5gsPduSessionInactive, Open5gsNgapN2Failure active
  [✓] [ALERT-10] IMS / SIP Alert Rules: ImsSipServerDown, ImsSubscriberUnregistered, ImsRegisteredSubscribersLow active
  [✓] [ALERT-11] RTP Media Alert Rules: RtpEngineControlDown active
  [✓] [ALERT-12] QoE Service Assurance Alert Rules: QoEMosDegraded, QoECssrLow, QoEPacketLossHigh active
  [✓] [ALERT-13] Roaming Alert Rules: RoamingUeDetached, RoamingLboUserPlaneDown, RoamingSuccessRateLow active

3. Fault Injection & Incident Lifecycle Validation
  [✓] [ALERT-14] Steady-State Baseline: 0 active firing alerts under normal operation
  [✓] [ALERT-15] Controlled Fault Firing: Open5gsCorePodsDegraded transitioned to FIRING in Prometheus
  [✓] [ALERT-16] Alertmanager Dispatch: Alert dispatched & registered as ACTIVE in Alertmanager
  [✓] [ALERT-17] Automatic Alert Resolution: Alert resolved after component restoration
  [✓] [ALERT-18] Post-Recovery Baseline: System returned cleanly to 0 firing alerts

4. Grafana Alerting Integration
  [✓] [ALERT-19] Grafana Alertmanager Integration: Alertmanager datasource provisioned & queryable in Grafana

═══════════════════════════════════════════════════════════════════════
  Alerting Verification Summary: 19 Passed, 0 Failed
═══════════════════════════════════════════════════════════════════════
  >>> All Phase 5.4 Prometheus Alerting & Incident Tests Passed! <<<
```
