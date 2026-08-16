# Erlang/OTP Telecom Revenue & Charging Service

High-performance, carrier-grade Online Revenue & Charging Service implemented in Erlang/OTP for the `5G-IMS-Lab` telecommunications reference environment.

---

## 1. Overview & Architecture

The service provides real-time rating, credit reservation, balance debiting, and accounting capabilities for 5G Standalone and IMS Vo5G voice sessions:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 charging_service_sup                                   │
│                            (OTP one_for_one Supervisor)                                │
└───────────────────────────────────────────┬────────────────────────────────────────────┘
                                            │
                    ┌───────────────────────┴───────────────────────┐
                    ▼                                               ▼
┌───────────────────────────────────────┐       ┌───────────────────────────────────────┐
│            charging_server            │       │             charging_http             │
│        (Core OTP gen_server)          │       │    (Cowboy REST API Listener :8085)   │
│                                       │       └───────────────────┬───────────────────┘
│  • Multi-Bucket Balance Accounts      │                           │
│  • Credit Reservation State Machine   │                           ▼
│  • Double-Entry Transaction Ledger    │       ┌───────────────────────────────────────┐
│  • Single-Charge Idempotency Engine   │       │         charging_http_handler         │
│  • Pure Deterministic Rating Engine   │       │   (Routing, JSON Encoding & Decoding) │
│  • Mathematical Reconciliation Audit  │       └───────────────────────────────────────┘
└───────────────────────────────────────┘
```

- **Root Supervisor (`charging_service_sup`):** `one_for_one` supervision managing the core state server and HTTP listener.
- **Charging Server (`charging_server`):** Core `gen_server` managing multi-bucket balances (`balance_available`, `balance_reserved`, `balance_consumed`), reservation state machines, and transaction journals.
- **Deterministic Rating (`charging_rating`):** Pure functional rating engine executing 3GPP/BSS pricing arithmetic with duration ceiling rounding (`CEIL`).
- **Financial Reconciliation (`charging_reconcile`):** Formal mathematical auditor validating account equity and cash aggregate conservation ($0$ anomalies).
- **HTTP REST API (`charging_http` / `charging_http_handler`):** High-throughput Cowboy HTTP server on port `8085`.

---

## 2. Subscriber Account & Rating Data Model

### Account Model
Every subscriber account maintains a multi-bucket balance structure:
- `balance_available`: Liquid funds available for reservation or direct debit.
- `balance_reserved`: Funds locked in active in-flight call sessions.
- `balance_consumed`: Cumulative rated charges successfully debited.

| Account ID | Subscriber Name | IMSI | Home PLMN | Serving PLMN | Rate Plan | Initial Balance |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `acc-ue1` | UE1 Domestic Subscriber | `602030000000001` | `602/03` | `602/03` | `standard-prepaid` | `50.0000 LAB` |
| `acc-ue2` | UE2 Domestic Subscriber | `602040000000002` | `602/04` | `602/04` | `standard-prepaid` | `25.0000 LAB` |
| `acc-ue3` | UE3 Roaming Subscriber | `602030000000003` | `602/03` | `218/90` | `premium-roaming` | `30.0000 LAB` |
| `acc-test-broke` | Zero Balance Test | `001010000000000` | `001/01` | `001/01` | `standard-prepaid` | `0.0200 LAB` |

### Roaming Charging Semantics
> [!IMPORTANT]
> **UE3 Home vs. Visited PLMN Distinction:**
> - **Home PLMN (HPLMN):** UE3 belongs to Egypt `602/03`. Its subscription credentials reside in the Home UDM/MongoDB database.
> - **Serving PLMN (VPLMN):** UE3 attaches via radio to `gNodeB-Visited` in Bosnia `218/90`.
> - **Rating Rule:** Because `serving_plmn` (`218/90`) $\neq$ `plmn` (`602/03`), the engine classifies the call as `roaming_vplmn` and applies tariff `tariff-premium-roaming-voice` (`setup_charge: 0.10 LAB`, `unit_rate: 0.04 LAB/s`).

---

## 3. REST API Reference (Cowboy `:8085`)

Base URL: `http://127.0.0.1:8085`

| Method | Endpoint | Description | Status Codes |
| :--- | :--- | :--- | :--- |
| `GET` | `/health` | Service health, OTP release, and timestamp | `200` |
| `GET` | `/metrics` | Operational counters and balances | `200` |
| `GET` | `/v1/accounts` | List all provisioned subscriber accounts | `200` |
| `GET` | `/v1/accounts/:id/balance` | Query multi-bucket balance statement | `200`, `404` |
| `GET` | `/v1/accounts/:id/transactions` | Query full sequential transaction journal | `200`, `404` |
| `POST` | `/v1/accounts/:id/topup` | Add credit to subscriber account | `200`, `400`, `404` |
| `GET` | `/v1/tariffs` | List all active tariff rules | `200` |
| `POST` | `/v1/rating/quote` | Rate quote for voice duration or data units | `200`, `400`, `404` |
| `POST` | `/v1/charging/events` | Direct rating & debit for completed call event | `200`, `400`, `402`, `404` |
| `POST` | `/v1/charging/reserve` | Lock credit for an active call session | `200`, `400`, `402`, `404`, `409` |
| `POST` | `/v1/charging/consume` | Finalize session charge with unused credit refund | `200`, `400`, `402`, `404` |
| `POST` | `/v1/charging/refund` | Release unconsumed credit hold | `200`, `400`, `404` |
| `GET` | `/v1/reconciliation` | Run multi-point financial audit | `200`, `500` |
| `POST` | `/v1/fault/simulate` | Inject simulated crash for OTP supervisor recovery | `200` |

