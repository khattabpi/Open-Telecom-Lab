# Phase 5.6 — Erlang/OTP Telecom Charging Service REST API Reference

The Erlang/OTP Charging Service exposes a high-performance HTTP REST API on port `8085` managed by the **Cowboy HTTP Server**.

**Base URL:** `http://127.0.0.1:8085`

---

## 1. System & Health Endpoints

### 1.1 Health Check
- **Endpoint:** `GET /health`
- **Response:** `200 OK`
```json
{
  "otp_release": "25",
  "service": "charging-erlang",
  "status": "UP",
  "timestamp": "2026-08-16T13:16:56Z",
  "version": "1.0.0"
}
```

### 1.2 Telemetry & Metrics
- **Endpoint:** `GET /metrics`
- **Response:** `200 OK`
```json
{
  "active_accounts_count": 4,
  "operations_breakdown": {
    "balance_inquiry": 15,
    "rating_quote": 8,
    "reservation_hold": 5,
    "reservation_consume": 3
  },
  "service": "charging-erlang",
  "status": "HEALTHY",
  "total_available_balance": 88.13,
  "total_reserved_balance": 0.0,
  "total_revenue_charged": 16.89,
  "total_transactions_count": 12,
  "uptime_seconds": 128
}
```

---

## 2. Account & Balance Management

### 2.1 Get Subscriber Balance
- **Endpoint:** `GET /v1/accounts/:account_id/balance`
- **Example:** `GET /v1/accounts/acc-ue3/balance`
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue3",
  "balance_available": 30.0,
  "balance_consumed": 0.0,
  "balance_reserved": 0.0,
  "currency": "LAB",
  "imsi": "602030000000003",
  "msisdn": "+201000000003",
  "name": "UE3 Roaming Subscriber",
  "plmn": "602/03",
  "rate_plan": "premium-roaming",
  "serving_plmn": "218/90",
  "sip_uri": "sip:ue3@ims.lab",
  "status": "ACTIVE"
}
```

### 2.2 Account Top-Up
- **Endpoint:** `POST /v1/accounts/:account_id/topup`
- **Payload:**
```json
{
  "amount": 20.0,
  "description": "Retail Recharge Voucher"
}
```
- **Response:** `200 OK`

### 2.3 View Account Transaction History
- **Endpoint:** `GET /v1/accounts/:account_id/transactions`
- **Example:** `GET /v1/accounts/acc-ue3/transactions`
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue3",
  "count": 3,
  "transactions": [
    {
      "amount": 30.0,
      "balance_after": 30.0,
      "balance_before": 0.0,
      "created_at": "2026-08-16T13:16:56Z",
      "description": "Initial subscriber account credit",
      "reference_id": "init",
      "reference_type": "seed",
      "transaction_id": "tx-init-acc-ue3",
      "transaction_type": "TOPUP"
    },
    {
      "amount": 0.0,
      "balance_after": 29.5,
      "balance_before": 30.0,
      "description": "Session reservation hold (0.5000 LAB)",
      "reference_id": "sess-ue3-01",
      "reference_type": "reservation",
      "transaction_id": "tx-res-12",
      "transaction_type": "RESERVE"
    },
    {
      "amount": -0.5,
      "balance_after": 29.5,
      "balance_before": 30.0,
      "description": "Consumed reservation: charge for voice (0.5000 LAB)",
      "reference_id": "sess-ue3-01",
      "reference_type": "rated_usage",
      "transaction_id": "tx-cons-14",
      "transaction_type": "CHARGE"
    }
  ]
}
```

---

## 3. Rating & Pricing Quotation

### 3.1 Quote Usage Rating
- **Endpoint:** `POST /v1/rating/quote`
- **Request (UE3 Roaming Voice, 10s):**
```json
{
  "account_id": "acc-ue3",
  "destination": "roaming_vplmn",
  "duration": 10.0,
  "service_type": "voice"
}
```
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue3",
  "billable_units": 10,
  "currency": "LAB",
  "destination_type": "roaming_vplmn",
  "explanation": "Rated under tariff-premium-roaming-voice (voice/roaming_vplmn): setup 0.1000 LAB + 10 units @ 0.0400 LAB/1 units = 0.5000 LAB",
  "service_type": "voice",
  "setup_charge": 0.1,
  "source_units": 10.0,
  "tariff_id": "tariff-premium-roaming-voice",
  "total_charge": 0.5,
  "usage_charge": 0.4
}
```

---

## 4. Prepaid Session Credit Control

### 4.1 Reserve Session Balance
- **Endpoint:** `POST /v1/charging/reserve`
- **Payload:**
```json
{
  "account_id": "acc-ue3",
  "estimated_amount": 0.50,
  "service_type": "voice",
  "session_id": "call-sess-99"
}
```
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue3",
  "available_balance": 29.5,
  "currency": "LAB",
  "reservation_id": "res-22",
  "reserved_amount": 0.5,
  "reserved_balance": 0.5,
  "session_id": "call-sess-99",
  "status": "ACTIVE"
}
```

### 4.2 Consume Session Reservation
- **Endpoint:** `POST /v1/charging/consume`
- **Payload:**
```json
{
  "account_id": "acc-ue3",
  "actual_charge": 0.50,
  "session_id": "call-sess-99"
}
```
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue3",
  "actual_charge": 0.5,
  "available_balance": 29.5,
  "consumed_balance": 0.5,
  "currency": "LAB",
  "refund_amount": 0.0,
  "reserved_balance": 0.0,
  "session_id": "call-sess-99",
  "status": "CONSUMED"
}
```

### 4.3 Refund / Release Reservation Hold
- **Endpoint:** `POST /v1/charging/refund`
- **Payload:**
```json
{
  "account_id": "acc-ue1",
  "session_id": "call-sess-cancel"
}
```
- **Response:** `200 OK`
```json
{
  "account_id": "acc-ue1",
  "available_balance": 50.0,
  "currency": "LAB",
  "refunded_amount": 2.0,
  "reserved_balance": 0.0,
  "session_id": "call-sess-cancel",
  "status": "RELEASED"
}
```

---

## 5. Financial Reconciliation

- **Endpoint:** `GET /v1/reconciliation`
- **Response:** `200 OK`
```json
{
  "accounts_audited": 4,
  "anomalies": [],
  "anomalies_count": 0,
  "status": "PASS",
  "total_available": 88.13,
  "total_consumed": 16.89,
  "total_reserved": 0.0,
  "total_topups": 105.02
}
```

---

## 6. Fault Simulation & Supervision Test

- **Endpoint:** `POST /v1/fault/simulate`
- **Response:** `200 OK`
```json
{
  "message": "Simulated worker fault injected. Supervisor will restart charging_server."
}
```
