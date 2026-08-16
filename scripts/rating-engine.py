#!/usr/bin/env python3
# ==============================================================================
# rating-engine.py - 5G-IMS-Lab Phase 5.5 Telecom Rating & Balance Management CLI
#
# Commands:
#   init-db                  Initialize schema and seed rate plans, tariffs, accounts
#   rate-cdrs                Fetch pending Kamailio IMS CDRs, rate and debit accounts
#   rate-data                Fetch 5G user-plane data usage, rate and debit accounts
#   balance <account_id>     Display available, reserved, and consumed balance
#   top-up <account_id> <amt>Add credit to prepaid account with transaction logging
#   history <account_id>     Display full auditable transaction ledger
#   reconcile                Run comprehensive financial & relational reconciliation
#   report                   Generate operator-level revenue and charging report
#   explain <cdr_id>         Display step-by-step rating breakdown for a CDR
#   simulate-call            Simulate reserve/consume lifecycle for a call
# ==============================================================================

import argparse
import json
import os
import sys
import subprocess
from typing import Dict, Any, List

# Ensure src is in python path
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_ROOT)

from src.charging import (
    Database, RatingEngine, BalanceManager, ReconciliationEngine,
    UsageEvent, RatedEvent, Transaction, Account
)

def get_db():
    return Database()

def cmd_init_db(args):
    db = get_db()
    db.seed_default_configurations(force_reload=args.force)
    print("✓ Charging database schema initialized and default rate plans, tariffs & accounts seeded.")

def fetch_kamailio_cdrs() -> List[Dict[str, Any]]:
    """Fetches CDRs from Kamailio S-CSCF pod or local SQLite DB."""
    cmd = """kubectl -n ims exec deploy/kamailio-scscf -c scscf 2>/dev/null -- python3 -c "
import sqlite3, json
try:
    con = sqlite3.connect('/etc/kamailio/db/kamailio.sqlite')
    con.row_factory = sqlite3.Row
    rows = con.execute('SELECT id, callid, caller, callee, start_time, end_time, duration, sip_code, sip_reason FROM cdrs ORDER BY id ASC').fetchall()
    print(json.dumps([dict(r) for r in rows]))
except Exception as e:
    print('[]')
" """
    try:
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
        if out:
            return json.loads(out)
    except Exception:
        pass
    return []

def cmd_rate_cdrs(args):
    db = get_db()
    re = RatingEngine(db)
    bm = BalanceManager(db)
    
    cdrs = fetch_kamailio_cdrs()
    if not cdrs:
        print("No Kamailio CDRs found (or pod unreachable).")
        return

    print(f"Ingesting {len(cdrs)} Kamailio CDRs for rating...")
    rated_count = 0
    skipped_count = 0
    error_count = 0
    total_charged_session = 0.0

    print("-----------------------------------------------------------------------------------------------")
    printf_fmt = "%-4s %-20s %-16s %-16s %-6s %-14s %-10s %-10s\n"
    print(printf_fmt % ("ID", "Call-ID", "Caller", "Callee", "Dur", "Destination", "Charge", "Status"))
    print("-----------------------------------------------------------------------------------------------")

    for cdr in cdrs:
        cdr_id_str = f"cdr-{cdr['id']}-{cdr['callid'][:12]}"
        usage_event = UsageEvent(
            id=cdr_id_str,
            source="kamailio_cdr",
            service_type="voice",
            caller_id=cdr["caller"],
            caller_uri=cdr["caller"],
            callee_uri=cdr["callee"],
            duration_seconds=float(cdr["duration"]),
            start_time=cdr["start_time"],
            end_time=cdr["end_time"],
            sip_code=int(cdr["sip_code"]),
            sip_reason=cdr["sip_reason"]
        )

        rated = re.rate_event(usage_event)
        if rated.rating_status != "RATED":
            print(printf_fmt % (cdr["id"], cdr["callid"][:18]+"..", cdr["caller"].replace("sip:",""), cdr["callee"].replace("sip:",""), f"{cdr['duration']}s", "N/A", "0.0000", rated.rating_status))
            error_count += 1
            continue

        success, msg, tx = bm.debit_account(rated.account_id, rated)
        status_label = "RATED"
        if "Idempotent" in msg:
            status_label = "EXISTING"
            skipped_count += 1
        elif success:
            rated_count += 1
            total_charged_session += rated.total_charge
        else:
            status_label = "REJECTED"
            error_count += 1

        print(printf_fmt % (
            cdr["id"], cdr["callid"][:18]+"..",
            cdr["caller"].replace("sip:",""), cdr["callee"].replace("sip:",""),
            f"{cdr['duration']}s", rated.destination_type,
            f"{rated.total_charge:.4f} {rated.currency}", status_label
        ))

    print("-----------------------------------------------------------------------------------------------")
    print(f"Rating Summary: {rated_count} newly rated, {skipped_count} already rated (idempotent), {error_count} rejected.")
    print(f"Total Session Revenue Generated: {total_charged_session:.4f} LAB")

