# Phase 5.5 — Operator Manual & CLI Reference

## 1. CLI Utility Overview

The primary management interface for Phase 5.5 is `scripts/rating-engine.py`.

```text
usage: rating-engine.py [-h] {init-db,rate-cdrs,rate-data,balance,top-up,history,reconcile,report,simulate-call} ...
```

---

## 2. Command Reference

### 2.1 Database Initialization & Tariff Seeding
Initializes SQLite schema, applies indexes, and loads declarative rate plans, tariffs, and accounts from `configs/charging/`:
```bash
python3 scripts/rating-engine.py init-db
# Force re-seed:
python3 scripts/rating-engine.py init-db --force
```

### 2.2 Rate Pending Kamailio Voice CDRs
Extracts unrated Call Detail Records from the Kamailio S-CSCF SQLite database, applies domestic/roaming rating rules, and debits caller accounts:
```bash
python3 scripts/rating-engine.py rate-cdrs
```

### 2.3 Rate 5G User-Plane Data Usage
Extracts network namespace kernel GTP-U byte counters per SUPI and DNN, rates internet/IMS data, and debits accounts:
```bash
sudo python3 scripts/rating-engine.py rate-data
```

### 2.4 Subscriber Balance Statement
Displays available, reserved, consumed, and total balances for an account:
```bash
python3 scripts/rating-engine.py balance acc-ue1
python3 scripts/rating-engine.py balance sip:ue2@ims.lab
```

### 2.5 Prepaid Account Top-Up
Adds liquid credit to a subscriber's available balance with an auditable transaction entry:
```bash
python3 scripts/rating-engine.py top-up acc-ue1 20.00 --description "Retail Topup Card"
```

### 2.6 View Transaction Journal & Ledger
Inspects the full chronological audit ledger for an account:
```bash
python3 scripts/rating-engine.py history acc-ue1
```

### 2.7 Executive Revenue & Billing Report
Displays operator-level revenue aggregation across services and destinations:
```bash
python3 scripts/rating-engine.py report
```

### 2.8 Financial Reconciliation Audit
Executes mathematical and relational reconciliation:
```bash
python3 scripts/rating-engine.py reconcile
python3 scripts/rating-engine.py reconcile --json
```

### 2.9 Simulate Call Session Lifecycle
Simulates a real-time call lifecycle with reservation hold, rating calculation, and reservation consumption:
```bash
# Domestic Call Simulation (UE1 -> UE2, 10s):
python3 scripts/rating-engine.py simulate-call --caller acc-ue1 --callee sip:ue2@ims.lab --duration 10.0

# Roaming Call Simulation (UE3 in VPLMN 218/90 -> UE1, 10s):
python3 scripts/rating-engine.py simulate-call --caller acc-ue3 --callee sip:ue1@ims.lab --duration 10.0
```