---

## 4. IMS-to-Charging Integration Architecture

When an IMS call completes in [`scripts/test-ims-call.sh`](../../scripts/test-ims-call.sh):
1. SIP `INVITE` $\rightarrow$ `180 Ringing` $\rightarrow$ `200 OK` establishes the dialog.
2. Bidirectional RTP audio stream is verified (25/25 packets, 0% loss).
3. SIP `BYE` $\rightarrow$ `200 OK` terminates the session.
4. `test-ims-call.sh` notifies the Erlang Charging Service:

```bash
POST /v1/charging/events
Content-Type: application/json

{
  "call_id": "call-run-12345@10.46.0.22",
  "session_id": "call-run-12345@10.46.0.22",
  "caller": "sip:ue1@ims.lab",
  "callee": "sip:ue3@ims.lab",
  "account_id": "acc-ue3",
  "service_type": "voice",
  "duration": 10.0,
  "destination": "roaming_vplmn"
}
```

5. The Erlang Charging Server rates the call ($0.10 + 10 \times 0.04 = 0.5000\text{ LAB}$), debits `balance_available`, credits `balance_consumed`, records an immutable transaction in the journal, and returns `200 OK`.

---

## 5. Single-Charge Idempotency Guarantee

If a network retry or duplicate event arrives with the same `call_id` / `session_id`, `charging_server` checks the transaction journal:
- Detects existing `CHARGE` transaction with `reference_id == CallId`.
- Returns `{ "status": "EXISTING", "message": "Call already charged (idempotent)" }`.
- **No duplicate debit is made**, preserving ledger integrity and balance conservation.

---

## 6. Financial Reconciliation & Invariants

The service continuously enforces three mathematical accounting invariants:

1. **Conservation of Account Equity:**
   $$\text{Balance Available} + \text{Balance Reserved} = \sum \text{Transaction Amounts}$$
2. **Aggregate Cash Conservation:**
   $$\text{Total Available} + \text{Total Consumed} + \text{Total Reserved} \equiv \text{Total Topups}$$
3. **Single-Charge Idempotency:**
   Zero duplicate charge transaction IDs across the journal.

---

## 7. Manual Validation & Execution Procedure

### Lifecycle Management:
```bash
# Start background daemon
bash scripts/run-erlang-charging.sh start

# Check live service status & balances
bash scripts/run-erlang-charging.sh status

# Stop background daemon
bash scripts/run-erlang-charging.sh stop
```

### End-to-End Verification:
```bash
# 1. Check pre-call balance
curl -s http://127.0.0.1:8085/v1/accounts/acc-ue3/balance | jq .

# 2. Run real IMS Roaming Voice Call (UE1 -> UE3)
sudo bash scripts/test-ims-call.sh 1 3

# 3. Query post-call balance (Available: 29.5000 LAB, Consumed: 0.5000 LAB)
curl -s http://127.0.0.1:8085/v1/accounts/acc-ue3/balance | jq .

# 4. Inspect transaction journal
curl -s http://127.0.0.1:8085/v1/accounts/acc-ue3/transactions | jq .

# 5. Run formal reconciliation audit (status: PASS, anomalies: 0)
curl -s http://127.0.0.1:8085/v1/reconciliation | jq .
```

---

## 8. Expected Before / After Balances

| Subscriber Account | Call Scenario | Pre-Call Available | Rated Charge | Post-Call Available | Post-Call Consumed |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **`acc-ue3` (UE3 Roaming)** | UE1 $\rightarrow$ UE3 (10s Roaming) | `30.0000 LAB` | `0.5000 LAB` | `29.5000 LAB` | `0.5000 LAB` |
| **`acc-ue1` (UE1 Domestic)**| UE1 $\rightarrow$ UE2 (10s Domestic)| `50.0000 LAB` | `0.2500 LAB` | `49.7500 LAB` | `0.2500 LAB` |
| **`acc-ue3` (UE3 Roaming)** | UE3 $\rightarrow$ UE1 (10s Rev Roam)| `29.5000 LAB` | `0.5000 LAB` | `29.0000 LAB` | `1.0000 LAB` |

---

## 9. Testing & Quality Assurance

```bash
# Run unit tests (29 tests)
cd services/charging-erlang && rebar3 eunit

# Run full Phase 5.6 automated verification suite (24 tests)
bash scripts/verify-erlang-charging.sh
```
