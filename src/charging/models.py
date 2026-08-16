"""
Data models and type definitions for the Telecom Rating Engine & Balance Management subsystem.
"""

from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List
import datetime

@dataclass
class Account:
    id: str
    name: str
    imsi: str
    msisdn: str
    sip_uri: str
    plmn: str
    rate_plan: str
    balance_available: float
    balance_reserved: float = 0.0
    balance_consumed: float = 0.0
    currency: str = "LAB"
    status: str = "ACTIVE"
    serving_plmn: Optional[str] = None
    created_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())
    updated_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())

    @property
    def total_balance(self) -> float:
        return self.balance_available + self.balance_reserved

@dataclass
class Tariff:
    id: str
    rate_plan_id: str
    service_type: str        # voice, data, sms
    destination_type: str    # domestic, roaming_vplmn, international
    dnn: str = "any"         # internet, ims, any
    setup_charge: float = 0.0
    unit_rate: float = 0.0   # per second for voice, per unit_size bytes for data
    unit_size: int = 1       # 1 for voice seconds, 1048576 (1MB) for data
    min_units: int = 1       # minimum billable units
    granularity_units: int = 1
    rounding_policy: str = "CEIL"

@dataclass
class RatePlan:
    id: str
    name: str
    description: str
    currency: str = "LAB"
    tariffs: List[str] = field(default_factory=list)

@dataclass
class UsageEvent:
    id: str
    source: str              # kamailio_cdr, netns_data, simulation
    service_type: str        # voice, data
    caller_id: str           # imsi, msisdn, or sip_uri
    callee_id: Optional[str] = None
    caller_uri: Optional[str] = None
    callee_uri: Optional[str] = None
    origin_plmn: Optional[str] = None
    destination_plmn: Optional[str] = None
    dnn: Optional[str] = None
    duration_seconds: float = 0.0
    bytes_uploaded: int = 0
    bytes_downloaded: int = 0
    session_id: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    sip_code: Optional[int] = None
    sip_reason: Optional[str] = None

@dataclass
class RatedEvent:
    id: str
    usage_id: str
    account_id: str
    service_type: str
    destination_type: str
    tariff_id: str
    raw_quantity: float      # seconds or bytes
    billable_units: float
    setup_charge: float
    duration_charge: float
    total_charge: float
    currency: str
    rating_status: str       # RATED, REJECTED, INSUFFICIENT_BALANCE, DUPLICATE_IGNORED
    usage_source: str = "kamailio_cdr"
    rejection_reason: Optional[str] = None
    rating_explanation: Optional[str] = None
    created_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())

@dataclass
class Transaction:
    id: str
    account_id: str
    transaction_type: str    # TOPUP, CHARGE, RESERVE, RELEASE, ADJUST
    amount: float            # Positive for credit, negative for debit
    balance_before: float
    balance_after: float
    reference_type: str      # rated_usage, reservation, manual
    reference_id: str
    description: str
    created_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())

@dataclass
class Reservation:
    id: str
    account_id: str
    session_id: str
    service_type: str
    reserved_amount: float
    consumed_amount: float = 0.0
    status: str = "ACTIVE"   # ACTIVE, CONSUMED, RELEASED, EXPIRED
    created_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())
    updated_at: str = field(default_factory=lambda: datetime.datetime.utcnow().isoformat())
