# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.6.0] — 2026-08-16 (Phase 5.6)

### Added
- **Erlang/OTP Telecom Revenue & Charging Service (`services/charging-erlang/`)**:
  - Production-grade OTP application (`charging_service`) with `one_for_one` root supervisor (`charging_service_sup`).
  - Core charging `gen_server` (`charging_server`) with state management, balance buckets, reservations, and auditable transaction logging.
  - Deterministic rating calculation module (`charging_rating`) with 100% mathematical parity to the Phase 5.5 reference.
  - Multi-point financial reconciliation module (`charging_reconcile`) verifying account equity, cash aggregate equality, and idempotency.
  - High-performance Cowboy HTTP REST API on port `8085` (`/health`, `/metrics`, `/v1/accounts`, `/v1/rating/quote`, `/v1/charging/reserve`, `/v1/charging/consume`, `/v1/charging/refund`, `/v1/reconciliation`).
  - Fault-tolerance and supervision recovery endpoints (`/v1/fault/simulate`).
  - Dedicated EUnit test suite (`rebar3 eunit` — 25/25 PASS).
  - Automated end-to-end verification harness (`scripts/verify-erlang-charging.sh` — 22/22 PASS).
  - Consolidated regression test baseline expanded to **192 / 192 Tests Passing (100% Green)**.

## [2.5.0] — 2026-08-16 (Phase 5.5)

### Added
- **Telecom Rating Engine Subsystem (`src/charging/`)**:
  - Deterministic, explainable rating engine for voice and data usage events.
  - Multi-PLMN domestic vs. roaming tariff classification (`domestic` vs `roaming_vplmn`).
  - Declarative configuration files: `configs/charging/rate-plans.yaml`, `configs/charging/tariffs.yaml`, `configs/charging/accounts.yaml`.
  - Configurable setup fees, duration rates, minimum billable units, and ceiling rounding (`CEIL`).
  - Zero-rated policy for Vo5G IMS signaling bearer (`dnn: ims`).
- **Prepaid Balance Manager & Transaction Journal**:
  - Three-bucket balance architecture (`balance_available`, `balance_reserved`, `balance_consumed`).
  - Session reservation lifecycle (`RESERVE` hold $\rightarrow$ `CONSUME` with refund $\rightarrow$ `RELEASE`).
  - Strict non-negative balance enforcement with automated rejection on insufficient funds.
  - ACID SQLite database (`data/charging.sqlite`) with WAL mode and foreign key constraints.
  - Immutable audit ledger (`charging_transactions`) tracking all credit and debit operations.
- **Financial Reconciliation Engine (`src/charging/reconciliation.py`)**:
  - Mathematical integrity audit proving $\sum \text{Ledger} \equiv \text{Available} + \text{Reserved}$.
  - Idempotent rating protection rejecting duplicate CDR ingestion without double-charging.
- **CLI Management Utility (`scripts/rating-engine.py`)**:
  - Rich operator subcommands: `init-db`, `rate-cdrs`, `rate-data`, `balance`, `top-up`, `history`, `reconcile`, `report`, `simulate-call`.
- **Full-Stack Observability & Incident Detection Integration**:
  - Extended `telecom-exporter` (`:9100`) with 12 Phase 5.5 metrics (`charging_revenue_total`, `charging_balance_available_total`, etc.).
  - Added **Section J: Telecom Rating, Prepaid Balance & Revenue Management** to Grafana Dashboard (`:30300`), expanding total dashboard panels to 53.
  - Added 5 declarative charging alert rules to Alertmanager (`telecom_rating_charging_alerts`).
- **Automated Verification Suite (`scripts/verify-rating.sh`)**:
  - 22 deterministic automated tests covering CLI, schema, rating, balance lifecycle, idempotency, reconciliation, and observability.
  - Total repository regression test count expanded to **169 / 169 Tests Passing (100% Green)**.

### Clarifications & Scope
- **Laboratory-Grade Offline Rating**: Designed for revenue engineering and tariff experimentation using SQLite CDRs; distinct from a 3GPP Rel-16 production online Charging Function (CHF / `Nchf`).

---

## [2.0.0] — 2026-08-15

### Added
- **Kamailio IMS Service Layer**:
  - P-CSCF with `hostNetwork` ingress (`10.46.0.1:5060`) and RFC 3327 Path routing.
  - I-CSCF with ClusterIP service and domain routing for `ims.lab`.
  - S-CSCF with memory-backed usrloc registrar and SQLite Digest MD5 authentication.
- **RTPEngine Media Proxy**:
  - SDP offer/answer endpoint rewriting to `10.46.0.1` and dynamic media relay ports (`20000-20100`).
  - NG protocol control over UDP port `22222`.
  - Automatic media session deletion upon BYE dialog teardown.
- **Multi-UE 5G SA & Multi-PLMN Support**:
  - Parallel multi-PLMN UE instances (`602030000000001` [PLMN 602/03] and `602040000000002` [PLMN 602/04]) with independent network namespaces.
  - Shared gNodeB multi-PLMN SIB1 broadcast and NGAP setup.
  - Concurrent dual PDU sessions (`internet` and `ims` DNNs).
  - Dynamic SMF IP address resolution across `10.45.0.0/16` and `10.46.0.0/16`.
- **Automated Verification Suite**:
  - `scripts/validate-ims-call.sh` (22/22 standalone IMS checks passed).
  - `scripts/test-ims-call.sh` (end-to-end SIP call & 25/25 bidirectional G.711 PCMU RTP stream test).
  - `scripts/verify-lab.sh` (full 55/55 5G SA + IMS regression suite passed).
- **Technical Documentation**:
  - `docs/IMS-CALL-FLOW-VALIDATION.md` detailing message traces, root-cause analyses, and Wireshark captures.

---

## [1.0.0] — 2026-07-18

### Added
- **5G SA Core Network** — Full Open5GS v2.8.0 deployment
  - AMF, SMF, UPF, NRF, AUSF, UDM, UDR, PCF, NSSF, BSF, SCP
- **RAN Simulator** — UERANSIM v3.3.0 (gNodeB + UE)
- **UE Registration** — Initial Registration with PLMN selection (001/01)
- **5G-AKA Authentication** — Authentication with Security Mode
- **PDU Session Establishment** — IPv4 session on DNN `internet` (SST:1, SD:0xFFFFFF)
- **User Plane** — GTP-U tunnel via TUN interface (`ogstun`, `10.45.0.x`)
- **Internet Connectivity** — End-to-end data path with NAT via UPF
- **Subscriber Management** — MongoDB with provisioned test subscriber
