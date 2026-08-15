# 5G SA + IMS / Vo5G End-to-End Call Flow & Validation Guide

This document details the architecture, SIP signaling transactions, RTPEngine media proxy integration, root-cause debugging analysis, and end-to-end verification procedures for the 3GPP IP Multimedia Subsystem (IMS) service layer running over the Open5GS 5G Standalone dual-slice core.

---

## 1. 🏛️ Architecture & Network Topology

```
                  5G SA Control Plane (N2 NGAP via Home AMF :38412 & Visited AMF :38413)
                  5G SA User Plane    (N3 GTP-U via UPF :2152 on ogstun)
                                       │
                  ┌────────────────────┼────────────────────┐
                  │                    │                    │
        [UE1: 10.46.0.10:5060]  [UE2: 10.46.0.11:5060]  [UE3: 10.46.0.100:5060]
        IMSI: 602030000000001   IMSI: 602040000000002   IMSI: 602030000000003
        HPLMN: 602/03 (Home)    HPLMN: 602/04 (Home)    HPLMN: 602/03 | VPLMN: 218/90
        SIP: sip:ue1@ims.lab    SIP: sip:ue2@ims.lab    SIP: sip:ue3@ims.lab
                  │                    │                    │
                  └────────────────────┼────────────────────┘
                                       │ SIP Signaling (10.46.0.0/16)
                                       ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ Kubernetes Namespace: ims                                               │
    │                                                                         │
    │  ┌───────────────────────────────────────────────────────────────────┐  │
    │  │ P-CSCF (Proxy-CSCF) — kamailio-pcscf                              │  │
    │  │ • Ingress Listener: 10.46.0.1:5060 (hostNetwork: true)            │  │
    │  │ • Path Header Insertion (RFC 3327) & NAT Traversal                │  │
    │  │ • RTPEngine Media Control (rtpengine_offer / rtpengine_answer)    │  │
    │  └──────────────────┬─────────────────────────────▲──────────────────┘  │
    │                     │                             │                     │
    │                     ▼                             │                     │
    │  ┌────────────────────────────────────┐           │                     │
    │  │ I-CSCF (Interrogating-CSCF)        │           │ Terminating Route   │
    │  │ • Service: kamailio-icscf:5060     │           │                     │
    │  │ • Ingress routing for home network │           │                     │
    │  └──────────────────┬─────────────────┘           │                     │
    │                     │                             │                     │
    │                     ▼                             │                     │
    │  ┌────────────────────────────────────────────────┴──────────────────┐  │
    │  │ S-CSCF (Serving-CSCF) — kamailio-scscf                            │  │
    │  │ • Service: kamailio-scscf:5060                                    │  │
    │  │ • 3GPP User Registration (usrloc) & Digest Auth (auth_db)         │  │
    │  │ • Originating & Terminating session state routing                 │  │
    │  │ • SQLite Subscriber Credentials Backend                           │  │
    │  └───────────────────────────────────────────────────────────────────┘  │
    │                                                                         │
    │  ┌───────────────────────────────────────────────────────────────────┐  │
    │  │ RTPEngine (Media Relay Daemon) — rtpengine                        │  │
    │  │ • NG Control Protocol: 127.0.0.1:22222 / 172.19.0.2:22222        │  │
    │  │ • Voice Media Relay Ports: UDP 20000-20100 on 10.46.0.1           │  │
    │  └───────────────────────────────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 📞 End-to-End SIP Call & Media Sequence

```mermaid
sequenceDiagram
    autonumber
    participant UE1 as UE1 (10.46.0.7)
    participant PCSCF as P-CSCF (10.46.0.1:5060)
    participant ICSCF as I-CSCF
    participant SCSCF as S-CSCF
    participant RTPENG as RTPEngine (10.46.0.1)
    participant UE2 as UE2 (10.46.0.8)

    Note over UE1,SCSCF: 1. SIP Registration & 3GPP Digest MD5 Challenge-Response
    UE1->>PCSCF: REGISTER sip:ims.lab (Contact: <sip:ue1@10.46.0.7:5060>)
    PCSCF->>ICSCF: REGISTER (Path: <sip:10.46.0.1:5060;lr;received="sip:10.46.0.7:5060">)
    ICSCF->>SCSCF: REGISTER
    SCSCF-->>ICSCF: 401 Unauthorized (Digest realm="ims.lab", nonce="...")
    ICSCF-->>PCSCF: 401 Unauthorized
    PCSCF-->>UE1: 401 Unauthorized
    UE1->>PCSCF: REGISTER (Authorization: Digest username="ue1", response="...")
    PCSCF->>ICSCF: REGISTER (Authorization)
    ICSCF->>SCSCF: REGISTER (Authorization)
    SCSCF-->>ICSCF: 200 OK (Binding stored in usrloc memory)
    ICSCF-->>PCSCF: 200 OK
    PCSCF-->>UE1: 200 OK

    Note over UE1,UE2: 2. Vo5G Session Setup & RTPEngine SDP Proxying
    UE1->>PCSCF: INVITE sip:ue2@ims.lab (SDP: c=10.46.0.7, m=10000)
    PCSCF->>RTPENG: rtpengine_offer (Allocates relay port 20000)
    RTPENG-->>PCSCF: Rewritten SDP (c=10.46.0.1, m=20000)
    PCSCF->>SCSCF: INVITE (SDP: c=10.46.0.1, m=20000)
    SCSCF->>PCSCF: INVITE to terminating Path (UE2)
    PCSCF->>UE2: INVITE (SDP: c=10.46.0.1, m=20000)
    UE2-->>PCSCF: 180 Ringing
    PCSCF-->>SCSCF: 180 Ringing
    SCSCF-->>PCSCF: 180 Ringing
    PCSCF-->>UE1: 180 Ringing
    UE2-->>PCSCF: 200 OK (SDP: c=10.46.0.8, m=10000)
    PCSCF->>RTPENG: rtpengine_answer (Allocates relay port 20008)
    RTPENG-->>PCSCF: Rewritten SDP (c=10.46.0.1, m=20008)
    PCSCF-->>SCSCF: 200 OK (SDP: c=10.46.0.1, m=20008)
    SCSCF-->>PCSCF: 200 OK
    PCSCF-->>UE1: 200 OK (SDP: c=10.46.0.1, m=20008)
    UE1->>PCSCF: ACK
    PCSCF->>SCSCF: ACK
    SCSCF->>PCSCF: ACK
    PCSCF->>UE2: ACK

    Note over UE1,UE2: 3. Bidirectional RTP Voice Media Flow via RTPEngine
    UE1->>RTPENG: RTP Audio (10.46.0.7:10000 -> 10.46.0.1:20008)
    RTPENG->>UE2: RTP Audio (10.46.0.1 -> 10.46.0.8:10000)
    UE2->>RTPENG: RTP Audio (10.46.0.8:10000 -> 10.46.0.1:20000)
    RTPENG->>UE1: RTP Audio (10.46.0.1 -> 10.46.0.7:10000)

    Note over UE1,UE2: 4. Session Teardown
    UE1->>PCSCF: BYE
    PCSCF->>RTPENG: rtpengine_delete (Releases relay ports)
    PCSCF->>SCSCF: BYE
    SCSCF->>PCSCF: BYE
    PCSCF->>UE2: BYE
    UE2-->>PCSCF: 200 OK
    PCSCF-->>SCSCF: 200 OK
    SCSCF-->>PCSCF: 200 OK
    PCSCF-->>UE1: 200 OK