def fetch_netns_data_usage() -> List[Dict[str, Any]]:
    """Fetches real netns data bytes."""
    cmd = r"""sudo python3 -c "
import subprocess, re, json
ues = [
    {'imsi': '602030000000001', 'plmn': '602/03'},
    {'imsi': '602040000000002', 'plmn': '602/04'},
    {'imsi': '602030000000003', 'plmn': '218/90'}
]
res = []
for ue in ues:
    for dnn in ['internet', 'ims']:
        ns = f'ueransim-{ue[\"imsi\"]}-{dnn}-psi1' if dnn=='internet' else f'ueransim-{ue[\"imsi\"]}-{dnn}-psi2'
        out = subprocess.run(f'ip netns exec {ns} ip -s link show uesimtun0 2>/dev/null', shell=True, capture_output=True, text=True).stdout
        rx_m = re.search(r'RX:\s+bytes\s+packets[^\n]+\n\s+(\d+)', out)
        tx_m = re.search(r'TX:\s+bytes\s+packets[^\n]+\n\s+(\d+)', out)
        if rx_m and tx_m:
            res.append({
                'imsi': ue['imsi'], 'plmn': ue['plmn'], 'dnn': dnn,
                'rx_bytes': int(rx_m.group(1)), 'tx_bytes': int(tx_m.group(1))
            })
print(json.dumps(res))
" 2>/dev/null || echo '[]'"""
    try:
        out = subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()
        if out:
            return json.loads(out)
    except Exception:
        pass
    return []

def cmd_rate_data(args):
    db = get_db()
    re = RatingEngine(db)
    bm = BalanceManager(db)

    data_records = fetch_netns_data_usage()
    if not data_records:
        print("No active network namespace data counters found.")
        return

    print("-----------------------------------------------------------------------------------------------")
    printf_fmt = "%-18s %-12s %-10s %-14s %-12s %-10s %-10s\n"
    print(printf_fmt % ("IMSI", "PLMN", "DNN", "Total Bytes", "Destination", "Charge", "Status"))
    print("-----------------------------------------------------------------------------------------------")

    total_data_revenue = 0.0
    for r in data_records:
        total_bytes = r["rx_bytes"] + r["tx_bytes"]
        # Batch usage id
        usage_id = f"data-usage-{r['imsi']}-{r['dnn']}-b1"
        event = UsageEvent(
            id=usage_id,
            source="netns_data",
            service_type="data",
            caller_id=r["imsi"],
            origin_plmn=r["plmn"],
            dnn=r["dnn"],
            bytes_uploaded=r["tx_bytes"],
            bytes_downloaded=r["rx_bytes"]
        )

        rated = re.rate_event(event)
        if rated.rating_status == "RATED":
            success, msg, tx = bm.debit_account(rated.account_id, rated)
            status_label = "RATED" if success else ("EXISTING" if "Idempotent" in msg else "REJECTED")
            if success and "Idempotent" not in msg:
                total_data_revenue += rated.total_charge
            print(printf_fmt % (
                r["imsi"], r["plmn"], r["dnn"], f"{total_bytes} B",
                rated.destination_type, f"{rated.total_charge:.4f} {rated.currency}", status_label
            ))

    print("-----------------------------------------------------------------------------------------------")
    print(f"Data Usage Rating Complete. Total Data Revenue: {total_data_revenue:.4f} LAB")

def cmd_balance(args):
    bm = BalanceManager(get_db())
    acc = bm.get_account(args.account_id)
    if not acc:
        print(f"Account '{args.account_id}' not found.")
        sys.exit(1)

    print("═══════════════════════════════════════════════════════════════")
    print(f"  Prepaid Account Statement: {acc.name}")
    print("═══════════════════════════════════════════════════════════════")
    print(f"  Account ID:        {acc.id}")
    print(f"  IMSI / SUPI:       {acc.imsi}")
    print(f"  SIP URI:           {acc.sip_uri}")
    print(f"  PLMN:              {acc.plmn}")
    print(f"  Rate Plan:         {acc.rate_plan}")
    print(f"  Account Status:    {acc.status}")
    print("───────────────────────────────────────────────────────────────")
    print(f"  Available Balance: {acc.balance_available:.4f} {acc.currency}")
    print(f"  Reserved Balance:  {acc.balance_reserved:.4f} {acc.currency}")
    print(f"  Total Balance:     {acc.total_balance:.4f} {acc.currency}")
    print(f"  Consumed to Date:  {acc.balance_consumed:.4f} {acc.currency}")
    print("═══════════════════════════════════════════════════════════════")

