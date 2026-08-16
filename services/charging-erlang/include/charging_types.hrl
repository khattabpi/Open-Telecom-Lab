%%%-------------------------------------------------------------------
%%% @doc charging_types.hrl
%%% Shared record definitions for the Erlang/OTP Telecom Charging Service.
%%% Mirrors the Phase 5.5 Golden Data Model.
%%% @end
%%%-------------------------------------------------------------------

-ifndef(CHARGING_TYPES_HRL).
-define(CHARGING_TYPES_HRL, true).

%% Subscriber account entity
-record(account, {
    id :: binary(),
    name :: binary(),
    imsi :: binary() | undefined,
    msisdn :: binary() | undefined,
    sip_uri :: binary() | undefined,
    plmn :: binary(),
    serving_plmn :: binary() | undefined,
    rate_plan :: binary(),
    balance_available = 0.0 :: float(),
    balance_reserved = 0.0 :: float(),
    balance_consumed = 0.0 :: float(),
    currency = <<"LAB">> :: binary(),
    status = <<"ACTIVE">> :: binary(),
    created_at :: binary(),
    updated_at :: binary()
}).

%% Rate plan definition
-record(rate_plan, {
    id :: binary(),
    name :: binary(),
    plan_type = <<"prepaid">> :: binary(),
    currency = <<"LAB">> :: binary(),
    is_default = false :: boolean(),
    created_at :: binary()
}).

%% Tariff pricing rule
-record(tariff, {
    id :: binary(),
    rate_plan_id :: binary(),
    service_type :: binary(),      % <<"voice">>, <<"data">>
    destination_type :: binary(),  % <<"domestic">>, <<"roaming_vplmn">>, <<"any">>
    dnn = <<"any">> :: binary(),   % <<"any">>, <<"internet">>, <<"ims">>
    setup_charge = 0.0 :: float(),
    unit_rate = 0.0 :: float(),
    unit_size = 1 :: pos_integer(),
    min_units = 1 :: non_neg_integer(),
    granularity_units = 1 :: pos_integer(),
    rounding_policy = <<"CEIL">> :: binary(),
    is_active = true :: boolean(),
    created_at :: binary()
}).

%% Active balance reservation
-record(reservation, {
    id :: binary(),
    account_id :: binary(),
    session_id :: binary(),
    service_type = <<"voice">> :: binary(),
    reserved_amount = 0.0 :: float(),
    consumed_amount = 0.0 :: float(),
    status = <<"ACTIVE">> :: binary(), % <<"ACTIVE">>, <<"CONSUMED">>, <<"RELEASED">>
    expires_at = 0 :: integer(),
    created_at :: binary()
}).

%% Immutable transaction journal entry
-record(transaction, {
    id :: binary(),
    account_id :: binary(),
    transaction_type :: binary(), % <<"TOPUP">>, <<"CHARGE">>, <<"RESERVE">>, <<"RELEASE">>
    amount = 0.0 :: float(),
    balance_before = 0.0 :: float(),
    balance_after = 0.0 :: float(),
    reference_type = <<"manual">> :: binary(),
    reference_id = <<>> :: binary(),
    description = <<>> :: binary(),
    created_at :: binary()
}).

%% Rated usage event
-record(rated_event, {
    id :: binary(),
    account_id :: binary(),
    tariff_id :: binary(),
    service_type :: binary(),
    destination_type :: binary(),
    source_units = 0.0 :: float(),
    billable_units = 0 :: integer(),
    setup_charge = 0.0 :: float(),
    usage_charge = 0.0 :: float(),
    total_charge = 0.0 :: float(),
    currency = <<"LAB">> :: binary(),
    rating_status = <<"SUCCESS">> :: binary(),
    explanation = <<>> :: binary(),
    created_at :: binary()
}).

-endif.
