# Open Telecom Lab — Roadmap

> Living document tracking the evolution of the project from a 5G SA lab to a full-scale cloud-native telecom platform.

---

## 🟢 v1.0 — 5G SA Foundation `RELEASED`

- [x] Open5GS 5G Core deployment (native Ubuntu)
- [x] UERANSIM gNodeB + UE integration
- [x] UE Registration & 5G-AKA Authentication
- [x] PDU Session Establishment (IPv4)
- [x] User Plane connectivity & internet access
- [x] MongoDB subscriber provisioning
- [x] tcpdump / Wireshark packet captures
- [x] Repository structure & documentation

## 🔄 v1.x — Protocol Deep-Dives `IN PROGRESS`

- [ ] NAS message walkthrough (Registration, Authentication, PDU Session)
- [ ] NGAP procedure analysis (Initial UE Message, Initial Context Setup)
- [ ] PFCP session walkthrough (Session Establishment, Modification)
- [ ] GTP-U tunnel analysis (encapsulation, decapsulation)
- [ ] Wireshark display filters & coloring rules for 5G protocols
- [ ] Annotated PCAP samples with step-by-step guides

## 📋 v2.x — IMS & Voice Services `PLANNED`

- [ ] IMS Core deployment (Kamailio / Open5GS IMS)
- [ ] SIP registration and call setup
- [ ] VoLTE / VoNR call flow
- [ ] RTP media stream analysis
- [ ] SIP/SDP message walkthrough
- [ ] Call flow sequence diagrams

## 📋 v3.x — LTE Comparison & Mobility `PLANNED`

- [ ] LTE EPC deployment (MME, SGW, PGW)
- [ ] EPC vs 5GC architecture comparison
- [ ] Inter-RAT mobility procedures
- [ ] Xn / N2 handover analysis
- [ ] Tracking Area Update procedures

## 📋 v4.x — Docker Deployment `PLANNED`

- [ ] Dockerfiles for Open5GS NFs
- [ ] Docker Compose orchestration
- [ ] Multi-container networking
- [ ] Persistent volume configuration
- [ ] Environment-based configuration

## 📋 v5.x — Kubernetes Deployment `PLANNED`

- [ ] Helm charts for 5G Core
- [ ] StatefulSet for NFs with state
- [ ] Service mesh integration
- [ ] Horizontal Pod Autoscaling
- [ ] Network policies for NF isolation

## 📋 v6.x — Monitoring & Observability `PLANNED`

- [ ] Prometheus metrics collection
- [ ] Grafana dashboards (NF health, UE sessions, throughput)
- [ ] Alerting rules for SLA violations
- [ ] Log aggregation (Loki / ELK)
- [ ] Distributed tracing for SBI calls

## 📋 v7.x — CI/CD Automation `PLANNED`

- [ ] GitHub Actions workflows
- [ ] Automated configuration validation
- [ ] Integration testing pipeline
- [ ] Documentation build & deploy
- [ ] Release automation

## 📋 v8.x — Cloud Deployment `PLANNED`

- [ ] OpenStack deployment guide
- [ ] K3s lightweight Kubernetes setup
- [ ] AWS deployment (optional)
- [ ] Multi-site / multi-cluster topology
- [ ] Cost optimization strategies

---

## Legend

| Status | Meaning |
|--------|---------|
| 🟢 `RELEASED` | Implemented and verified |
| 🔄 `IN PROGRESS` | Currently being worked on |
| 📋 `PLANNED` | Scoped but not started |
