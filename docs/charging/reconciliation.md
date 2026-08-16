# Phase 5.5 — Financial Reconciliation & Audit Framework

## 1. Reconciliation Overview

Telecom revenue assurance mandates strict mathematical and relational integrity across usage generation, rating rules, balance ledgers, and reporting tables.

---

## 2. Formal Invariants Checked

The reconciliation engine (`src/charging/reconciliation.py`) continuously verifies five fundamental invariants:

### Invariant 1: Conservation of Account Equity
For every account $A_i \in \text{charging\_accounts}$:

$$\text{Available}(A_i) + \text{Reserved}(A_i) \equiv \sum_{t \in \text{Tx}(A_i)} \text{amount}(t)$$

Any variance exceeding $\pm 0.001\text{ LAB}$ flags an immediate integrity anomaly.

### Invariant 2: Idempotent Single-Charge Guarantee
No source usage record ID ($\text{source\_record\_id}$) may appear more than once in `rated_usage` or have multiple corresponding `CHARGE` transactions.

$$\forall s \in \text{UsageRecords}: \quad \text{Count}(\text{CHARGE}(s)) \le 1$$

### Invariant 3: Aggregate Cash Reconciliation

$$\sum \text{TOPUP Amounts} - \sum |\text{CHARGE Amounts}| \equiv \sum \text{Available Balances} + \sum \text{Reserved Balances}$$

### Invariant 4: CDR Rating Coverage
Verifies that all completed Kamailio SQLite CDRs are accounted for in `rated_usage`. Any unrated backlog is measured and exposed as `charging_usage_unrated_total`.

### Invariant 5: Transaction Ledger Sequential Continuity
Ensures that for all transactions on an account, $\text{balance\_before}(t_{k+1}) = \text{balance\_after}(t_k)$.

---

## 3. Running Reconciliation

```bash
python3 scripts/rating-engine.py reconcile
```

### 3.1 Golden Baseline Audit Output (Frozen Snapshot)
```text
═══════════════════════════════════════════════════════════════
  Telecom Rating & Balance Reconciliation Audit Report
═══════════════════════════════════════════════════════════════
  Reconciliation Status:   ✓ PASS
  Accounts Audited:        4
  Total Available Balance: 88.1300 LAB
  Total Reserved Balance:  0.0000 LAB
  Total Consumed Balance:  16.8900 LAB
  Total Top-up Credits:    105.0200 LAB
  Total Revenue Charged:   16.8900 LAB
  Rated CDRs Ingested:     108 / 108 (0 unrated)
  Anomalies Detected:      0
═══════════════════════════════════════════════════════════════
```

$$\text{Available } (88.1300\text{ LAB}) + \text{Consumed } (16.8900\text{ LAB}) + \text{Reserved } (0.0000\text{ LAB}) = \text{Top-ups } (105.0200\text{ LAB})$$

> [!NOTE]
> **Golden Baseline vs Live Environment:** The figures above reflect the certified `phase5.5-golden` baseline snapshot immediately following ingestion of the 108-CDR dataset. In active laboratory deployments, manual test calls or recharges will dynamically update balances, while the fundamental invariant ($\text{Available} + \text{Consumed} + \text{Reserved} = \text{Top-ups}$) remains rigorously enforced ($0$ anomalies).
