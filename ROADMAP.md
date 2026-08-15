# 5G-IMS-Lab — Project Roadmap

Living document tracking the milestones and technical roadmap for the 5G Standalone and IMS testbed.

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
- [x] Multi-UE simulation with independent IMSIs (`001010000000001` and `001010000000002`)
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

## 🟢 Milestone 4: Comprehensive Test Automation & Regression `COMPLETED`

- [x] Standalone 22-step IMS infrastructure validation suite (`scripts/validate-ims-call.sh`)
- [x] Dedicated SIP dialog and RTPEngine media verification runner (`scripts/test-ims-call.sh`)
- [x] Complete 55-check 5G SA + IMS regression test suite (`scripts/verify-lab.sh`)
- [x] Monotonic CSeq verification across repeated registrations
- [x] Controlled negative testing (invalid credentials, unregistered destinations, malformed packets)
- [x] Detailed protocol analysis and live trace documentation (`docs/IMS-CALL-FLOW-VALIDATION.md`)

---

## 📋 Future Enhancements

- [ ] TLS / SRTP signaling and media encryption validation
- [ ] Diameter / Rx interface integration between P-CSCF and PCF for dynamic QoS policy
- [ ] Multi-cell handovers and mobility scenarios with UERANSIM
