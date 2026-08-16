# Phase 5.5 — Automated Testing & Validation Specification

## 1. Test Suite Architecture

Phase 5.5 provides an automated, non-destructive 23-point verification suite: `scripts/verify-rating.sh`.

> [!IMPORTANT]
> **Execution Shell Requirement:** `verify-rating.sh` is a **Bash script**, not a Python script. It must be executed as:
> ```bash
> bash scripts/verify-rating.sh
> # or:
> ./scripts/verify-rating.sh
> ```
> *Never execute as `python3 scripts/verify-rating.sh`.*

### Test Isolation & Harness Architecture
To protect live operator balances from drift or test-induced corruption, `verify-rating.sh` implements **test fixture isolation**:
1. Read-only checks (schema, rate plans, account configurations) validate the operational database (`data/charging.sqlite`).
2. Mutating transaction tests (reservations, debits, insufficient balance checks, rounding policies) run against an isolated temporary SQLite database fixture (`/tmp/charging_test_fixture_$$.sqlite`) instantiated dynamically via `CHARGING_DB_PATH`.
3. Ingestion and idempotency tests validate against the authentic Kamailio S-CSCF CDR dataset.

---

## 2. Test Cases Specification Matrix (23 Tests)

| Test ID | Category | Target Assertion | Validation Method |
| :--- | :--- | :--- | :--- |
| `[RATING-01]` | Architecture | Rating Engine & CLI Availability | Asserts `scripts/rating-engine.py` and `src/charging` exist |
| `[RATING-02]` | Database | SQLite Schema Initialization | Validates all 6 core charging tables with foreign keys |
| `[RATING-03]` | Schema | `serving_plmn` Column Schema | Asserts `charging_accounts` table contains `serving_plmn` |
| `[RATING-04]` | Provisioning | UE1 Domestic Account Configuration | Asserts `acc-ue1` has `plmn='602/03'`, `serving_plmn=NULL`, `standard-prepaid` |
| `[RATING-05]` | Provisioning | UE2 Domestic Account Configuration | Asserts `acc-ue2` has `plmn='602/04'`, `serving_plmn=NULL`, `standard-prepaid` |
| `[RATING-06]` | Provisioning | UE3 Roaming Account Configuration | Asserts `acc-ue3` has `plmn='602/03'`, `serving_plmn='218/90'`, `premium-roaming` |
| `[RATING-07]` | Tariff Model | Roaming Voice Tariff Verification | Asserts `tariff-premium-roaming-voice` (setup: `0.10 LAB`, rate: `0.04 LAB/s`) |
| `[RATING-08]` | Tariff Model | Domestic Voice Tariff Verification | Asserts `tariff-domestic-voice` (setup: `0.05 LAB`, rate: `0.02 LAB/s`) |
| `[RATING-09]` | Rating Engine | Roaming Originating Voice Rating | UE3 (VPLMN `218/90`) 10s call $\rightarrow$ `0.5000 LAB` (`tariff-premium-roaming-voice`) |
| `[RATING-10]` | Rating Engine | Domestic Voice Rating Regression | UE1 $\rightarrow$ UE2 10s call $\rightarrow$ `0.2500 LAB` (`tariff-domestic-voice`) |
| `[RATING-11]` | Balance Engine | Reservation Lifecycle & Refund | Reserve `5.00 LAB`, consume `1.50 LAB` $\rightarrow$ `3.50 LAB` refund, `reserve=0.00` |
| `[RATING-12]` | Balance Engine | Roaming Balance Accounting | UE3 balance updated from `30.0000` $\rightarrow$ `29.5000 LAB` (`0.5000` consumed) |
| `[RATING-13]` | Audit Ledger | Transaction Journal Continuity | Verifies sequential audit trail (`TOPUP`, `RESERVE`, `CHARGE`) |
| `[RATING-14]` | Integrity | Insufficient Balance Rejection | Rejects debit when balance $< \text{setup}$ (`0.02 LAB` preserved, non-negative) |
| `[RATING-15]` | Rating Engine | Duration Rounding Policy (`CEIL`) | Tests 1.1s duration rounded up to 2 billable seconds (`0.0900 LAB`) |
| `[RATING-16]` | Ingestion | Kamailio S-CSCF CDR Ingestion | Discovers and rates all pending CDRs from `kamailio.sqlite` |
| `[RATING-17]` | Ingestion | CDR Traffic Classification | Asserts both `domestic` and `roaming_vplmn` traffic classes exist |
| `[RATING-18]` | Idempotency | CDR Re-Rating Idempotency | Re-rating produces `0 newly rated`, `0 double-debits` |
| `[RATING-19]` | Reconciliation | Financial Reconciliation Audit | 100% mathematical consistency across ledger and balances (PASS, 0 anomalies) |
| `[RATING-20]` | Telemetry | Prometheus Exporter Telemetry | Metric `charging_revenue_total` exposed on port `:9100` |
| `[RATING-21]` | Telemetry | Prometheus Target Scrape | Metric `charging_revenue_total` successfully scraped on `:30090` |
| `[RATING-22]` | Dashboard | Grafana Section J Visual Panels | Asserts $\ge 50$ visual panels active in Grafana dashboard |
| `[RATING-23]` | Alerting | Alertmanager Rating Alert Rules | Asserts 5 declarative rules active in `telecom_rating_charging_alerts` |

