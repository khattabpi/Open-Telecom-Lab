"""
Reconciliation & Audit Engine for Telecom Rating and Prepaid Balance Subsystem.
"""

from typing import Dict, Any, List
from .database import Database

class ReconciliationEngine:
    def __init__(self, db: Database = None):
        self.db = db or Database()

    def run_reconciliation(self, kamailio_cdrs_count: int = 0) -> Dict[str, Any]:
        """Runs comprehensive financial and relational reconciliation."""
        anomalies = []
        accounts_audited = 0
        total_balance_avail = 0.0
        total_balance_res = 0.0
        total_consumed = 0.0
        total_topups = 0.0
        total_charges = 0.0

        with self.db.get_connection() as con:
            cur = con.cursor()

            # 1. Audit Accounts vs Transaction Ledger
            cur.execute("SELECT * FROM charging_accounts;")
            accounts = cur.fetchall()
            accounts_audited = len(accounts)

            for acc in accounts:
                acc_id = acc["id"]
                avail = acc["balance_available"]
                res = acc["balance_reserved"]
                consumed = acc["balance_consumed"]
                total_balance_avail += avail
                total_balance_res += res
                total_consumed += consumed

                # Get all transactions for this account
                cur.execute("""
                SELECT transaction_type, amount, balance_before, balance_after 
                FROM charging_transactions 
                WHERE account_id = ? 
                ORDER BY rowid ASC;
                """, (acc_id,))
                txs = cur.fetchall()

                # Calculate sum of debits and credits
                net_ledger = sum(t["amount"] for t in txs)
                # Available + Reserved should equal net_ledger
                if abs((avail + res) - net_ledger) > 0.001:
                    anomalies.append(
                        f"Balance mismatch for account '{acc_id}': Available({avail}) + Reserved({res}) = {avail+res:.4f} != Net Ledger({net_ledger:.4f})"
                    )

            # 2. Check for Duplicate Rated Records
            cur.execute("""
            SELECT source_record_id, COUNT(*) as cnt 
            FROM rated_usage 
            GROUP BY source_record_id 
            HAVING cnt > 1;
            """)
            dup_records = cur.fetchall()
            for dup in dup_records:
                anomalies.append(f"Duplicate rated record detected: source_record_id='{dup['source_record_id']}' (count={dup['cnt']})")

            # 3. Check for Duplicate CHARGE Transactions for the same usage event
            cur.execute("""
            SELECT reference_id, COUNT(*) as cnt 
            FROM charging_transactions 
            WHERE reference_type = 'rated_usage' 
            GROUP BY reference_id 
            HAVING cnt > 1;
            """)
            dup_txs = cur.fetchall()
            for dtx in dup_txs:
                anomalies.append(f"Duplicate charge transaction detected: reference_id='{dtx['reference_id']}' (count={dtx['cnt']})")

            # 4. Check Aggregate Financials
            cur.execute("SELECT COALESCE(SUM(amount), 0) FROM charging_transactions WHERE transaction_type = 'TOPUP';")
            total_topups = cur.fetchone()[0]

            cur.execute("SELECT COALESCE(SUM(amount), 0) FROM charging_transactions WHERE transaction_type = 'CHARGE';")
            total_charges = abs(cur.fetchone()[0])

            # 5. Check CDR Coverage
            cur.execute("SELECT COUNT(*) FROM rated_usage WHERE usage_source = 'kamailio_cdr' AND rating_status = 'RATED';")
            rated_cdrs_count = cur.fetchone()[0]

            unrated_cdrs = max(0, kamailio_cdrs_count - rated_cdrs_count) if kamailio_cdrs_count > 0 else 0

        is_reconciled = (len(anomalies) == 0)

        return {
            "reconciled": is_reconciled,
            "status": "PASS" if is_reconciled else "FAIL",
            "accounts_audited": accounts_audited,
            "total_available_balance": round(total_balance_avail, 4),
            "total_reserved_balance": round(total_balance_res, 4),
            "total_consumed_balance": round(total_consumed, 4),
            "total_topup_credit": round(total_topups, 4),
            "total_revenue_charged": round(total_charges, 4),
            "rated_cdrs_count": rated_cdrs_count,
            "unrated_cdrs_count": unrated_cdrs,
            "anomaly_count": len(anomalies),
            "anomalies": anomalies
        }
