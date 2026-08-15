# 5G-IMS-Lab — Project Roadmap

Living document tracking the milestones and technical roadmap for the 5G Standalone, IMS, Observability, and Revenue Engineering testbed.

---

## 🟢 Milestone 1: 5G SA Core Foundation `COMPLETED`
- [x] Open5GS 5G Core control plane deployment (AMF, SMF, AUSF, UDM, UDR, PCF, NRF, BSF)
- [x] UERANSIM gNodeB + UE simulation
- [x] 5G-AKA authentication & NAS security context establishment
- [x] IPv4 PDU session establishment (`internet` DNN, SST:1, SD:0xFFFFFF)
- [x] GTP-U user plane tunneling over kernel TUN (`ogstun`)
- [x] Data plane internet routing and HTTPS egress validation

---

## 🟢 Milestone 2: Cloud-Native & Multi-UE Infrastructure `COMPLETED`
- [x] Kubernetes (`kind`) container orchestration for 5G Core network functions
- [x] Multi-UE simulation with independent PLMNs/IMSIs (`602030000000001` [602/03] and `602040000000002` [602/04])
- [x] Linux network namespace isolation for parallel UE data planes
- [x] Concurrent dual PDU sessions per UE (`internet` + `ims` bearers)
- [x] Dynamic IPv4 address pool management (`10.45.0.0/16` and `10.46.0.0/16`)
- [x] Host kernel networking automation (IP forwarding, NAT MASQUERADE, rp_filter tuning)

---

## 🟢 Milestone 3: IMS Service Layer & Media Proxy `COMPLETED`
- [x] Kamailio P-CSCF deployment with `hostNetwork` ingress (`10.46.0.1:5060`)
- [x] Kamailio I-CSCF routing and domain resolution (`ims.lab`)
- [x] Kamailio S-CSCF registrar with SQLite subscriber credentials and Digest MD5 auth
- [x] RFC 3327 `Path` header support for NAT traversal to UE endpoints
- [x] RTPEngine media proxy deployment with NG control protocol (`22222/UDP`)
- [x] Automated SDP offer/answer rewriting to RTPEngine relay endpoints (`20000-20100/UDP`)
- [x] End-to-end SIP call flow (`INVITE` -> `180 Ringing` -> `200 OK` -> `ACK` -> `BYE`)
- [x] Bidirectional RTP voice stream exchange (G.711 PCMU, 0% packet loss)

---

## 🟢 Milestone 4: Multi-PLMN Roaming, QoS & Telemetry Foundation `COMPLETED`
- [x] Independent Isolated RAN Topology (gNodeB-Home on `127.0.0.1:38412` & gNodeB-Visited on `127.0.0.1:38413`)
- [x] Inter-PLMN Local Breakout (LBO) Roaming (UE3 HPLMN `602/03` $\rightarrow$ VPLMN `218/90` Bosnia)
- [x] Linux `tc prio` DSCP-to-QoS User-Plane Queueing (EF/CS5 high-priority voice queues)
- [x] PCF & BSF Static Policy Control per 5QI/QFI
- [x] SQLite CDR Database Accounting in Kamailio S-CSCF (`cdrs` and `acc` tables)
- [x] Real-Time ITU-T G.107 E-model Service Assurance KPI Engine (`scripts/measure-kpis.sh`)
- [x] Consolidated 91-test regression test suite (`scripts/verify-lab.sh`)

---

## 🟢 Milestone 5: Full-Stack Observability, Alerting & Rating Management `COMPLETED`
- [x] **Phase 5.1 & 5.2**: Custom Python `telecom-exporter` (`:9100`) & Prometheus (`:30090`) scraping across 7 telemetry categories (`scripts/verify-observability.sh` — 19/19 PASS)
- [x] **Phase 5.3**: Production 53-panel Grafana Operations Dashboard (`:30300`) across Sections A–J (`scripts/verify-grafana.sh` — 18/18 PASS)
- [x] **Phase 5.4**: Alertmanager (`:30093`) with 26 declarative alert rules and automated fault injection recovery (`scripts/verify-alerting.sh` — 19/19 PASS)
- [x] **Phase 5.5**: Telecom Rating Engine & Prepaid Balance Management (`src/charging/` & `scripts/rating-engine.py`) with ACID SQLite ledger, voice/data tariffs, reconciliation, and 22 automated tests (`scripts/verify-rating.sh` — 22/22 PASS)
- [x] **Consolidated Regression Baseline**: 169 / 169 Tests Passing (100% Green)

---

## 📋 Future Enhancements (Phase 5.6+)

- [ ] **Phase 5.6**: Automated Self-Healing & Closed-Loop Remediation Operator
- [ ] **Phase 5.7**: Automated CI/CD Testing Pipeline (GitHub Actions syntax, linting & regression runner)
- [ ] **Phase 6.0**: Cloud-Native 5G Core Upgrade (Open5GS v2.9+ / 3GPP Rel-17 features)
- [ ] Diameter / Rx interface integration between P-CSCF and PCF for dynamic QoS policy
- [ ] TLS / SRTP signaling and media encryption validation
