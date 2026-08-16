# Erlang/OTP Telecom Revenue & Charging Service

High-performance, fault-tolerant Online Revenue & Charging Service implemented in Erlang/OTP for the `5G-IMS-Lab` telecommunications reference environment.

---

## 1. Overview & Architecture

The service provides carrier-grade rating, balance reservation, and accounting capabilities:
- **Root Supervisor (`charging_service_sup`):** `one_for_one` supervision managing the core state server and HTTP listener.
- **Charging Server (`charging_server`):** Core `gen_server` managing multi-bucket balances (`balance_available`, `balance_reserved`, `balance_consumed`), reservation state machines, and transaction journals.
- **Deterministic Rating (`charging_rating`):** Pure functional rating engine executing 3GPP/BSS pricing arithmetic with duration ceiling rounding (`CEIL`).
- **Financial Reconciliation (`charging_reconcile`):** Formal mathematical auditor validating account equity and cash aggregate conservation ($0$ anomalies).
- **HTTP REST API (`charging_http` / `charging_http_handler`):** High-throughput Cowboy HTTP server on port `8085`.

---

## 2. Quick Start & Build

```bash
# 1. Compile application and dependencies
rebar3 compile

# 2. Run EUnit test suites (25 tests)
rebar3 eunit

# 3. Start interactive shell
rebar3 shell

# 4. Or run consolidated Phase 5.6 verification harness
bash ../../scripts/verify-erlang-charging.sh
```

---

## 3. REST API Reference

Base URL: `http://127.0.0.1:8085`

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Service health and OTP runtime information |
| `GET` | `/metrics` | JSON telemetry and operational counters |
| `GET` | `/v1/accounts` | List all provisioned subscriber accounts |
| `GET` | `/v1/accounts/:id/balance` | Query multi-bucket balance statement |
| `GET` | `/v1/accounts/:id/transactions` | Query full sequential transaction journal |
| `POST` | `/v1/accounts/:id/topup` | Top up subscriber balance |
| `GET` | `/v1/tariffs` | List all active tariff rules |
| `POST` | `/v1/rating/quote` | Rate quote for voice duration or data volume |
| `POST` | `/v1/charging/reserve` | Lock credit for an active call session |
| `POST` | `/v1/charging/consume` | Finalize session charge with unused credit refund |
| `POST` | `/v1/charging/refund` | Release unconsumed credit hold |
| `GET` | `/v1/reconciliation` | Run multi-point financial audit |
| `POST` | `/v1/fault/simulate` | Inject simulated crash for OTP supervisor recovery |

---

## 4. Documentation Links

- [Erlang/OTP Architecture Specification](../../docs/charging/erlang-otp-architecture.md)
- [REST API Reference & Examples](../../docs/charging/erlang-api.md)
- [Testing & Verification Matrix](../../docs/charging/erlang-testing.md)