def cmd_topup(args):
    bm = BalanceManager(get_db())
    success, msg, tx = bm.topup_account(args.account_id, float(args.amount), args.description)
    if success:
        print(f"✓ {msg} (Transaction ID: {tx.id})")
    else:
        print(f"✗ Failed to top up: {msg}")
        sys.exit(1)

def cmd_history(args):
    bm = BalanceManager(get_db())
    txs = bm.get_account_transactions(args.account_id)
    if not txs:
        print(f"No transactions found for account '{args.account_id}'.")
        return

    print("═══════════════════════════════════════════════════════════════════════════════════════════════")
    print(f"  Transaction Journal & Ledger for Account: {args.account_id}")
    print("═══════════════════════════════════════════════════════════════════════════════════════════════")
    printf_fmt = "%-20s %-10s %-12s %-12s %-12s %-20s %-25s\n"
    print(printf_fmt % ("TX ID", "Type", "Amount", "Bal Before", "Bal After", "Timestamp", "Description"))
    print("───────────────────────────────────────────────────────────────────────────────────────────────")
    for t in txs:
        amt_str = f"{t.amount:+.4f}"
        print(printf_fmt % (t.id, t.transaction_type, amt_str, f"{t.balance_before:.4f}", f"{t.balance_after:.4f}", t.created_at[:19], t.description[:25]))
    print("═══════════════════════════════════════════════════════════════════════════════════════════════")

def cmd_reconcile(args):
    rec = ReconciliationEngine(get_db())
    cdrs = fetch_kamailio_cdrs()
    report = rec.run_reconciliation(kamailio_cdrs_count=len(cdrs))

    if args.json:
        print(json.dumps(report, indent=2))
        sys.exit(0 if report["reconciled"] else 1)

    print("═══════════════════════════════════════════════════════════════")
    print("  Telecom Rating & Balance Reconciliation Audit Report")
    print("═══════════════════════════════════════════════════════════════")
    print(f"  Reconciliation Status:   {'✓ PASS' if report['reconciled'] else '✗ FAIL'}")
    print(f"  Accounts Audited:        {report['accounts_audited']}")
    print(f"  Total Available Balance: {report['total_available_balance']:.4f} LAB")
    print(f"  Total Reserved Balance:  {report['total_reserved_balance']:.4f} LAB")
    print(f"  Total Consumed Balance:  {report['total_consumed_balance']:.4f} LAB")
    print(f"  Total Top-up Credits:    {report['total_topup_credit']:.4f} LAB")
    print(f"  Total Revenue Charged:   {report['total_revenue_charged']:.4f} LAB")
    print(f"  Rated CDRs Ingested:     {report['rated_cdrs_count']} / {len(cdrs)} ({report['unrated_cdrs_count']} unrated)")
    print(f"  Anomalies Detected:      {report['anomaly_count']}")
    
    if report["anomalies"]:
        print("───────────────────────────────────────────────────────────────")
        print("  Detected Anomalies:")
        for a in report["anomalies"]:
            print(f"    - {a}")

    print("═══════════════════════════════════════════════════════════════")
    sys.exit(0 if report["reconciled"] else 1)

def cmd_report(args):
    db = get_db()
    with db.get_connection() as con:
        cur = con.cursor()
        cur.execute("SELECT COUNT(*), COALESCE(SUM(balance_available),0), COALESCE(SUM(balance_consumed),0) FROM charging_accounts;")
        acc_cnt, total_avail, total_consumed = cur.fetchone()

        cur.execute("SELECT COUNT(*), COALESCE(SUM(total_charge),0) FROM rated_usage WHERE rating_status = 'RATED';")
        rated_cnt, total_revenue = cur.fetchone()

        cur.execute("SELECT destination_type, COUNT(*), COALESCE(SUM(total_charge),0) FROM rated_usage WHERE rating_status = 'RATED' GROUP BY destination_type;")
        dest_stats = {r[0]: {"count": r[1], "revenue": r[2]} for r in cur.fetchall()}

        cur.execute("SELECT service_type, COUNT(*), COALESCE(SUM(total_charge),0) FROM rated_usage WHERE rating_status = 'RATED' GROUP BY service_type;")
        srv_stats = {r[0]: {"count": r[1], "revenue": r[2]} for r in cur.fetchall()}

    print("═══════════════════════════════════════════════════════════════")
    print("  5G-IMS-Lab Executive Revenue & Rating Ledger Summary")
    print("═══════════════════════════════════════════════════════════════")
    print(f"  Active Accounts:         {acc_cnt}")
    print(f"  Total Prepaid Reserve:   {total_avail:.4f} LAB")
    print(f"  Total Cumulative Spend:  {total_consumed:.4f} LAB")
    print(f"  Total Rated Events:      {rated_cnt}")
    print(f"  Total Billed Revenue:    {total_revenue:.4f} LAB")
    print("───────────────────────────────────────────────────────────────")
    print("  Revenue by Service:")
    for s, data in srv_stats.items():
        print(f"    - {s.upper():<8}: {data['count']:<4} events | {data['revenue']:.4f} LAB")
    print("  Revenue by Destination:")
    for d, data in dest_stats.items():
        print(f"    - {d:<14}: {data['count']:<4} events | {data['revenue']:.4f} LAB")
    print("═══════════════════════════════════════════════════════════════")

