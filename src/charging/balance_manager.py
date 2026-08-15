"""
Prepaid Balance Manager and Transaction Journal for Telecom Charging.
"""

import uuid
import datetime
from typing import Optional, Dict, Any, List, Tuple
from .models import Account, Transaction, Reservation, RatedEvent
from .database import Database

class BalanceManager:
    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()

    def get_account(self, account_id: str) -> Optional[Account]:
        """Fetches account by ID, IMSI, or SIP URI."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("SELECT * FROM charging_accounts WHERE id = ? OR imsi = ? OR sip_uri = ?;", 
                        (account_id, account_id, account_id))
            row = cur.fetchone()
            if row:
                return Account(**dict(row))
        return None

    def topup_account(self, account_id: str, amount: float, description: str = "Prepaid top-up") -> Tuple[bool, str, Optional[Transaction]]:
        """Adds funds to subscriber's available balance with an auditable transaction."""
        if amount <= 0:
            return False, "Top-up amount must be strictly positive.", None

        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("SELECT * FROM charging_accounts WHERE id = ? OR imsi = ?;", (account_id, account_id))
            row = cur.fetchone()
            if not row:
                return False, f"Account '{account_id}' not found.", None
            
            acc = Account(**dict(row))
            bal_before = acc.balance_available
            bal_after = round(bal_before + amount, 4)
            now_str = datetime.datetime.utcnow().isoformat()
            tx_id = f"tx-topup-{uuid.uuid4().hex[:8]}"

            cur.execute("""
            UPDATE charging_accounts 
            SET balance_available = ?, updated_at = ?
            WHERE id = ?;
            """, (bal_after, now_str, acc.id))

            cur.execute("""
            INSERT INTO charging_transactions 
            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
            VALUES (?, ?, 'TOPUP', ?, ?, ?, 'manual', ?, ?, ?);
            """, (tx_id, acc.id, amount, bal_before, bal_after, tx_id, description, now_str))

            con.commit()
            
            tx = Transaction(
                id=tx_id, account_id=acc.id, transaction_type="TOPUP",
                amount=amount, balance_before=bal_before, balance_after=bal_after,
                reference_type="manual", reference_id=tx_id, description=description,
                created_at=now_str
            )
            return True, f"Successfully topped up {amount:.2f} {acc.currency}. New balance: {bal_after:.2f}", tx

    def debit_account(self, account_id: str, rated_event: RatedEvent) -> Tuple[bool, str, Optional[Transaction]]:
        """Debits account for a rated usage event with ACID transaction and idempotency protection."""
        amount = rated_event.total_charge
        with self.db.get_connection() as con:
            cur = con.cursor()

            # 1. Idempotency Check: Was this source record already charged?
            cur.execute("SELECT * FROM charging_transactions WHERE reference_type = 'rated_usage' AND reference_id = ?;", (rated_event.usage_id,))
            existing_tx = cur.fetchone()
            if existing_tx:
                return True, f"Idempotent: Usage event '{rated_event.usage_id}' already charged in transaction {existing_tx['id']}.", Transaction(**dict(existing_tx))

            # 2. Check Account
            cur.execute("SELECT * FROM charging_accounts WHERE id = ?;", (account_id,))
            row = cur.fetchone()
            if not row:
                return False, f"Account '{account_id}' not found.", None
            
            acc = Account(**dict(row))

            # 3. Check Balance
            if acc.balance_available < amount:
                now_str = datetime.datetime.utcnow().isoformat()
                # Record rejected rating in rated_usage
                cur.execute("""
                INSERT OR REPLACE INTO rated_usage
                (id, usage_source, source_record_id, account_id, service_type, destination_type, tariff_id, raw_quantity, billable_units, setup_charge, duration_charge, total_charge, currency, rating_status, rejection_reason, rating_explanation, created_at)
                VALUES (?, 'system', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'INSUFFICIENT_BALANCE', ?, ?, ?);
                """, (
                    rated_event.id, rated_event.usage_id, acc.id, rated_event.service_type,
                    rated_event.destination_type, rated_event.tariff_id, rated_event.raw_quantity,
                    rated_event.billable_units, rated_event.setup_charge, rated_event.duration_charge,
                    rated_event.total_charge, acc.currency,
                    f"Insufficient funds: available {acc.balance_available:.2f} < required {amount:.2f}",
                    rated_event.rating_explanation, now_str
                ))
                con.commit()
                return False, f"Insufficient balance: available {acc.balance_available:.2f} {acc.currency} < required {amount:.2f} {acc.currency}", None

            # 4. Perform Atomic Balance Deduction
            bal_before = acc.balance_available
            bal_after = round(bal_before - amount, 4)
            consumed_after = round(acc.balance_consumed + amount, 4)
            now_str = datetime.datetime.utcnow().isoformat()
            tx_id = f"tx-chg-{uuid.uuid4().hex[:8]}"

            cur.execute("""
            UPDATE charging_accounts
            SET balance_available = ?, balance_consumed = ?, updated_at = ?
            WHERE id = ?;
            """, (bal_after, consumed_after, now_str, acc.id))

            # 5. Insert Rated Usage Record
            cur.execute("""
            INSERT OR REPLACE INTO rated_usage
            (id, usage_source, source_record_id, account_id, service_type, destination_type, tariff_id, raw_quantity, billable_units, setup_charge, duration_charge, total_charge, currency, rating_status, rejection_reason, rating_explanation, created_at)
            VALUES (?, 'kamailio_cdr', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'RATED', NULL, ?, ?);
            """, (
                rated_event.id, rated_event.usage_id, acc.id, rated_event.service_type,
                rated_event.destination_type, rated_event.tariff_id, rated_event.raw_quantity,
                rated_event.billable_units, rated_event.setup_charge, rated_event.duration_charge,
                rated_event.total_charge, acc.currency, rated_event.rating_explanation, now_str
            ))

            # 6. Insert Transaction Record
            cur.execute("""
            INSERT INTO charging_transactions
            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
            VALUES (?, ?, 'CHARGE', ?, ?, ?, 'rated_usage', ?, ?, ?);
            """, (
                tx_id, acc.id, -amount, bal_before, bal_after,
                rated_event.usage_id,
                f"Charge for {rated_event.service_type} ({rated_event.destination_type}): {amount:.4f} {acc.currency}",
                now_str
            ))

            con.commit()

            tx = Transaction(
                id=tx_id, account_id=acc.id, transaction_type="CHARGE",
                amount=-amount, balance_before=bal_before, balance_after=bal_after,
                reference_type="rated_usage", reference_id=rated_event.usage_id,
                description=f"Charge for {rated_event.service_type}: {amount:.4f} {acc.currency}",
                created_at=now_str
            )
            return True, f"Charged {amount:.4f} {acc.currency}. Balance: {bal_after:.2f}", tx

    def reserve_balance(self, account_id: str, estimated_amount: float, session_id: str, service_type: str) -> Tuple[bool, str, Optional[Reservation]]:
        """Reserves balance before a session starts."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("SELECT * FROM charging_accounts WHERE id = ?;", (account_id,))
            row = cur.fetchone()
            if not row:
                return False, f"Account '{account_id}' not found.", None
            
            acc = Account(**dict(row))
            if acc.balance_available < estimated_amount:
                return False, f"Insufficient balance to reserve {estimated_amount:.2f} (available: {acc.balance_available:.2f})", None

            bal_avail_after = round(acc.balance_available - estimated_amount, 4)
            bal_res_after = round(acc.balance_reserved + estimated_amount, 4)
            now_str = datetime.datetime.utcnow().isoformat()
            res_id = f"res-{uuid.uuid4().hex[:8]}"
            tx_id = f"tx-res-{uuid.uuid4().hex[:8]}"

            cur.execute("""
            UPDATE charging_accounts
            SET balance_available = ?, balance_reserved = ?, updated_at = ?
            WHERE id = ?;
            """, (bal_avail_after, bal_res_after, now_str, acc.id))

            cur.execute("""
            INSERT INTO charging_reservations
            (id, account_id, session_id, service_type, reserved_amount, consumed_amount, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 0.0, 'ACTIVE', ?, ?);
            """, (res_id, acc.id, session_id, service_type, estimated_amount, now_str, now_str))

            cur.execute("""
            INSERT INTO charging_transactions
            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
            VALUES (?, ?, 'RESERVE', 0.0, ?, ?, 'reservation', ?, ?, ?);
            """, (
                tx_id, acc.id, acc.balance_available, bal_avail_after,
                res_id, f"Session reservation hold for {service_type}: {estimated_amount:.2f}", now_str
            ))

            con.commit()

            res = Reservation(
                id=res_id, account_id=acc.id, session_id=session_id,
                service_type=service_type, reserved_amount=estimated_amount,
                consumed_amount=0.0, status="ACTIVE", created_at=now_str, updated_at=now_str
            )
            return True, f"Reserved {estimated_amount:.2f} for session {session_id}", res

    def consume_reservation(self, reservation_id: str, actual_amount: float, usage_id: str) -> Tuple[bool, str, Optional[Transaction]]:
        """Consumes a reservation upon session completion, adjusting the actual charge and refunding unused reserve."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("SELECT * FROM charging_reservations WHERE id = ? AND status = 'ACTIVE';", (reservation_id,))
            res_row = cur.fetchone()
            if not res_row:
                return False, f"Active reservation '{reservation_id}' not found.", None
            
            res = Reservation(**dict(res_row))
            cur.execute("SELECT * FROM charging_accounts WHERE id = ?;", (res.account_id,))
            acc = Account(**dict(cur.fetchone()))

            reserved = res.reserved_amount
            now_str = datetime.datetime.utcnow().isoformat()

            if actual_amount <= reserved:
                refund = round(reserved - actual_amount, 4)
                bal_avail_after = round(acc.balance_available + refund, 4)
                bal_res_after = round(acc.balance_reserved - reserved, 4)
                bal_consumed_after = round(acc.balance_consumed + actual_amount, 4)
            else:
                extra = round(actual_amount - reserved, 4)
                bal_avail_after = round(max(0.0, acc.balance_available - extra), 4)
                bal_res_after = round(acc.balance_reserved - reserved, 4)
                bal_consumed_after = round(acc.balance_consumed + actual_amount, 4)

            tx_id = f"tx-cons-{uuid.uuid4().hex[:8]}"

            cur.execute("""
            UPDATE charging_accounts
            SET balance_available = ?, balance_reserved = ?, balance_consumed = ?, updated_at = ?
            WHERE id = ?;
            """, (bal_avail_after, bal_res_after, bal_consumed_after, now_str, acc.id))

            cur.execute("""
            UPDATE charging_reservations
            SET consumed_amount = ?, status = 'CONSUMED', updated_at = ?
            WHERE id = ?;
            """, (actual_amount, now_str, res.id))

            cur.execute("""
            INSERT INTO charging_transactions
            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
            VALUES (?, ?, 'CHARGE', ?, ?, ?, 'reservation_consumed', ?, ?, ?);
            """, (
                tx_id, acc.id, -actual_amount, acc.total_balance, bal_avail_after + bal_res_after,
                res.id, f"Consumed reservation: charge {actual_amount:.4f} (refunded {reserved - actual_amount:.4f})", now_str
            ))

            con.commit()

            tx = Transaction(
                id=tx_id, account_id=acc.id, transaction_type="CHARGE",
                amount=-actual_amount, balance_before=acc.total_balance,
                balance_after=bal_avail_after + bal_res_after,
                reference_type="reservation_consumed", reference_id=res.id,
                description=f"Consumed reservation: {actual_amount:.4f}", created_at=now_str
            )
            return True, f"Consumed {actual_amount:.4f}. New available balance: {bal_avail_after:.2f}", tx

    def release_reservation(self, reservation_id: str) -> Tuple[bool, str, Optional[Transaction]]:
        """Releases an unconsumed reservation back to available balance."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("SELECT * FROM charging_reservations WHERE id = ? AND status = 'ACTIVE';", (reservation_id,))
            res_row = cur.fetchone()
            if not res_row:
                return False, f"Active reservation '{reservation_id}' not found.", None
            
            res = Reservation(**dict(res_row))
            cur.execute("SELECT * FROM charging_accounts WHERE id = ?;", (res.account_id,))
            acc = Account(**dict(cur.fetchone()))

            bal_avail_after = round(acc.balance_available + res.reserved_amount, 4)
            bal_res_after = round(acc.balance_reserved - res.reserved_amount, 4)
            now_str = datetime.datetime.utcnow().isoformat()
            tx_id = f"tx-rel-{uuid.uuid4().hex[:8]}"

            cur.execute("""
            UPDATE charging_accounts
            SET balance_available = ?, balance_reserved = ?, updated_at = ?
            WHERE id = ?;
            """, (bal_avail_after, bal_res_after, now_str, acc.id))

            cur.execute("""
            UPDATE charging_reservations
            SET status = 'RELEASED', updated_at = ?
            WHERE id = ?;
            """, (now_str, res.id))

            cur.execute("""
            INSERT INTO charging_transactions
            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
            VALUES (?, ?, 'RELEASE', 0.0, ?, ?, 'reservation_released', ?, ?, ?);
            """, (
                tx_id, acc.id, acc.balance_available, bal_avail_after,
                res.id, f"Released reservation hold: {res.reserved_amount:.2f}", now_str
            ))

            con.commit()

            tx = Transaction(
                id=tx_id, account_id=acc.id, transaction_type="RELEASE",
                amount=0.0, balance_before=acc.balance_available,
                balance_after=bal_avail_after, reference_type="reservation_released",
                reference_id=res.id, description=f"Released reservation {res.id}", created_at=now_str
            )
            return True, f"Released {res.reserved_amount:.2f} back to available balance.", tx

    def get_account_transactions(self, account_id: str) -> List[Transaction]:
        """Fetches complete transaction ledger for an account."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("""
            SELECT * FROM charging_transactions 
            WHERE account_id = ? OR account_id = (SELECT id FROM charging_accounts WHERE imsi = ? OR sip_uri = ?)
            ORDER BY created_at ASC;
            """, (account_id, account_id, account_id))
            return [Transaction(**dict(r)) for r in cur.fetchall()]
