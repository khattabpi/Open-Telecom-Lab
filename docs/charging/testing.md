# Phase 5.5 — Automated Testing & Validation Specification

## 1. Test Suite Architecture

Phase 5.5 introduces a dedicated 22-test automated regression suite: `scripts/verify-rating.sh`.

```text
sudo ./scripts/verify-rating.sh
```

---

## 2. Test Cases Specification Matrix

| Test ID | Test Category | Target Assertion | Validation Method |
| :--- | :--- | :--- | :--- |
| `[RATING-01]` | Architecture | CLI & Python Package Availability | Asserts `rating-engine.py` and `src/charging/` exist |
| `[RATING-02]` | Database | SQLite Table & Schema Initialization | Queries `sqlite_master` for 6 required tables |
| `[RATING-03]` | Configuration | Declarative Tariffs Loaded | Asserts $\ge 6$ active tariffs in `tariffs` table |
| `[RATING-04]` | Provisioning | Subscriber Accounts & Seed Balances | Asserts accounts provisioned for UE1, UE2, UE3, Test |
| `[RATING-05]` | Management | Account Balance Inquiry CLI | Formats and queries balance statement for `acc-ue1` |
| `[RATING-06]` | Management | Prepaid Account Top-Up Transaction | Tests balance credit with auditable transaction logging |
| `[RATING-07]` | Rating Engine | Domestic Voice Call Rating | Asserts setup 0.05 + (2s * 0.02) = 0.0900 LAB |
| `[RATING-08]` | Rating Engine | Inter-PLMN Roaming Voice Rating | Asserts setup 0.15 + (2s * 0.08) = 0.3100 LAB |
| `[RATING-09]` | Rating Engine | Call Duration Ceiling Rounding | Tests 1.1s duration $\rightarrow$ 2s billable units |
| `[RATING-10]` | Rating Engine | Data Usage Rating (DNN: internet) | Tests 2 MB data rating $\rightarrow$ 0.0200 LAB |
| `[RATING-11]` | Rating Engine | Zero-Rated IMS Signaling Bearer | Tests DNN `ims` data rating $\rightarrow$ 0.0000 LAB |
| `[RATING-12]` | Balance Lifecycle | Session Balance Reservation | Tests `AVAILABLE` $\rightarrow$ `RESERVED` credit hold |
| `[RATING-13]` | Balance Lifecycle | Reservation Consumption & Refund | Tests `RESERVED` $\rightarrow$ `CONSUMED` with unused credit refund |
| `[RATING-14]` | Balance Lifecycle | Reservation Release | Tests `RESERVED` $\rightarrow$ `AVAILABLE` cancellation |
| `[RATING-15]` | Integrity | Insufficient Balance Rejection | Verifies call rejection when balance < setup fee |
| `[RATING-16]` | Integrity | Idempotent Duplicate Charge Protection | Proves duplicate CDR ingestion is rejected |
| `[RATING-17]` | Audit Trail | Transaction Ledger Continuity | Verifies sequential balance before/after audit entries |
| `[RATING-18]` | Reconciliation | Mathematical Accounting Consistency | Verifies 0 anomalies across ledger and balances |
| `[RATING-19]` | Observability | Prometheus Exporter Telemetry (:9100) | Asserts `charging_revenue_total` on exporter endpoint |
| `[RATING-20]` | Observability | Prometheus Server Scrape Target | Queries Prometheus API for scraped charging metrics |
| `[RATING-21]` | Observability | Grafana Section J Dashboard Panels | Asserts $\ge 50$ total panels in Grafana dashboard |
| `[RATING-22]` | Alerting | Alertmanager Rating Alert Rules | Asserts 5 charging rules in `telecom_rating_charging_alerts` |

---

## 3. End-to-End Test Execution Result

```text
═══════════════════════════════════════════════════════════════════════
  5G-IMS-Lab Phase 5.5 Telecom Rating & Balance Verification Suite     
═══════════════════════════════════════════════════════════════════════

1. Rating Engine Architecture & Database Validation
  [✓] [RATING-01] Rating Engine CLI: scripts/rating-engine.py and src/charging package available
  [✓] [RATING-02] Database Schema: all 6 charging tables created with foreign keys & indexes
  [✓] [RATING-03] Rate Plans & Tariffs: 8 declarative tariff rules provisioned
  [✓] [RATING-04] Subscriber Accounts: 4 subscriber accounts provisioned (UE1, UE2, UE3, Test)
  [✓] [RATING-05] Balance Inquiry: balance statement retrieved cleanly for acc-ue1

2. Deterministic Rating & Financial Accounting Logic
  [✓] [RATING-06] Prepaid Account Top-Up: credit added to available balance with transaction logging
  [✓] [RATING-07] Domestic Voice Rating: setup 0.05 + (2s * 0.02) = 0.0900 LAB (domestic)
  [✓] [RATING-08] Roaming Voice Rating: setup 0.15 + (2s * 0.08) = 0.3100 LAB (roaming_vplmn)
  [✓] [RATING-09] Duration Rounding Policy: 1.1s call correctly rounded to 2s billable units (CEIL)
  [✓] [RATING-10] Data Usage Rating (Internet): 2 MB internet data rated at 0.0200 LAB
  [✓] [RATING-11] Zero-Rated Bearer Policy: IMS signaling bearer zero-rated (0.0000 LAB)

3. Reservation Lifecycle & Atomicity Constraints
  [✓] [RATING-12] Balance Reservation: 5.00 LAB successfully reserved on acc-ue2 (ID: res-16317e4e)
  [✓] [RATING-13] Reservation Consumption: actual usage 1.50 LAB debited, 3.50 refund returned to available
  [✓] [RATING-14] Reservation Release: unconsumed reservation released back to available balance
  [✓] [RATING-15] Insufficient Balance Rejection: transaction rejected without balance corruption (0.02 preserved)
  [✓] [RATING-16] Idempotency & Duplicate Protection: duplicate CDR charge rejected without double-debiting
  [✓] [RATING-17] Transaction Ledger Audit: 104 immutable journal entries verified for acc-ue1
  [✓] [RATING-18] Financial Reconciliation Audit: 100% mathematical consistency across balances and ledger (PASS)

4. Observability, Metrics & Alerting Integration
  [✓] [RATING-19] Prometheus Exporter Telemetry: charging_revenue_total exposed on :9100 (16.14 LAB)
  [✓] [RATING-20] Prometheus Target Scrape: charging_revenue_total scraped by Prometheus (16.14 LAB)
  [✓] [RATING-21] Grafana Dashboard Section J: 53 visual panels loaded including Section J Revenue & Balance
  [✓] [RATING-22] Alertmanager Rules: 5 declarative charging alert rules active in Prometheus

═══════════════════════════════════════════════════════════════════════
  Phase 5.5 Rating & Balance Verification Summary: 22 Passed, 0 Failed
═══════════════════════════════════════════════════════════════════════
  >>> All Phase 5.5 Telecom Rating & Balance Management Tests Passed! <<<
```
