# 5G-IMS-Lab — Telecom Metrics Model Specification

## 1. Metric Naming Convention & Taxonomy

The **5G-IMS-Lab Metrics Model** strictly adheres to OpenMetrics and Prometheus time-series design standards. Every metric identifier follows the structured taxonomy:

$$\text{<namespace>}\_\text{<subsystem>}\_\text{<name>}\_\text{<unit\_or\_type>}$$

### 1.1 Prefix Taxonomy
| Domain / Namespace | Subsystem Identifier | Focus Area |
|---|---|---|
| `k8s_infra_*` | `pod`, `node`, `cluster` | Kubernetes infrastructure, container readiness, restarts |
| `open5gs_5gc_*` | `nf`, `amf`, `smf`, `upf`, `session` | 5G Core control plane, N2/N4 status, PDU sessions |
| `ims_sip_*` | `reg`, `invite`, `dialog`, `server` | Kamailio P/I/S-CSCF signaling, registrations, SIP status |
| `ims_rtp_*` | `engine`, `stream`, `quality` | RTPEngine media proxy, packet counts, bytes, sessions |
| `charging_*` | `cdr`, `usage`, `rating` | SQLite CDRs, call duration, per-UE dual-PDU volume |
| `qoe_telecom_*` | `signaling`, `media`, `voice` | Real-time Service Assurance KPIs (PDD, CST, CSSR, MOS) |
| `roaming_*` | `lbo`, `inter_plmn` | Visited network registration, cross-PLMN call routing |

### 1.2 Unit & Type Suffix Rules
- `_total`: Monotonically increasing counter (e.g. `ims_sip_requests_total`).
- `_seconds`: Time intervals and latencies in seconds (e.g. `qoe_telecom_pdd_seconds`).
- `_bytes`: Data volumes in bytes (e.g. `charging_usage_uplink_bytes`).
- `_packets`: Packet volumes (e.g. `ims_rtp_packets_relayed_total`).
- `_ratio`: Normalized fraction between $0.0$ and $1.0$ (e.g. `qoe_telecom_packet_loss_ratio`).
- `_percent`: Percentages between $0.0$ and $100.0$ (e.g. `qoe_telecom_cssr_percent`).
- `_status` / `_info`: Instantaneous boolean or enumeration gauge (e.g. `open5gs_5gc_nf_status`).

---

## 2. Standardized Label Model & Cardinality Policy

| Label | Description | Allowed Cardinality / Example Values |
|---|---|---|
| `nf_name` | Name of 5G Core Network Function | `amf`, `v_amf`, `smf`, `v_smf`, `upf`, `pcf`, `bsf`, `udr`, `udm`, `ausf`, `nrf` |
| `component` | Subsystem component | `pcscf`, `icscf`, `scscf`, `rtpengine`, `gnb_home`, `gnb_visited` |
| `ue_id` | Normalized UE identifier | `ue1`, `ue2`, `ue3` |
| `plmn` | Serving PLMN identifier | `602_03`, `602_04`, `218_90` |
| `role` | PLMN network domain role | `home`, `visited` |
| `call_type` | Voice call category | `domestic`, `roaming` |
| `dnn` | 5G Data Network Name | `internet`, `ims` |
| `direction` | Media/Traffic flow direction | `uplink`, `downlink`, `caller_to_callee`, `callee_to_caller` |
| `sip_method` | SIP transaction method | `REGISTER`, `INVITE`, `ACK`, `BYE`, `OPTIONS` |
| `sip_code` | SIP response class or code | `180`, `200`, `401`, `407`, `486`, `500` |

---

## 3. Comprehensive Metric Dictionary

### Category A: Infrastructure & Pod Health (`k8s_infra_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `k8s_infra_pod_ready` | Gauge | Boolean indicator (1=Ready, 0=Not Ready) of pod readiness | Gauge | `namespace`, `pod_name`, `app` |
| `k8s_infra_pod_status` | Gauge | Pod lifecycle phase (1=Running, 0=Other) | Gauge | `namespace`, `pod_name`, `app` |
| `k8s_infra_container_restarts_total` | Counter | Total restart count for container | Counter | `namespace`, `pod_name`, `container` |

### Category B: 5G Core Control & User Plane (`open5gs_5gc_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `open5gs_5gc_nf_status` | Gauge | NF operational status (1=Running/Ready, 0=Down) | Gauge | `nf_name`, `role` |
| `open5gs_5gc_registered_ues` | Gauge | Number of registered UEs currently attached | Integer | `plmn`, `role` |
| `open5gs_5gc_active_pdu_sessions` | Gauge | Total active PDU sessions established | Integer | `ue_id`, `dnn`, `role` |
| `open5gs_5gc_ngap_n2_associations` | Gauge | N2 SCTP association status (1=Connected, 0=Down) | Gauge | `gnb_instance`, `target_amf`, `plmn` |
| `open5gs_5gc_pfcp_n4_status` | Gauge | SMF-to-UPF PFCP N4 association status | Gauge | `smf_instance`, `endpoint` |
| `open5gs_5gc_gtpu_n3_bytes_total` | Counter | Aggregate GTP-U user-plane bytes transferred on N3 | Bytes | `direction`, `interface` |

