# 5G-IMS-Lab — Telemetry Inventory & Metrics Source Map

## 1. Overview & Source-of-Truth Inventory

This document maps every metric defined in [`metrics-model.md`](metrics-model.md) to its physical underlying source of truth, extraction mechanism, expected nominal values, and deterministic validation command.

---

## 2. Telemetry Source Inventory Table

| Component | Telemetry Element | Direct Source | Extraction Mechanism | Reusable in Exporter? | Notes / Gap |
|---|---|---|---|---|---|
| **Kubernetes Pods** | Pod Phase & Container Readiness | Kubernetes API (`/api/v1/pods`) | `kubectl get pods -n open5gs -o json` | **YES** | Standard `kube-state-metrics` or lab exporter |
| **5GC AMF (Home & Visited)** | SCTP N2 NGAP Association & Sockets | Linux host sockets (`:38412`, `:38413`) | `ss -tulpn \| grep -E '38412\|38413'` | **YES** | Directly verifiable from host |
| **5GC SMF & UPF** | PFCP N4 Association | UPF socket (`udp :8805`) | `nc -zuv -w 1 172.19.0.2 8805` | **YES** | Verified via UDP port check |
| **5GC UPF** | Aggregate N3 GTP-U Traffic | Linux network interface `ogstun` | `ip -s link show ogstun` | **YES** | Kernel netlink byte/packet counters |
| **UERANSIM UEs** | Dual-PDU Network Namespaces | Linux NetNS (`ueransim-*-psi1/2`) | `ip netns list`, `ip -4 addr show` | **YES** | Real IP allocation & NetNS presence |
| **UERANSIM UEs** | Per-UE UL/DL Data Volume | NetNS TUN interface `uesimtun0` | `ip netns exec <ns> ip -s link show uesimtun0` | **YES** | Direct kernel byte/packet counters |
| **Kamailio P-CSCF** | SIP Proxy Listener & Health | SIP UDP socket `10.46.0.1:5060` | Python UDP SIP `OPTIONS` ping | **YES** | Validates P-CSCF transaction engine |
| **Kamailio S-CSCF** | Active Subscriber Registrations | Kamailio USRLOC Memory Dump | `kamcmd ul.dump` in `kamailio-scscf` | **YES** | Real-time active AoR registrations |
| **Kamailio S-CSCF** | Active SIP Dialogs | Kamailio Dialog Module Memory Dump | `kamcmd dlg.list` in `kamailio-scscf` | **YES** | Real-time concurrent call dialogs |
| **Kamailio S-CSCF** | Offline CDR Accounting Records | SQLite DB `/etc/kamailio/db/kamailio.sqlite` | `SELECT * FROM cdrs` | **YES** | Durable call duration, caller, callee |
| **RTPEngine** | Media Proxy Health & Relayed Traffic | RTPEngine Bencode NG Protocol (`:22222`) | `command: ping`, `command: statistics` | **YES** | Real-time relayed packets, bytes, sessions |
| **KPI Engine** | Signaling & Voice QoE Telemetry | `scripts/measure-kpis.sh` JSON mode | `sudo bash scripts/measure-kpis.sh --json` | **YES** | PDD, CST, CSSR, Jitter, MOS |

---

## 3. Detailed Metric-to-Source Mapping

### 3.1 Infrastructure Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `k8s_infra_pod_ready` | Kubernetes Pods (`open5gs`, `ims`) | `kubectl -n <ns> get pods -l app=<app> -o jsonpath='{.items[0].status.containerStatuses[0].ready}'` | `1` (true) |
| `k8s_infra_container_restarts_total` | Kubernetes Pods (`open5gs`, `ims`) | `kubectl -n <ns> get pods -l app=<app> -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}'` | `0` (stable) |

### 3.2 5G Core Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `open5gs_5gc_nf_status{nf_name="amf"}` | Home AMF Deployment | `kubectl -n open5gs get deploy/open5gs-amf -o jsonpath='{.status.readyReplicas}'` | `1` |
| `open5gs_5gc_ngap_n2_associations{role="home"}` | `gNodeB-Home` N2 SCTP | `grep -ci "NG Setup procedure is successful" /tmp/ueransim-gnb-home.log` | `1` |
| `open5gs_5gc_ngap_n2_associations{role="visited"}` | `gNodeB-Visited` N2 SCTP | `grep -ci "NG Setup procedure is successful" /tmp/ueransim-gnb-visited.log` | `1` |
| `open5gs_5gc_registered_ues` | UERANSIM UE processes | `pgrep -c nr-ue` | `3` |
| `open5gs_5gc_active_pdu_sessions` | Host Network Namespaces | `ip netns list \| grep -c 'ueransim-'` | `6` (3 UEs $\times$ 2 PDUs) |

