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

## 3. 🧪 Validation Evidence & Test Results

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
