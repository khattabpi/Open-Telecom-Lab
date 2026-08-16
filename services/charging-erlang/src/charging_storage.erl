%%%-------------------------------------------------------------------
%%% @doc charging_storage
%%% Storage and initial seed data adapter for Erlang Telecom Charging.
%%% Provides declarative seed definitions identical to Phase 5.5.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_storage).

-include("charging_types.hrl").

-export([
    default_accounts/0,
    default_tariffs/0,
    default_rate_plans/0,
    default_transactions/0
]).

-spec default_accounts() -> [#account{}].
default_accounts() ->
    Now = current_iso8601(),
    [
        #account{
            id = <<"acc-ue1">>,
            name = <<"UE1 Domestic Subscriber">>,
            imsi = <<"602030000000001">>,
            msisdn = <<"+201000000001">>,
            sip_uri = <<"sip:ue1@ims.lab">>,
            plmn = <<"602/03">>,
            serving_plmn = undefined,
            rate_plan = <<"standard-prepaid">>,
            balance_available = 50.0000,
            balance_reserved = 0.0000,
            balance_consumed = 0.0000,
            currency = <<"LAB">>,
            status = <<"ACTIVE">>,
            created_at = Now,
            updated_at = Now
        },
        #account{
            id = <<"acc-ue2">>,
            name = <<"UE2 Domestic Subscriber">>,
            imsi = <<"602040000000002">>,
            msisdn = <<"+201000000002">>,
            sip_uri = <<"sip:ue2@ims.lab">>,
            plmn = <<"602/04">>,
            serving_plmn = undefined,
            rate_plan = <<"standard-prepaid">>,
            balance_available = 25.0000,
            balance_reserved = 0.0000,
            balance_consumed = 0.0000,
            currency = <<"LAB">>,
            status = <<"ACTIVE">>,
            created_at = Now,
            updated_at = Now
        },
        #account{
            id = <<"acc-ue3">>,
            name = <<"UE3 Roaming Subscriber">>,
            imsi = <<"602030000000003">>,
            msisdn = <<"+201000000003">>,
            sip_uri = <<"sip:ue3@ims.lab">>,
            plmn = <<"602/03">>,
            serving_plmn = <<"218/90">>,
            rate_plan = <<"premium-roaming">>,
            balance_available = 30.0000,
            balance_reserved = 0.0000,
            balance_consumed = 0.0000,
            currency = <<"LAB">>,
            status = <<"ACTIVE">>,
            created_at = Now,
            updated_at = Now
        },
        #account{
            id = <<"acc-test-broke">>,
            name = <<"Zero Balance Test Subscriber">>,
            imsi = <<"602030000000999">>,
            msisdn = <<"+201000000999">>,
            sip_uri = <<"sip:broke@ims.lab">>,
            plmn = <<"602/03">>,
            serving_plmn = undefined,
            rate_plan = <<"standard-prepaid">>,
            balance_available = 0.0200,
            balance_reserved = 0.0000,
            balance_consumed = 0.0000,
            currency = <<"LAB">>,
            status = <<"ACTIVE">>,
            created_at = Now,
            updated_at = Now
        }
    ].