def cmd_simulate_call(args):
    db = get_db()
    re = RatingEngine(db)
    bm = BalanceManager(db)

    print(f"Simulating Call Lifecycle: {args.caller} -> {args.callee} (duration: {args.duration}s)...")
    
    # 1. Estimate & Reserve
    acc = bm.get_account(args.caller)
    if not acc:
        print(f"Account for caller '{args.caller}' not found.")
        sys.exit(1)

    est_amount = 0.50 # Estimate 0.50 credits for session
    print(f"1. Reserving estimated credit: {est_amount:.2f} {acc.currency} on account '{acc.id}'...")
    success, msg, res = bm.reserve_balance(acc.id, est_amount, "sess-sim-001", "voice")
    if not success:
        print(f"✗ Reservation failed: {msg}")
        sys.exit(1)
    print(f"✓ {msg}")

    # 2. Rate Actual Usage
    usage = UsageEvent(
        id="sim-call-001",
        source="simulation",
        service_type="voice",
        caller_id=acc.id,
        caller_uri=acc.sip_uri,
        callee_uri=args.callee,
        duration_seconds=float(args.duration)
    )
    rated = re.rate_event(usage)
    print(f"2. Rating Call: Actual cost = {rated.total_charge:.4f} {rated.currency}")
    print(f"   Explanation: {rated.rating_explanation}")

    # 3. Consume Reservation
    success, msg, tx = bm.consume_reservation(res.id, rated.total_charge, usage.id)
    if success:
        print(f"3. Consumed Reservation: ✓ {msg}")
    else:
        print(f"✗ Consumption failed: {msg}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="5G-IMS-Lab Telecom Rating & Balance Management CLI")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # init-db
    p_init = subparsers.add_parser("init-db", help="Initialize database schema and seed rate plans")
    p_init.add_argument("--force", action="store_true", help="Force re-seed tariffs and plans")

    # rate-cdrs
    subparsers.add_parser("rate-cdrs", help="Rate pending Kamailio CDRs")

    # rate-data
    subparsers.add_parser("rate-data", help="Rate 5G user plane data usage")

    # balance
    p_bal = subparsers.add_parser("balance", help="Check account balance")
    p_bal.add_argument("account_id", help="Account ID, IMSI, or SIP URI")

    # top-up
    p_top = subparsers.add_parser("top-up", help="Top up account balance")
    p_top.add_argument("account_id", help="Account ID, IMSI, or SIP URI")
    p_top.add_argument("amount", type=float, help="Top-up amount")
    p_top.add_argument("--description", default="Prepaid top-up", help="Transaction description")

    # history
    p_hist = subparsers.add_parser("history", help="Show account transaction ledger")
    p_hist.add_argument("account_id", help="Account ID, IMSI, or SIP URI")

    # reconcile
    p_rec = subparsers.add_parser("reconcile", help="Run financial reconciliation")
    p_rec.add_argument("--json", action="store_true", help="Output raw JSON")

    # report
    subparsers.add_parser("report", help="Show executive revenue and rating report")

    # simulate-call
    p_sim = subparsers.add_parser("simulate-call", help="Simulate call reservation and consumption")
    p_sim.add_argument("--caller", default="acc-ue1", help="Caller account ID or SIP URI")
    p_sim.add_argument("--callee", default="sip:ue3@ims.lab", help="Callee SIP URI")
    p_sim.add_argument("--duration", type=float, default=2.0, help="Call duration in seconds")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmds = {
        "init-db": cmd_init_db,
        "rate-cdrs": cmd_rate_cdrs,
        "rate-data": cmd_rate_data,
        "balance": cmd_balance,
        "top-up": cmd_topup,
        "history": cmd_history,
        "reconcile": cmd_reconcile,
        "report": cmd_report,
        "simulate-call": cmd_simulate_call
    }
    cmds[args.command](args)

if __name__ == "__main__":
    main()
