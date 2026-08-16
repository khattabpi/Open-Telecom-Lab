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

    def lookup_account_by_identifier(self, identifier: Optional[str]) -> Optional[Account]:
        """Resolves charging account by IMSI, SIP URI, MSISDN, or Account ID."""
        if not identifier:
            return None
        with self.db.get_connection() as con:
            cur = con.cursor()
            cur.execute("""
            SELECT * FROM charging_accounts 
            WHERE sip_uri = ? OR imsi = ? OR msisdn = ? OR id = ?;
            """, (identifier, identifier, identifier, identifier))
            row = cur.fetchone()
            if row:
                return Account(**dict(row))
        return None

    def resolve_account(self, event: UsageEvent) -> Optional[Account]:
        """Resolves charging account for the event's caller."""
        if event.caller_uri:
            acc = self.lookup_account_by_identifier(event.caller_uri)
            if acc:
                return acc
        if event.caller_id:
            acc = self.lookup_account_by_identifier(event.caller_id)
            if acc:
                return acc
        return None

    def classify_destination(self, event: UsageEvent, account: Account) -> str:
        """
        Determines if the session is domestic or roaming based on:
        1. Caller's serving PLMN vs Home PLMN (Originating Roaming)
        2. Callee's serving PLMN vs Home PLMN (Terminating Roaming)
        3. Event origin/destination PLMN indicators
        """
        # 1. Check if caller is roaming (Serving PLMN != Home PLMN)
        caller_serving_plmn = event.origin_plmn or account.serving_plmn
        if caller_serving_plmn and caller_serving_plmn != account.plmn:
            return "roaming_vplmn"

        # 2. Check Voice Destination
        if event.service_type == "voice":
            callee_id = event.callee_uri or event.callee_id
            if callee_id:
                callee_acc = self.lookup_account_by_identifier(callee_id)
                if callee_acc:
                    callee_serving_plmn = event.destination_plmn or callee_acc.serving_plmn
                    if callee_serving_plmn and callee_serving_plmn != callee_acc.plmn:
                        return "roaming_vplmn"
                    # If callee is in an external network outside home PLMN group
                    if callee_acc.plmn != account.plmn and not (account.plmn.startswith("602/") and callee_acc.plmn.startswith("602/")):
                        return "roaming_vplmn"

            if event.destination_plmn and event.destination_plmn != account.plmn and not (account.plmn.startswith("602/") and event.destination_plmn.startswith("602/")):
                return "roaming_vplmn"

        # 3. Check Data Destination
        elif event.service_type == "data":
            if event.origin_plmn and event.origin_plmn != account.plmn:
                return "roaming_vplmn"

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
            usage_source=event.source or "kamailio_cdr",
            rejection_reason=None,
            rating_explanation=explanation,
            created_at=datetime.datetime.utcnow().isoformat()
        )