-spec default_tariffs() -> [#tariff{}].
default_tariffs() ->
    Now = current_iso8601(),
    [
        #tariff{
            id = <<"tariff-domestic-voice">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"voice">>,
            destination_type = <<"domestic">>,
            dnn = <<"any">>,
            setup_charge = 0.0500,
            unit_rate = 0.0200,
            unit_size = 1,
            min_units = 1,
            granularity_units = 1,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-roaming-voice">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"voice">>,
            destination_type = <<"roaming_vplmn">>,
            dnn = <<"any">>,
            setup_charge = 0.1500,
            unit_rate = 0.0800,
            unit_size = 1,
            min_units = 1,
            granularity_units = 1,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-premium-roaming-voice">>,
            rate_plan_id = <<"premium-roaming">>,
            service_type = <<"voice">>,
            destination_type = <<"roaming_vplmn">>,
            dnn = <<"any">>,
            setup_charge = 0.1000,
            unit_rate = 0.0400,
            unit_size = 1,
            min_units = 1,
            granularity_units = 1,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-domestic-data-internet">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"data">>,
            destination_type = <<"domestic">>,
            dnn = <<"internet">>,
            setup_charge = 0.0000,
            unit_rate = 0.0100,
            unit_size = 1048576,
            min_units = 1024,
            granularity_units = 1024,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-roaming-data-internet">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"data">>,
            destination_type = <<"roaming_vplmn">>,
            dnn = <<"internet">>,
            setup_charge = 0.0000,
            unit_rate = 0.0500,
            unit_size = 1048576,
            min_units = 1024,
            granularity_units = 1024,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-premium-roaming-data">>,
            rate_plan_id = <<"premium-roaming">>,
            service_type = <<"data">>,
            destination_type = <<"roaming_vplmn">>,
            dnn = <<"internet">>,
            setup_charge = 0.0000,
            unit_rate = 0.0250,
            unit_size = 1048576,
            min_units = 1024,
            granularity_units = 1024,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-domestic-data-ims">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"data">>,
            destination_type = <<"domestic">>,
            dnn = <<"ims">>,
            setup_charge = 0.0000,
            unit_rate = 0.0000,
            unit_size = 1024,
            min_units = 1024,
            granularity_units = 1024,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        },
        #tariff{
            id = <<"tariff-roaming-data-ims">>,
            rate_plan_id = <<"standard-prepaid">>,
            service_type = <<"data">>,
            destination_type = <<"roaming_vplmn">>,
            dnn = <<"ims">>,
            setup_charge = 0.0000,
            unit_rate = 0.0000,
            unit_size = 1024,
            min_units = 1024,
            granularity_units = 1024,
            rounding_policy = <<"CEIL">>,
            created_at = Now
        }
    ].

-spec default_rate_plans() -> [#rate_plan{}].
default_rate_plans() ->
    Now = current_iso8601(),
    [
        #rate_plan{
            id = <<"standard-prepaid">>,
            name = <<"Standard Prepaid Plan">>,
            plan_type = <<"prepaid">>,
            currency = <<"LAB">>,
            is_default = true,
            created_at = Now
        },
        #rate_plan{
            id = <<"premium-roaming">>,
            name = <<"Premium Roaming Plan">>,
            plan_type = <<"prepaid">>,
            currency = <<"LAB">>,
            is_default = false,
            created_at = Now
        }
    ].

-spec default_transactions() -> [#transaction{}].
default_transactions() ->
    Now = current_iso8601(),
    [
        #transaction{
            id = <<"tx-init-acc-ue1">>,
            account_id = <<"acc-ue1">>,
            transaction_type = <<"TOPUP">>,
            amount = 50.0000,
            balance_before = 0.0000,
            balance_after = 50.0000,
            reference_type = <<"seed">>,
            reference_id = <<"init">>,
            description = <<"Initial subscriber account credit">>,
            created_at = Now
        },
        #transaction{
            id = <<"tx-init-acc-ue2">>,
            account_id = <<"acc-ue2">>,
            transaction_type = <<"TOPUP">>,
            amount = 25.0000,
            balance_before = 0.0000,
            balance_after = 25.0000,
            reference_type = <<"seed">>,
            reference_id = <<"init">>,
            description = <<"Initial subscriber account credit">>,
            created_at = Now
        },
        #transaction{
            id = <<"tx-init-acc-ue3">>,
            account_id = <<"acc-ue3">>,
            transaction_type = <<"TOPUP">>,
            amount = 30.0000,
            balance_before = 0.0000,
            balance_after = 30.0000,
            reference_type = <<"seed">>,
            reference_id = <<"init">>,
            description = <<"Initial subscriber account credit">>,
            created_at = Now
        },
        #transaction{
            id = <<"tx-init-acc-test-broke">>,
            account_id = <<"acc-test-broke">>,
            transaction_type = <<"TOPUP">>,
            amount = 0.0200,
            balance_before = 0.0000,
            balance_after = 0.0200,
            reference_type = <<"seed">>,
            reference_id = <<"init">>,
            description = <<"Initial subscriber account credit">>,
            created_at = Now
        }
    ].

current_iso8601() ->
    {{Y, M, D}, {H, MM, S}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, M, D, H, MM, S])).
