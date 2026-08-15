"""
Deterministic Telecom Rating Engine for 5G Standalone & IMS Vo5G laboratory sessions.
"""

import math
import uuid
import datetime
from typing import Optional, Dict, Any, Tuple
from .models import UsageEvent, RatedEvent, Tariff, Account
from .database import Database

class RatingEngine:
    def __init__(self, db: Optional[Database] = None):
        self.db = db or Database()

    def resolve_account(self, event: UsageEvent) -> Optional[Account]:
        """Resolves charging account by IMSI, SIP URI, or MSISDN."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            # 1. Match by SIP URI
            if event.caller_uri:
                cur.execute("SELECT * FROM charging_accounts WHERE sip_uri = ?;", (event.caller_uri,))
                row = cur.fetchone()
                if row:
                    return Account(**dict(row))
            # 2. Match by Caller ID (IMSI or MSISDN)
            if event.caller_id:
                cur.execute("SELECT * FROM charging_accounts WHERE imsi = ? OR msisdn = ? OR id = ?;", 
                            (event.caller_id, event.caller_id, event.caller_id))
                row = cur.fetchone()
                if row:
                    return Account(**dict(row))
        return None

    def classify_destination(self, event: UsageEvent, account: Account) -> str:
        """Determines if the session is domestic or roaming."""
        if event.service_type == "voice":
            callee = (event.callee_uri or event.callee_id or "").lower()
            # If callee is UE3 (roaming in Bosnia 218/90) or destination is 218/90
            if "ue3" in callee or event.destination_plmn == "218/90":
                return "roaming_vplmn"
            # If caller is roaming in VPLMN 218/90
            if event.origin_plmn == "218/90" or "218/90" in account.plmn:
                return "roaming_vplmn"
            return "domestic"

        elif event.service_type == "data":
            if event.origin_plmn == "218/90" or "roaming" in (event.origin_plmn or "").lower():
                return "roaming_vplmn"
            return "domestic"

        return "domestic"

    def select_tariff(self, rate_plan_id: str, service_type: str, destination_type: str, dnn: str = "any") -> Optional[Tariff]:
        """Selects the best matching tariff rule."""
        with self.db.get_connection() as con:
            cur = con.cursor()
            # 1. Exact match with DNN
            cur.execute("""
            SELECT * FROM tariffs 
            WHERE rate_plan_id = ? AND service_type = ? AND destination_type = ? AND dnn = ?;
            """, (rate_plan_id, service_type, destination_type, dnn))
            row = cur.fetchone()
            if row:
                return Tariff(**dict(row))

            # 2. Fallback match with dnn='any'
            cur.execute("""
            SELECT * FROM tariffs 
            WHERE rate_plan_id = ? AND service_type = ? AND destination_type = ? AND dnn = 'any';
            """, (rate_plan_id, service_type, destination_type))
            row = cur.fetchone()
            if row:
                return Tariff(**dict(row))
        return None

    def rate_event(self, event: UsageEvent) -> RatedEvent:
        """Applies rating rules to a usage event and produces a deterministic RatedEvent."""
        account = self.resolve_account(event)
        if not account:
            return RatedEvent(
                id=f"rated-err-{uuid.uuid4().hex[:8]}",
                usage_id=event.id,
                account_id="UNKNOWN",
                service_type=event.service_type,
                destination_type="UNKNOWN",
                tariff_id="NONE",
                raw_quantity=event.duration_seconds if event.service_type == "voice" else (event.bytes_uploaded + event.bytes_downloaded),
                billable_units=0.0,
                setup_charge=0.0,
                duration_charge=0.0,
                total_charge=0.0,
                currency="LAB",
                rating_status="REJECTED",
                rejection_reason=f"Unable to resolve charging account for caller: uri={event.caller_uri}, id={event.caller_id}",
                rating_explanation="Rating failed: Unidentified subscriber."
            )

        destination_type = self.classify_destination(event, account)
        dnn = event.dnn or "any"
        tariff = self.select_tariff(account.rate_plan, event.service_type, destination_type, dnn)

        if not tariff:
            return RatedEvent(
                id=f"rated-err-{uuid.uuid4().hex[:8]}",
                usage_id=event.id,
                account_id=account.id,
                service_type=event.service_type,
                destination_type=destination_type,
                tariff_id="NONE",
                raw_quantity=event.duration_seconds if event.service_type == "voice" else (event.bytes_uploaded + event.bytes_downloaded),
                billable_units=0.0,
                setup_charge=0.0,
                duration_charge=0.0,
                total_charge=0.0,
                currency=account.currency,
                rating_status="REJECTED",
                rejection_reason=f"No tariff found for plan={account.rate_plan}, service={event.service_type}, dest={destination_type}, dnn={dnn}",
                rating_explanation="Rating failed: Missing tariff configuration."
            )

        # Mathematical Rating Calculation
        if event.service_type == "voice":
            raw_qty = max(0.0, float(event.duration_seconds))
            if raw_qty == 0.0:
                # 0-second call (e.g. instant cancel or unanswered)
                billable_units = 0.0
                setup = 0.0
                usage_cost = 0.0
            else:
                billable_units = max(raw_qty, float(tariff.min_units))
                if tariff.rounding_policy == "CEIL":
                    billable_units = math.ceil(billable_units / tariff.granularity_units) * tariff.granularity_units
                setup = tariff.setup_charge
                usage_cost = (billable_units / tariff.unit_size) * tariff.unit_rate
            total = round(setup + usage_cost, 4)

            explanation = (
                f"[Voice Rating] Plan: {account.rate_plan} | Tariff: {tariff.id} ({destination_type}) | "
                f"Duration: {raw_qty}s -> Billable: {billable_units}s | "
                f"Setup: {setup:.2f} {account.currency} + Usage: {usage_cost:.4f} {account.currency} "
                f"(@ {tariff.unit_rate}/s) = Total: {total:.4f} {account.currency}"
            )

        elif event.service_type == "data":
            raw_qty = float(event.bytes_uploaded + event.bytes_downloaded)
            if raw_qty == 0:
                billable_units = 0.0
                setup = 0.0
                usage_cost = 0.0
            else:
                billable_units = max(raw_qty, float(tariff.min_units))
                if tariff.rounding_policy == "CEIL":
                    billable_units = math.ceil(billable_units / tariff.granularity_units) * tariff.granularity_units
                setup = tariff.setup_charge
                usage_cost = (billable_units / tariff.unit_size) * tariff.unit_rate
            total = round(setup + usage_cost, 4)

            explanation = (
                f"[Data Rating] Plan: {account.rate_plan} | Tariff: {tariff.id} (DNN: {dnn}, {destination_type}) | "
                f"Volume: {int(raw_qty)} B ({raw_qty/1048576:.2f} MB) -> Billable: {int(billable_units)} B | "
                f"Rate: {tariff.unit_rate} {account.currency}/MB = Total: {total:.4f} {account.currency}"
            )

        else:
            return RatedEvent(
                id=f"rated-err-{uuid.uuid4().hex[:8]}",
                usage_id=event.id,
                account_id=account.id,
                service_type=event.service_type,
                destination_type=destination_type,
                tariff_id=tariff.id,
                raw_quantity=0.0,
                billable_units=0.0,
                setup_charge=0.0,
                duration_charge=0.0,
                total_charge=0.0,
                currency=account.currency,
                rating_status="REJECTED",
                rejection_reason=f"Unsupported service type: {event.service_type}",
                rating_explanation="Rating failed: Unknown service."
            )

        rated_id = f"rated-{event.id}"
        return RatedEvent(
            id=rated_id,
            usage_id=event.id,
            account_id=account.id,
            service_type=event.service_type,
            destination_type=destination_type,
            tariff_id=tariff.id,
            raw_quantity=raw_qty,
            billable_units=billable_units,
            setup_charge=setup,
            duration_charge=usage_cost,
            total_charge=total,
            currency=account.currency,
            rating_status="RATED",
            rejection_reason=None,
            rating_explanation=explanation,
            created_at=datetime.datetime.utcnow().isoformat()
        )