```

---

## 3. 🔍 Root Causes & Technical Solutions

### Issue 1: Malformed SIP Header in P-CSCF Logs
- **Observed Log:**
  ```text
  invalid header name for: [ue1[authentication username=W password=password123] ...
  bad header / parse_headers(): bad header field
  ```
- **Root Cause:** A test scenario (`configs/sipp/register.xml`) had an improperly formatted SIPp macro `[authentication username=[field0]...]` without preceding `Authorization:` header tag. When executed, raw XML template text was sent directly over UDP, causing Kamailio's parser to reject the packet.
- **Fix:** Switched test runner to native, dependency-free Python RFC 3261 / RFC 2617 Digest MD5 implementation in `scripts/test-ims-call.sh` and `scripts/validate-ims-call.sh`.

---

### Issue 2: Module Initialization Order Warnings in Kamailio
- **Observed Log:**
  ```text
  ERROR: tm [tm_load.c:33]: load_tm(): Module not initialized yet, make sure that all modules that need tm module are loaded after tm in the configuration file
  sl: could not bind tm module - only stateless mode available during modules initialization
  ```
- **Root Cause:** `sl.so` was loaded before `tm.so` in `pcscf.cfg`, `icscf.cfg`, and `scscf.cfg`.
- **Fix:** Placed `loadmodule "tm.so"` first before `loadmodule "sl.so"`, `rr.so`, and `path.so`.

---

### Issue 3: CSeq Invalidity During Repeated Registrations
- **Observed Log:**
  ```text
  ERROR: registrar [save.c:721]: update_contacts(): invalid cseq for aor <ue1>
  ```
- **Root Cause:** Re-running test scripts with fixed CSeq (`CSeq: 1 REGISTER`) caused the Kamailio registrar to reject lower/duplicate CSeq values as mandated by RFC 3261 Section 10.3.
- **Fix:** Configured `cseq_base = int(time.time())` in client scripts for monotonic CSeq progression, and configured `modparam("usrloc", "db_mode", 0)` with `modparam("usrloc", "cseq_delay", 0)` in `scscf.cfg`.

---

### Issue 4: RTP Media Flowing Directly instead of via RTPEngine
- **Observed Behavior:** RTP packets were sent directly between `10.46.0.7` and `10.46.0.8` without media proxying.
- **Root Cause:** P-CSCF was relaying INVITE and 200 OK without invoking `rtpengine_offer()` and `rtpengine_answer()`.
- **Fix:** 
  1. Deployed RTPEngine on `hostNetwork: true` listening on `10.46.0.1:20000-20100` and control port `127.0.0.1:22222`.
  2. Integrated `rtpengine_offer("replace-origin replace-session-connection ICE=remove")` on INVITE in `pcscf.cfg`.
  3. Integrated `rtpengine_answer("replace-origin replace-session-connection ICE=remove")` on 200 OK SDP answer in `pcscf.cfg`.
  4. Integrated `rtpengine_delete()` on BYE and CANCEL.

---

## 4. 🚀 Validation & Execution Commands

### Quick Validation
```bash
sudo bash scripts/validate-ims-call.sh
```

### End-to-End Call Test
```bash
sudo bash scripts/test-ims-call.sh
```

### Full 5G Core + IMS Regression Suite
```bash
sudo bash scripts/verify-lab.sh
```

---

## 5. 📊 Packet Capture Methodology

To capture live SIP signaling and RTPEngine media traffic during a call:

```bash
# Capture SIP signaling on UPF ogstun interface
sudo tcpdump -i ogstun -n -s 0 -vvv "udp port 5060 or udp portrange 20000-20100" -w /tmp/ims-call.pcap
```

---

## 6. ⚖️ 3GPP Roaming Capabilities & Technical Boundaries

This laboratory is strictly classified as:
> **"5G Inter-PLMN Roaming Laboratory with Home-Network Authentication, Local Breakout, and IMS Roaming / Inter-PLMN Voice Service."**

### Technical Truth Matrix

- **5G Authentication**: Real 5G-AKA authentication handled by Home AUSF over N12 `Nausf_UEAuthentication` with `servingNetworkName: 5G:mnc090.mcc218.3gppnetwork.org`.
- **IMS Authentication**: Laboratory SIP Digest MD5 authentication against SQLite subscriber database in S-CSCF.
- **IMS Inter-Operator Routing**: Laboratory / emulated inter-operator IMS routing.
- **SEPP / N32**: Not implemented (cross-PLMN SBI uses direct Kubernetes cluster DNS).
- **IBCF / TrGW**: Not implemented (direct P-CSCF/S-CSCF routing with RTPEngine proxying).
- **Home-Routed (HR) Roaming (N16/N9)**: Not supported in Open5GS 2.8.0; user plane uses Local Breakout (LBO).