### Category C: IMS / Vo5G Signaling (`ims_sip_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `ims_sip_server_status` | Gauge | Operational status of IMS SIP server component | Gauge | `component` (`pcscf`, `icscf`, `scscf`) |
| `ims_sip_registered_subscribers` | Gauge | Instantaneous count of active AoR SIP registrations | Integer | `domain`, `component` |
| `ims_sip_subscriber_reg_status` | Gauge | Individual UE registration state (1=Registered, 0=Unregistered) | Gauge | `ue_id`, `domain` |
| `ims_sip_requests_total` | Counter | Total count of processed SIP requests | Counter | `sip_method`, `component` |
| `ims_sip_responses_total` | Counter | Total count of generated SIP responses | Counter | `sip_code`, `component` |
| `ims_sip_active_dialogs` | Gauge | Currently active, established SIP dialogs | Integer | `component` |
| `ims_sip_dialog_duration_seconds` | Gauge | Duration of active or recently completed call dialog | Seconds | `call_type`, `ue_id` |

### Category D: RTP Media & Proxy Quality (`ims_rtp_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `ims_rtp_proxy_status` | Gauge | RTPEngine control socket status (1=Operational, 0=Down) | Gauge | `endpoint` |
| `ims_rtp_managed_sessions_total` | Counter | Total media sessions managed by RTPEngine since start | Counter | `proxy` |
| `ims_rtp_active_sessions` | Gauge | Instantaneous active media streams passing through proxy | Integer | `proxy` |
| `ims_rtp_packets_relayed_total` | Counter | Total RTP audio packets relayed through RTPEngine | Packets | `proxy` |
| `ims_rtp_bytes_relayed_total` | Counter | Total RTP audio payload bytes relayed | Bytes | `proxy` |
| `ims_rtp_packet_errors_total` | Counter | Media packet relay errors encountered | Errors | `proxy` |

### Category E: Offline Charging & Usage Accounting (`charging_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `charging_cdr_records_total` | Counter | Total Call Detail Records recorded in SQLite DB | Records | `call_type`, `sip_code` |
| `charging_call_duration_seconds_total` | Counter | Cumulative voice call duration recorded across all CDRs | Seconds | `call_type` |
| `charging_last_call_duration_seconds` | Gauge | Duration of most recently closed call | Seconds | `call_type`, `caller`, `callee` |
| `charging_usage_uplink_bytes_total` | Counter | Cumulative user-plane uplink data per UE and DNN | Bytes | `ue_id`, `dnn`, `plmn` |
| `charging_usage_downlink_bytes_total` | Counter | Cumulative user-plane downlink data per UE and DNN | Bytes | `ue_id`, `dnn`, `plmn` |
| `charging_usage_uplink_packets_total` | Counter | Cumulative user-plane uplink packets per UE and DNN | Packets | `ue_id`, `dnn`, `plmn` |
| `charging_usage_downlink_packets_total`| Counter | Cumulative user-plane downlink packets per UE and DNN | Packets | `ue_id`, `dnn`, `plmn` |

### Category F: Service Assurance & Voice Quality of Experience (`qoe_telecom_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `qoe_telecom_pdd_seconds` | Gauge | Measured Post-Dial Delay (INVITE to 180 Ringing) | Seconds | `call_type` |
| `qoe_telecom_cst_seconds` | Gauge | Measured Call Setup Time (INVITE to 200 OK) | Seconds | `call_type` |
| `qoe_telecom_cssr_percent` | Gauge | Call Setup Success Rate | Percent | `call_type` |
| `qoe_telecom_packet_loss_ratio` | Gauge | Measured real-time RTP packet loss fraction | Ratio (0.0-1.0)| `call_type`, `direction` |
| `qoe_telecom_jitter_ms` | Gauge | RFC 3550 inter-arrival jitter in milliseconds | Milliseconds | `call_type`, `direction` |
| `qoe_telecom_r_factor` | Gauge | ITU-T G.107 E-model transmission rating factor (0-100) | Scalar | `call_type` |
| `qoe_telecom_mos_estimated` | Gauge | Estimated Mean Opinion Score (1.00 - 4.40+) | MOS (1.0-5.0)| `call_type` |

### Category G: Multi-PLMN & Roaming Specific Telemetry (`roaming_*`)
| Metric Name | Type | Description | Unit | Labels |
|---|---|---|---|---|
| `roaming_ue_attached_status` | Gauge | UE3 roaming attachment state in Visited PLMN (1=Attached, 0=Down)| Gauge | `ue_id`, `hplmn`, `vplmn` |
| `roaming_lbo_user_plane_status`| Gauge | Local Breakout user-plane path through VUPF active (1=Active, 0=Down)| Gauge | `vplmn`, `vupf_ip` |
| `roaming_inter_plmn_calls_total`| Counter | Total attempted inter-PLMN roaming calls | Counter | `origin_plmn`, `target_plmn` |
| `roaming_inter_plmn_success_rate`| Gauge | Success rate for inter-PLMN roaming voice sessions | Percent | `origin_plmn`, `target_plmn` |

---

## 4. Metric Summary Statistics
- **Total Metrics Defined:** 32 metrics.
- **Directly Available from Current Lab Telemetry:** 28 metrics.
- **Derived / Exporter Targets for Phase 5.2:** 4 metrics (formalized OpenMetrics scraping endpoints).
