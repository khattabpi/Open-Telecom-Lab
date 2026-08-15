# Phase 4 Engineering Notes — 5G QoS, Policy Control, Charging & Service Assurance

---

## 1. ⚖️ 3GPP Architecture & Technical Classification

> **"Laboratory IMS Offline Charging and 5G User-Plane Usage Accounting with DiffServ QoS Scheduling and SBI Policy Traceability."**

### Technical Boundaries & Truth Matrix
- **Converged Charging System (CHF)**: Open5GS v2.8.0 does **not** provide `open5gs-chfd` or native 3GPP Nchf (TS 32.290 / TS 32.291) HTTP/2 microservices.
- **IMS Charging Architecture**: Implemented via Kamailio S-CSCF `acc` and `dialog` modules backed by persistent SQLite storage (`/etc/kamailio/db/kamailio.sqlite`), generating standard telecom Call Detail Records (CDRs) for domestic and inter-PLMN roaming calls.
- **5G User-Plane Accounting**: Emulated via real Linux kernel network namespace interface statistics (`ip -s link show uesimtun0`), tracking Uplink/Downlink Bytes and Packets per SUPI and DNN.
- **5G QoS / 5QI Differentiation**: Standard 5QI 9 (Internet Default Non-GBR) and 5QI 5 (IMS Signaling) provisioned in UDR/MongoDB and negotiated in NAS/NGAP with QFI 1. User-plane prioritization is enforced via IETF DiffServ DSCP classification (`EF` / `0xB8` for RTP audio, `CS5` / `0xA0` for SIP signaling) and Linux `tc prio` queueing on UPF `ogstun`.

---

## 2. 📊 Step 4C — Charging & Usage Accounting Implementation

### 2.1 SQLite CDR Database Schema
The S-CSCF SQLite database (`/etc/kamailio/db/kamailio.sqlite`) records completed and in-flight SIP dialogs in the `cdrs` and `acc` tables:

```sql
CREATE TABLE IF NOT EXISTS cdrs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    callid VARCHAR(255) DEFAULT '' NOT NULL,
    caller VARCHAR(128) DEFAULT '' NOT NULL,
    callee VARCHAR(128) DEFAULT '' NOT NULL,
    from_tag VARCHAR(128) DEFAULT '' NOT NULL,
    to_tag VARCHAR(128) DEFAULT '' NOT NULL,
    start_time VARCHAR(32) DEFAULT '' NOT NULL,
    end_time VARCHAR(32) DEFAULT '' NOT NULL,
    duration INTEGER DEFAULT 0 NOT NULL,
    sip_code VARCHAR(3) DEFAULT '200' NOT NULL,
    sip_reason VARCHAR(128) DEFAULT 'OK' NOT NULL,
    src_ip VARCHAR(64) DEFAULT '' NOT NULL,
    call_type VARCHAR(32) DEFAULT 'Vo5G-SIP' NOT NULL
);
```

### 2.2 CDR Lifecycle & Trigger Points
1. **Dialog Initialization (`INVITE`)**: S-CSCF intercepts the initial INVITE, invokes `dlg_manage()`, captures caller (`$fu`), callee (`$ru`), Call-ID (`$ci`), From-tag (`$ft`), Source IP (`$si`), and start timestamp (`$TS`).
2. **Dialog Teardown (`BYE`)**: Upon receiving the in-dialog BYE, S-CSCF calculates exact call duration (`$TS - $dlg_var(start_ts)`) and executes an atomic SQLite `INSERT` into `cdrs` with start/end formatted datetime strings.

### 2.3 User-Plane Data Accounting Telemetry
Usage counters are polled directly from the Linux kernel network namespace of each simulated UE:
- **UE1** (`imsi-602030000000001`): `ueransim-602030000000001-internet-psi1` & `ueransim-602030000000001-ims-psi2`
- **UE2** (`imsi-602040000000002`): `ueransim-602040000000002-internet-psi1` & `ueransim-602040000000002-ims-psi2`
- **UE3** (`imsi-602030000000003`): `ueransim-602030000000003-internet-psi1` & `ueransim-602030000000003-ims-psi2`

