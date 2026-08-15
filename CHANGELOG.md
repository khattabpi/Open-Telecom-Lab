# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-08-15

### Added
- **Kamailio IMS Service Layer**:
  - P-CSCF with `hostNetwork` ingress (`10.46.0.1:5060`) and RFC 3327 Path routing.
  - I-CSCF with ClusterIP service and domain routing for `ims.lab`.
  - S-CSCF with memory-backed usrloc registrar and SQLite Digest MD5 authentication.
- **RTPEngine Media Proxy**:
  - SDP offer/answer endpoint rewriting to `10.46.0.1` and dynamic media relay ports (`20000-20100`).
  - NG protocol control over UDP port `22222`.
  - Automatic media session deletion upon BYE dialog teardown.
- **Multi-UE 5G SA Support**:
  - Parallel UE instances (`001010000000001` and `001010000000002`) with independent network namespaces.
  - Concurrent dual PDU sessions (`internet` and `ims` DNNs).
  - Dynamic SMF IP address resolution across `10.45.0.0/16` and `10.46.0.0/16`.
- **Automated Verification Suite**:
  - `scripts/validate-ims-call.sh` (22/22 standalone IMS checks passed).
  - `scripts/test-ims-call.sh` (end-to-end SIP call & 25/25 bidirectional G.711 PCMU RTP stream test).
  - `scripts/verify-lab.sh` (full 55/55 5G SA + IMS regression suite passed).
- **Technical Documentation**:
  - `docs/IMS-CALL-FLOW-VALIDATION.md` detailing message traces, root-cause analyses, and Wireshark captures.

---

## [1.0.0] — 2026-07-18

### Added
- **5G SA Core Network** — Full Open5GS v2.8.0 deployment
  - AMF, SMF, UPF, NRF, AUSF, UDM, UDR, PCF, NSSF, BSF, SCP
- **RAN Simulator** — UERANSIM v3.3.0 (gNodeB + UE)
- **UE Registration** — Initial Registration with PLMN selection (001/01)
- **5G-AKA Authentication** — Authentication with Security Mode
- **PDU Session Establishment** — IPv4 session on DNN `internet` (SST:1, SD:0xFFFFFF)
- **User Plane** — GTP-U tunnel via TUN interface (`ogstun`, `10.45.0.x`)
- **Internet Connectivity** — End-to-end data path with NAT via UPF
- **Subscriber Management** — MongoDB with provisioned test subscriber