### 3.3 IMS & SIP Signaling Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `ims_sip_server_status{component="scscf"}` | S-CSCF Pod | `kubectl -n ims get deploy/kamailio-scscf -o jsonpath='{.status.readyReplicas}'` | `1` |
| `ims_sip_registered_subscribers` | S-CSCF USRLOC Module | `kubectl -n ims exec deploy/kamailio-scscf -c scscf -- kamcmd ul.dump \| grep -c "Address: sip:"` | `3` (`ue1`, `ue2`, `ue3`) |
| `ims_sip_active_dialogs` | S-CSCF Dialog Module | `kubectl -n ims exec deploy/kamailio-scscf -c scscf -- kamcmd dlg.list` | `0` (idle) / `1`+ (during call) |

### 3.4 RTP Media Proxy Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `ims_rtp_proxy_status` | RTPEngine NG Protocol | Bencode `1234_1 d7:command4:pinge` to `172.19.0.2:22222` | `1` (`d6:result4:ponge`) |
| `ims_rtp_packets_relayed_total` | RTPEngine Statistics | Bencode `1234_2 d7:command10:statisticse` $\rightarrow$ `relayedpackets` | $>0$ (increasing with calls) |
| `ims_rtp_packet_errors_total` | RTPEngine Statistics | Bencode `1234_2 d7:command10:statisticse` $\rightarrow$ `relayedpacketerrors` | `0` |

### 3.5 Charging & Accounting Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `charging_cdr_records_total` | S-CSCF SQLite DB | `kubectl -n ims exec deploy/kamailio-scscf -c scscf -- sqlite3 /etc/kamailio/db/kamailio.sqlite "SELECT COUNT(*) FROM cdrs;"` | $\ge 2$ |
| `charging_usage_uplink_bytes_total{ue_id="ue1",dnn="internet"}` | Linux NetNS `ueransim-602030000000001-internet-psi1` | `ip netns exec ueransim-602030000000001-internet-psi1 ip -s link show uesimtun0 \| awk '/TX:/{getline; print $1}'` | $>0$ bytes |

### 3.6 Service Assurance & QoE Metrics
| Metric | Source Component | Query / Extraction Command | Expected Baseline Value |
|---|---|---|---|
| `qoe_telecom_pdd_seconds{call_type="domestic"}` | KPI Measurement Engine | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.signaling.pdd_ms / 1000'` | $<0.200$ s ($<200$ ms) |
| `qoe_telecom_cst_seconds{call_type="domestic"}` | KPI Measurement Engine | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.signaling.cst_ms / 1000'` | $<0.500$ s ($<500$ ms) |
| `qoe_telecom_cssr_percent{call_type="domestic"}`| KPI Measurement Engine | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.signaling.cssr_pct'` | `100.0`% |
| `qoe_telecom_packet_loss_ratio{call_type="domestic"}`| KPI Measurement Engine | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.media.packet_loss_pct / 100'` | `0.0` |
| `qoe_telecom_jitter_ms{call_type="domestic"}` | KPI Measurement Engine | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.media.rfc3550_jitter_ms'` | $<20.0$ ms |
| `qoe_telecom_mos_estimated{call_type="domestic"}` | ITU-T G.107 E-Model | `sudo bash scripts/measure-kpis.sh --json \| jq '.results.domestic.media.estimated_mos'` | $>4.30$ (G.711 max ~4.41) |

---

## 4. Phase 5.2 Exporter Integration Strategy

In **Phase 5.2**, a lightweight, containerized **Lab Telecom Metrics Exporter** will be introduced into the Kubernetes cluster. It will scrape these exact verified data sources via a standard `/metrics` endpoint:

1. **Kubernetes In-Cluster API Scraper**: Queries pod and node statuses.
2. **Kamailio Unix/JSON-RPC Scraper**: Polls `ul.dump` and `dlg.list`.
3. **SQLite CDR Poller**: Queries `/etc/kamailio/db/kamailio.sqlite`.
4. **RTPEngine NG Protocol Scraper**: Parses bencode statistics dict.
5. **Host Telemetry Agent**: Queries NetNS `uesimtun0` counters and `measure-kpis.sh` outputs.