### 2.4 Charging Records Collector
The unified collector script [`scripts/collect-charging-records.sh`](file:///home/abdulrhamn/5G-IMS-Lab/scripts/collect-charging-records.sh) queries:
1. S-CSCF SQLite CDR table
2. Per-UE kernel namespace RX/TX byte and packet counters
3. UPF `ogstun` aggregate user-plane counters
Supports human-readable table formatting and machine-readable JSON (`--json`).

---

## 3. 🧪 Validation Evidence & Test Results (Charging & Usage)

```text
===============================================================================================
  5G-IMS-Lab Offline Charging & User-Plane Usage Accounting Report
===============================================================================================

1. IMS CALL DETAIL RECORDS (CDRs) — Kamailio S-CSCF SQLite
-----------------------------------------------------------------------------------------------
ID   Call-ID                   Caller             Callee             Start Time          Duration Status
-----------------------------------------------------------------------------------------------
1    call-run-12056@10.46.0.12 ue1@ims.lab        ue2@ims.lab        2026-08-15 16:40:56 1s       200 OK
2    call-run-12058@10.46.0.12 ue1@ims.lab        ue3@ims.lab        2026-08-15 16:40:58 2s       200 OK

2. 5G USER-PLANE DATA USAGE PER SUPI & DNN (Real Linux Netns Counters)
-----------------------------------------------------------------------------------------------
SUPI                   Serving PLMN     DNN        Allocated IP    UL (Bytes/Pk) DL (Bytes/Pk)
-----------------------------------------------------------------------------------------------
imsi-602030000000001   602/03           internet   10.45.0.12      2796 B (33p) 8985 B (25p)
imsi-602030000000001   602/03           ims        10.46.0.12      70342 B (300p) 73741 B (303p)
imsi-602040000000002   602/04           internet   10.45.0.13      2772 B (33p) 8824 B (22p)
imsi-602040000000002   602/04           ims        10.46.0.13      41034 B (160p) 41667 B (153p)
imsi-602030000000003   218/90 (Roaming) internet   10.45.0.101     2696 B (32p) 7476 B (22p)
imsi-602030000000003   218/90 (Roaming) ims        10.46.0.101     41353 B (161p) 42064 B (154p)
```

---

## 4. 📈 Step 4D — Service Assurance & Real-Time KPI Engine

### 4.1 Methodology & Telemetry Classification
The service assurance framework clearly delineates between **MEASURED**, **DERIVED**, and **ESTIMATED** metrics:

| Metric Category | Metric Name | Classification | Measurement Boundary / Methodology |
| :--- | :--- | :--- | :--- |
| **SIP Signaling** | **Post-Dial Delay (PDD)** | **MEASURED** | Time delta from `INVITE` dispatch socket timestamp to `180 Ringing` reception socket timestamp ($t_{180} - t_{\text{INVITE}}$). |
| **SIP Signaling** | **Call Setup Time (CST)** | **MEASURED** | Time delta from `INVITE` dispatch socket timestamp to `200 OK` reception socket timestamp ($t_{200} - t_{\text{INVITE}}$). |
| **SIP Signaling** | **Call Setup Success Rate (CSSR)** | **DERIVED** | Ratio of successfully completed SIP dialogs (200 OK + ACK confirmed) to initiated SIP sessions ($\frac{\text{Successful Dialogs}}{\text{Initiated Dialogs}} \times 100\%$). |
| **RTP Media** | **Packet Loss Rate** | **MEASURED** | Real packet count delta: $\frac{\text{Tx Packets} - \text{Rx Packets}}{\text{Tx Packets}} \times 100\%$. |
| **RTP Media** | **Sequence Continuity** | **MEASURED** | Monotonic sequence number verification ($0 \dots N-1$) ensuring zero lost and zero out-of-order frames. |
| **RTP Media** | **Inter-Arrival Jitter** | **MEASURED** | RFC 3550 Section 6.4.1 statistical jitter variance algorithm at 8000 Hz clock rate: $D(i,j) = (R_j - R_i) \times 8000 - (S_j - S_i)$, $J(i) = J(i-1) + \frac{\|D(i-1,i)\| - J(i-1)}{16}$. |
| **Voice Quality** | **Transmission Rating (R)** | **DERIVED** | ITU-T G.107 E-model transmission rating factor ($R = 93.2 - I_d - I_{e\text{-eff}}$). |
| **Voice Quality** | **Estimated MOS** | **ESTIMATED** | **"Estimated MOS using ITU-T G.107 E-model approximation"** derived from measured packet loss, delay ($d \approx \text{CST}/4$), RFC 3550 jitter, and standard G.711 PCMU parameters ($I_e = 0, B_{pl} = 4.3$). |

### 4.2 Voice Quality E-Model Approximation (ITU-T G.107)
The system calculates voice quality scores without subjective testing claims using the mathematical E-model:
- **Delay Impairment ($I_d$)**: For one-way delay $d < 177.3\text{ ms}$, $I_d = 0.024 d$; for $d \ge 177.3\text{ ms}$, $I_d = 0.024 d + 0.11(d - 177.3)$.
- **Equipment Impairment ($I_{e\text{-eff}}$)**: For G.711 PCMU ($I_e = 0, B_{pl} = 4.3$), $I_{e\text{-eff}} = I_e + (95 - I_e) \times \frac{P_{pl}}{P_{pl} + B_{pl}}$.
- **Estimated MOS Conversion**:
  $$\text{Estimated MOS} = 1 + 0.035 R + R(R - 60)(100 - R) \times 7 \times 10^{-6}$$

### 4.3 Observed Benchmark Telemetry

```text
═══════════════════════════════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Service Assurance & Real-Time KPI Report
═══════════════════════════════════════════════════════════════════════════════════════════════

▶ CALL SESSION: Domestic Vo5G IMS Voice Call
  Caller:  ue1@ims.lab (UE1 (Egypt 602/03)) [PLMN: 602/03 (Home)]
  Callee:  ue2@ims.lab (UE2 (Egypt 602/04)) [PLMN: 602/04 (Home)]
  ---------------------------------------------------------------------------------------------
  SIP Signaling KPIs:
    • Post-Dial Delay (PDD):      3.41 ms  (Target: < 200 ms)  [PASS]
    • Call Setup Time (CST):      54.43 ms (Target: < 500 ms)  [PASS]
    • Call Setup Success (CSSR): 100.0 %   (Target: 100%    )  [PASS]
  ---------------------------------------------------------------------------------------------
  RTP Media Assurance (Forward Leg: Caller ──► Callee):
    • Packets Transmitted/Received: 25/25 (0.0% loss)  [PASS]
    • Sequence Number Continuity:   CONTINUOUS (0 missing, 0 out-of-order)  [PASS]
    • RFC 3550 Inter-Arrival Jitter: 0.294 ms (Target: < 20.0 ms)  [PASS]
    • Packet Spacing (Min/Avg/Max): 17.4 / 20.2 / 25.1 ms
  ---------------------------------------------------------------------------------------------
  RTP Media Assurance (Reverse Leg: Callee ──► Caller):
    • Packets Transmitted/Received: 25/25 (0.0% loss)  [PASS]
    • Sequence Number Continuity:   CONTINUOUS (0 missing, 0 out-of-order)  [PASS]
    • RFC 3550 Inter-Arrival Jitter: 0.276 ms (Target: < 20.0 ms)  [PASS]
    • Packet Spacing (Min/Avg/Max): 17.9 / 20.2 / 24.7 ms
  ---------------------------------------------------------------------------------------------
  Voice Quality Telemetry (ITU-T G.107 E-Model Approximation):
    • Codec / Framing:          G.711 PCMU (SDP payload type 0, 8000 Hz, 20ms framing)
    • Transmission Rating (R):  92.87 / 100
    • Estimated MOS:            4.40 / 4.50 (Target: >= 4.0)  [PASS]
    • Note:                     Estimated MOS using ITU-T G.107 E-model approximation
  ---------------------------------------------------------------------------------------------
  Session Service Assurance:   [✓] PASS

▶ CALL SESSION: Inter-PLMN Roaming Vo5G IMS Voice Call
  Caller:  ue1@ims.lab (UE1 (Egypt 602/03)) [PLMN: 602/03 (Home)]
  Callee:  ue3@ims.lab (UE3 (Bosnia 218/90 Roaming)) [PLMN: 218/90 (Roaming)]
  ---------------------------------------------------------------------------------------------
  SIP Signaling KPIs:
    • Post-Dial Delay (PDD):      3.84 ms  (Target: < 200 ms)  [PASS]
    • Call Setup Time (CST):      55.92 ms (Target: < 500 ms)  [PASS]
    • Call Setup Success (CSSR): 100.0 %   (Target: 100%    )  [PASS]
  ---------------------------------------------------------------------------------------------
  RTP Media Assurance (Forward Leg: Caller ──► Callee):
    • Packets Transmitted/Received: 25/25 (0.0% loss)  [PASS]
    • Sequence Number Continuity:   CONTINUOUS (0 missing, 0 out-of-order)  [PASS]
    • RFC 3550 Inter-Arrival Jitter: 0.617 ms (Target: < 20.0 ms)  [PASS]
    • Packet Spacing (Min/Avg/Max): 18.1 / 20.2 / 23.8 ms
  ---------------------------------------------------------------------------------------------
  RTP Media Assurance (Reverse Leg: Callee ──► Caller):
    • Packets Transmitted/Received: 25/25 (0.0% loss)  [PASS]
    • Sequence Number Continuity:   CONTINUOUS (0 missing, 0 out-of-order)  [PASS]
    • RFC 3550 Inter-Arrival Jitter: 1.224 ms (Target: < 20.0 ms)  [PASS]
    • Packet Spacing (Min/Avg/Max): 13.4 / 20.2 / 26.7 ms
  ---------------------------------------------------------------------------------------------
  Voice Quality Telemetry (ITU-T G.107 E-Model Approximation):
    • Codec / Framing:          G.711 PCMU (SDP payload type 0, 8000 Hz, 20ms framing)
    • Transmission Rating (R):  92.84 / 100
    • Estimated MOS:            4.40 / 4.50 (Target: >= 4.0)  [PASS]
    • Note:                     Estimated MOS using ITU-T G.107 E-model approximation
  ---------------------------------------------------------------------------------------------
  Session Service Assurance:   [✓] PASS
```