---

## 3. End-to-End Test Execution Result

```text
═══════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Phase 5.5 Telecom Rating & Balance Verification Suite     
═══════════════════════════════════════════════════════════════════════

1. Architecture, Schema & Account Configuration Validation
  [✓] [RATING-01] Charging Database & Engine: data/charging.sqlite and src/charging package available
  [✓] [RATING-02] Required Tables: all 6 charging tables created with foreign keys & indexes
  [✓] [RATING-03] serving_plmn Schema: charging_accounts table contains serving_plmn column
  [✓] [RATING-04] UE1 Domestic Configuration: acc-ue1 configured as domestic (PLMN 602/03, plan standard-prepaid)
  [✓] [RATING-05] UE2 Domestic Configuration: acc-ue2 configured as domestic (PLMN 602/04, plan standard-prepaid)
  [✓] [RATING-06] UE3 Roaming Configuration: acc-ue3 configured as roaming (HPLMN 602/03, VPLMN 218/90, plan premium-roaming)
  [✓] [RATING-07] Roaming Voice Tariff: tariff-premium-roaming-voice verified (setup 0.10 LAB, rate 0.04 LAB/s)
  [✓] [RATING-08] Domestic Voice Tariff: tariff-domestic-voice verified (setup 0.05 LAB, rate 0.02 LAB/s)

2. Deterministic Rating & Isolated Balance Lifecycle
  [✓] [RATING-09] Roaming Voice Rating: UE3 (VPLMN 218/90) 10s call -> 0.5000 LAB (roaming_vplmn, tariff-premium-roaming-voice)
  [✓] [RATING-10] Domestic Voice Regression: UE1 -> UE2 10s call -> 0.2500 LAB (domestic, tariff-domestic-voice)
  [✓] [RATING-11] Reservation Lifecycle: reserve 5.00 LAB -> consume 1.50 LAB -> 3.50 refund returned, reserve=0.00
  [✓] [RATING-12] Roaming Balance Accounting: UE3 balance updated from 30.0000 -> 29.5000 LAB (0.5000 consumed, 0.0000 reserved)
  [✓] [RATING-13] Transaction Ledger: auditable journal entries (TOPUP, RESERVE, CHARGE) verified with continuous balance tracking
  [✓] [RATING-14] Insufficient Balance Protection: transaction rejected without balance corruption (0.02 LAB preserved, non-negative)
  [✓] [RATING-15] Duration Rounding Policy: 1.1s call correctly rounded to 2s billable units (CEIL)

3. CDR Pipeline, Idempotency & Financial Reconciliation
  [✓] [RATING-16] CDR Ingestion: Rating Summary: 0 newly rated, 108 already rated
  [✓] [RATING-17] CDR Classification: both domestic and roaming_vplmn traffic classes rated (domestic=54:roaming=54)
  [✓] [RATING-18] CDR Rating Idempotency: re-rating produces 0 newly rated, 0 double-debits (idempotent)
  [✓] [RATING-19] Financial Reconciliation Audit: 100% mathematical consistency across ledger and balances (PASS, 0 anomalies)

4. Observability, Metrics & Alerting Integration
  [✓] [RATING-20] Prometheus Exporter Telemetry: charging_revenue_total exposed on :9100 (17.34 LAB)
  [✓] [RATING-21] Prometheus Target Scrape: charging_revenue_total scraped by Prometheus (17.34 LAB)
  [✓] [RATING-22] Grafana Dashboard Section J: 53 visual panels loaded including Section J Revenue & Balance
  [✓] [RATING-23] Alertmanager Rules: 5 declarative charging alert rules active in Prometheus

═══════════════════════════════════════════════════════════════════════
  Phase 5.5 Rating & Balance Verification Summary: 23 Passed, 0 Failed
═══════════════════════════════════════════════════════════════════════
  >>> All Phase 5.5 Telecom Rating & Balance Management Tests Passed! <<<
```
