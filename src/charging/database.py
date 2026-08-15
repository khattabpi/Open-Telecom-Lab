"""
Database connection manager and schema migrations for Telecom Rating and Balance Management.
"""

import os
import sqlite3
import yaml
from typing import Optional, Dict, Any, List
from .models import Account, RatePlan, Tariff, Transaction, RatedEvent, Reservation

DEFAULT_DB_PATH = os.environ.get("CHARGING_DB_PATH", os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "data", "charging.sqlite"))
CONFIGS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "configs", "charging")

class Database:
    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self.init_schema()

    def get_connection(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.db_path, timeout=30.0)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys = ON")
        con.execute("PRAGMA journal_mode = WAL")
        return con

    def init_schema(self):
        with self.get_connection() as con:
            cur = con.cursor()
            
            # 1. Accounts Table
            cur.execute("""
            CREATE TABLE IF NOT EXISTS charging_accounts (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                imsi TEXT UNIQUE NOT NULL,
                msisdn TEXT,
                sip_uri TEXT UNIQUE,
                plmn TEXT NOT NULL,
                serving_plmn TEXT,
                rate_plan TEXT NOT NULL,
                balance_available REAL NOT NULL DEFAULT 0.0 CHECK (balance_available >= 0),
                balance_reserved REAL NOT NULL DEFAULT 0.0 CHECK (balance_reserved >= 0),
                balance_consumed REAL NOT NULL DEFAULT 0.0 CHECK (balance_consumed >= 0),
                currency TEXT NOT NULL DEFAULT 'LAB',
                status TEXT NOT NULL DEFAULT 'ACTIVE',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            """)

            # Schema migration for existing databases
            cur.execute("PRAGMA table_info(charging_accounts);")
            cols = [row[1] for row in cur.fetchall()]
            if "serving_plmn" not in cols:
                cur.execute("ALTER TABLE charging_accounts ADD COLUMN serving_plmn TEXT;")

            # 2. Rate Plans Table
            cur.execute("""
            CREATE TABLE IF NOT EXISTS rate_plans (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT,
                currency TEXT NOT NULL DEFAULT 'LAB',
                created_at TEXT NOT NULL
            );
            """)

            # 3. Tariffs Table
            cur.execute("""
            CREATE TABLE IF NOT EXISTS tariffs (
                id TEXT PRIMARY KEY,
                rate_plan_id TEXT NOT NULL,
                service_type TEXT NOT NULL,
                destination_type TEXT NOT NULL,
                dnn TEXT NOT NULL DEFAULT 'any',
                setup_charge REAL NOT NULL DEFAULT 0.0,
                unit_rate REAL NOT NULL DEFAULT 0.0,
                unit_size INTEGER NOT NULL DEFAULT 1,
                min_units INTEGER NOT NULL DEFAULT 1,
                granularity_units INTEGER NOT NULL DEFAULT 1,
                rounding_policy TEXT NOT NULL DEFAULT 'CEIL',
                FOREIGN KEY (rate_plan_id) REFERENCES rate_plans(id)
            );
            """)

            # 4. Reservations Table
            cur.execute("""
            CREATE TABLE IF NOT EXISTS charging_reservations (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                service_type TEXT NOT NULL,
                reserved_amount REAL NOT NULL,
                consumed_amount REAL NOT NULL DEFAULT 0.0,
                status TEXT NOT NULL DEFAULT 'ACTIVE',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY (account_id) REFERENCES charging_accounts(id)
            );
            """)

            # 5. Rated Usage Table
            cur.execute("""
            CREATE TABLE IF NOT EXISTS rated_usage (
                id TEXT PRIMARY KEY,
                usage_source TEXT NOT NULL,
                source_record_id TEXT UNIQUE NOT NULL,
                account_id TEXT NOT NULL,
                service_type TEXT NOT NULL,
                destination_type TEXT NOT NULL,
                tariff_id TEXT,
                raw_quantity REAL NOT NULL,
                billable_units REAL NOT NULL,
                setup_charge REAL NOT NULL,
                duration_charge REAL NOT NULL,
                total_charge REAL NOT NULL,
                currency TEXT NOT NULL DEFAULT 'LAB',
                rating_status TEXT NOT NULL,
                rejection_reason TEXT,
                rating_explanation TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (account_id) REFERENCES charging_accounts(id)
            );
            """)

            # 6. Charging Transactions Ledger
            cur.execute("""
            CREATE TABLE IF NOT EXISTS charging_transactions (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                transaction_type TEXT NOT NULL,
                amount REAL NOT NULL,
                balance_before REAL NOT NULL,
                balance_after REAL NOT NULL,
                reference_type TEXT NOT NULL,
                reference_id TEXT NOT NULL,
                description TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (account_id) REFERENCES charging_accounts(id)
            );
            """)

            # Indices for rapid querying
            cur.execute("CREATE INDEX IF NOT EXISTS idx_accounts_imsi ON charging_accounts(imsi);")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_accounts_sip ON charging_accounts(sip_uri);")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_tx_account ON charging_transactions(account_id);")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_rated_source ON rated_usage(source_record_id);")
            cur.execute("CREATE INDEX IF NOT EXISTS idx_rated_account ON rated_usage(account_id);")
            
            con.commit()

    def seed_default_configurations(self, force_reload: bool = False):
        """Loads rate-plans.yaml, tariffs.yaml, and accounts.yaml into database."""
        rp_file = os.path.join(CONFIGS_DIR, "rate-plans.yaml")
        tariffs_file = os.path.join(CONFIGS_DIR, "tariffs.yaml")
        acc_file = os.path.join(CONFIGS_DIR, "accounts.yaml")

        with self.get_connection() as con:
            cur = con.cursor()
            
            if force_reload:
                cur.execute("DELETE FROM tariffs;")
                cur.execute("DELETE FROM rate_plans;")

            # 1. Seed Rate Plans
            if os.path.exists(rp_file):
                with open(rp_file, "r") as f:
                    rp_data = yaml.safe_load(f) or {}
                for rp in rp_data.get("rate_plans", []):
                    cur.execute("""
                    INSERT OR REPLACE INTO rate_plans (id, name, description, currency, created_at)
                    VALUES (?, ?, ?, ?, datetime('now'));
                    """, (rp["id"], rp["name"], rp.get("description", ""), rp.get("currency", "LAB")))

            # 2. Seed Tariffs
            if os.path.exists(tariffs_file):
                with open(tariffs_file, "r") as f:
                    t_data = yaml.safe_load(f) or {}
                for t in t_data.get("tariffs", []):
                    cur.execute("""
                    INSERT OR REPLACE INTO tariffs 
                    (id, rate_plan_id, service_type, destination_type, dnn, setup_charge, unit_rate, unit_size, min_units, granularity_units, rounding_policy)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """, (
                        t["id"], t["rate_plan_id"], t["service_type"], t["destination_type"],
                        t.get("dnn", "any"), float(t.get("setup_charge", 0.0)), float(t.get("unit_rate", 0.0)),
                        int(t.get("unit_size", 1)), int(t.get("min_units", 1)), int(t.get("granularity_units", 1)),
                        t.get("rounding_policy", "CEIL")
                    ))

            # 3. Seed Accounts (only if not already created)
            if os.path.exists(acc_file):
                with open(acc_file, "r") as f:
                    acc_data = yaml.safe_load(f) or {}
                for acc in acc_data.get("accounts", []):
                    cur.execute("SELECT id, balance_available FROM charging_accounts WHERE id = ?;", (acc["id"],))
                    existing = cur.fetchone()
                    serving_p = acc.get("serving_plmn")
                    if not existing:
                        init_bal = float(acc.get("initial_balance", 0.0))
                        cur.execute("""
                        INSERT INTO charging_accounts 
                        (id, name, imsi, msisdn, sip_uri, plmn, serving_plmn, rate_plan, balance_available, balance_reserved, balance_consumed, currency, status, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0.0, 0.0, ?, ?, datetime('now'), datetime('now'));
                        """, (
                            acc["id"], acc["name"], acc["imsi"], acc.get("msisdn", ""),
                            acc.get("sip_uri", ""), acc["plmn"], serving_p, acc["rate_plan"],
                            init_bal, acc.get("currency", "LAB"), acc.get("status", "ACTIVE")
                        ))
                        # Record Initial Top-up in Transaction Ledger
                        if init_bal > 0:
                            import uuid
                            tx_id = f"tx-init-{acc['id']}-{uuid.uuid4().hex[:6]}"
                            cur.execute("""
                            INSERT INTO charging_transactions
                            (id, account_id, transaction_type, amount, balance_before, balance_after, reference_type, reference_id, description, created_at)
                            VALUES (?, ?, 'TOPUP', ?, 0.0, ?, 'manual', 'initial_seed', 'Initial subscriber account provision balance', datetime('now'));
                            """, (tx_id, acc["id"], init_bal, init_bal))
                    else:
                        # Update serving_plmn and rate_plan if changed in config
                        cur.execute("""
                        UPDATE charging_accounts 
                        SET serving_plmn = ?, rate_plan = ?, name = ?, updated_at = datetime('now')
                        WHERE id = ?;
                        """, (serving_p, acc["rate_plan"], acc["name"], acc["id"]))
            con.commit()
