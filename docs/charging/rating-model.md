# Phase 5.5 — Telecom Rating Model & Tariff Specification

## 1. Overview

The `5G-IMS-Lab` rating engine employs a deterministic mathematical model supporting multi-service rating across domestic and inter-PLMN roaming boundaries.

---

## 2. Voice Rating Model

### 2.1 Formula & Arithmetic

$$\text{Call Cost} = \text{Setup Fee} + \left( \left\lceil \frac{\max(\text{Duration}, \text{Min Units})}{\text{Granularity}} \right\rceil \times \text{Granularity} \right) \times \frac{\text{Unit Rate}}{\text{Unit Size}}$$

Where:
- $\text{Setup Fee}$ is a fixed connection establishment charge.
- $\text{Min Units}$ is the minimum billable interval (e.g., 1 second).
- $\text{Granularity}$ defines increment rounding steps.
- $\text{Rounding Policy}$ defaults to `CEIL` (standard telecom ceiling rounding).

### 2.2 Voice Tariff Classes

| Tariff ID | Rate Plan | Service | Destination | Setup Charge | Unit Rate | Unit Size | Min Billable | Rounding | Effective Rate |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `tariff-domestic-voice` | `standard-prepaid` | `voice` | `domestic` | `0.05 LAB` | `0.02 LAB` | 1 sec | 1 sec | `CEIL` | `1.20 LAB / min` |
| `tariff-roaming-voice` | `standard-prepaid` | `voice` | `roaming_vplmn` | `0.15 LAB` | `0.08 LAB` | 1 sec | 1 sec | `CEIL` | `4.80 LAB / min` |
| `tariff-premium-roaming-voice` | `premium-roaming` | `voice` | `roaming_vplmn` | `0.10 LAB` | `0.04 LAB` | 1 sec | 1 sec | `CEIL` | `2.40 LAB / min` |

---

## 3. Data Rating Model

### 3.1 Formula & Arithmetic

$$\text{Data Cost} = \left\lceil \frac{\max(\text{Total Bytes}, \text{Min Bytes})}{\text{Granularity Bytes}} \right\rceil \times \text{Granularity Bytes} \times \frac{\text{Unit Rate}}{\text{1 MB (1,048,576 Bytes)}}$$

### 3.2 Data Tariff Classes

| Tariff ID | Rate Plan | Service | Destination | DNN | Unit Rate | Unit Size | Granularity | Notes |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| `tariff-domestic-data-internet` | `standard-prepaid` | `data` | `domestic` | `internet` | `0.010 LAB` | 1 MB | 1,024 B (1 KB) | Domestic data access |
| `tariff-domestic-data-ims` | `standard-prepaid` | `data` | `domestic` | `ims` | `0.000 LAB` | 1 MB | 1,024 B (1 KB) | **Zero-Rated** Vo5G signaling bearer |
| `tariff-roaming-data-internet` | `standard-prepaid` | `data` | `roaming_vplmn` | `internet` | `0.050 LAB` | 1 MB | 1,024 B (1 KB) | Roaming data surcharge |
| `tariff-premium-roaming-data` | `premium-roaming` | `data` | `roaming_vplmn` | `internet` | `0.025 LAB` | 1 MB | 1,024 B (1 KB) | Discounted roaming data |
| `tariff-roaming-data-ims` | `standard-prepaid` | `data` | `roaming_vplmn` | `ims` | `0.000 LAB` | 1 MB | 1,024 B (1 KB) | **Zero-Rated** Roaming IMS bearer |

---

## 4. Destination Classification Logic

The rating engine determines `destination_type` (`domestic` vs `roaming_vplmn`) by comparing the subscriber's Home PLMN (`account.plmn`) against their active Serving / Visited PLMN (`account.serving_plmn` or `event.origin_plmn`):

$$\text{Roaming Originating Call: } \text{account.serving\_plmn} \neq \text{account.plmn} \implies \text{destination\_type} = \text{roaming\_vplmn}$$

$$\text{Roaming Terminating Call: } \text{callee\_account.serving\_plmn} \neq \text{callee\_account.plmn} \implies \text{destination\_type} = \text{roaming\_vplmn}$$

```mermaid
flowchart TD
    START([Incoming Usage Event]) --> SVC{Service Type?}
    
    SVC -->|Voice| ORIG_CHECK{Caller Serving PLMN != Home PLMN?}
    ORIG_CHECK -->|Yes e.g. VPLMN 218/90| ROAM[Destination: roaming_vplmn]
    ORIG_CHECK -->|No / Domestic| CALLEE{Callee Serving PLMN != Home PLMN?}
    CALLEE -->|Yes e.g. UE3 in VPLMN 218/90| ROAM
    CALLEE -->|No e.g. UE1 <-> UE2 / PLMN 602/03 & 602/04| DOM[Destination: domestic]

    SVC -->|Data| DATA_ORIG{Serving PLMN != Home PLMN?}
    DATA_ORIG -->|Yes e.g. VPLMN 218/90| ROAM
    DATA_ORIG -->|No e.g. HPLMN 602/03 or 602/04| DOM

    ROAM --> TARIFF[Select Tariff for Rate Plan + Service + Destination]
    DOM --> TARIFF
```

### 4.1 Roaming Voice Classification Example (UE3)
- **Subscriber:** UE3 (`acc-ue3`)
- **Home PLMN (`account.plmn`):** `602/03` (Egypt)
- **Serving PLMN (`account.serving_plmn`):** `218/90` (Bosnia Local Breakout)
- **Rate Plan:** `premium-roaming`
- **Destination Type:** `roaming_vplmn`
- **Selected Tariff:** `tariff-premium-roaming-voice` (Setup: `0.10 LAB`, Unit Rate: `0.04 LAB/s`)
- **10-Second Call Rating Calculation:**
  $$\text{Total Charge} = 0.10\text{ LAB (Setup)} + (10\text{ s} \times 0.04\text{ LAB/s}) = 0.10 + 0.40 = \mathbf{0.5000\text{ LAB}}$$

---

## 5. Billing Traceability & Rating Explanation

Every rated event produces a human-readable, auditable mathematical explanation stored in `rated_usage.rating_explanation`:

```text
[Voice Rating] Plan: premium-roaming | Tariff: tariff-premium-roaming-voice (roaming_vplmn) | 
Duration: 10.0s -> Billable: 10s | 
Setup: 0.10 LAB + Usage: 0.4000 LAB (@ 0.04/s) = Total: 0.5000 LAB
```
