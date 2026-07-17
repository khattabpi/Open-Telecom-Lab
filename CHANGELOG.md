# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Protocol walkthrough documentation (NAS, NGAP, PFCP, GTP-U)
- Wireshark filter guides and annotated captures
- Additional lab exercises

---

## [1.0.0] — 2026-07-18

### Added
- **5G SA Core Network** — Full Open5GS v2.8.0 deployment on Ubuntu 24.04 LTS
  - AMF, SMF, UPF, NRF, AUSF, UDM, UDR, PCF, NSSF, BSF, SCP
- **RAN Simulator** — UERANSIM v3.3.0 (gNodeB + UE)
- **UE Registration** — Initial Registration with PLMN selection (001/01)
- **5G-AKA Authentication** — Full authentication with Security Mode (NIA2/NEA0)
- **PDU Session Establishment** — IPv4 session on DNN `internet` (SST:1, SD:0xFFFFFF)
- **User Plane** — GTP-U tunnel via TUN interface (uesimtun0, 10.45.0.x)
- **Internet Connectivity** — End-to-end data path with NAT via UPF
- **Subscriber Management** — MongoDB 8.0 with provisioned test subscriber
- **Protocol Captures** — tcpdump PCAP files for NGAP, PFCP, GTP-U analysis
- **Network Namespace Isolation** — Linux namespace-based UE traffic separation
- **Configuration Files** — Open5GS (AMF, SMF, UPF) and UERANSIM (gNB, UE) configs
- **Documentation** — Architecture diagrams, installation guide, troubleshooting
- **Repository Structure** — GitHub templates, contributing guide, security policy

### Infrastructure
- Ubuntu 24.04 LTS (Noble Numbat)
- Native deployment (no containers)
- MongoDB 8.0.26
- iptables NAT for UE internet access
