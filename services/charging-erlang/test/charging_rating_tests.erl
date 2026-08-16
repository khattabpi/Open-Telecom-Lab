%%%-------------------------------------------------------------------
%%% @doc charging_rating_tests
%%% EUnit tests for the Erlang Telecom Rating Engine.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_rating_tests).
-include_lib("eunit/include/eunit.hrl").
-include("charging_types.hrl").

rating_test_() ->
    {setup,
     fun() ->
         Tariffs = charging_storage:default_tariffs(),
         Accounts = charging_storage:default_accounts(),
         AccountMap = maps:from_list([{A#account.id, A} || A <- Accounts]),
         {AccountMap, Tariffs}
     end,
     fun(_) -> ok end,
     fun({AccountMap, Tariffs}) ->
         [
             {"[RATING-TEST-01] UE3 Roaming Voice Rating 10s -> 0.5000 LAB",
              fun() ->
                  AccUE3 = maps:get(<<"acc-ue3">>, AccountMap),
                  {ok, Event} = charging_rating:rate_usage(AccUE3, <<"roaming_vplmn">>, <<"voice">>, <<"any">>, 10.0, Tariffs),
                  ?assertEqual(0.1000, Event#rated_event.setup_charge),
                  ?assertEqual(0.4000, Event#rated_event.usage_charge),
                  ?assertEqual(0.5000, Event#rated_event.total_charge),
                  ?assertEqual(<<"roaming_vplmn">>, Event#rated_event.destination_type),
                  ?assertEqual(<<"tariff-premium-roaming-voice">>, Event#rated_event.tariff_id)
              end},

             {"[RATING-TEST-02] UE1 Domestic Voice Rating 10s -> 0.2500 LAB",
              fun() ->
                  AccUE1 = maps:get(<<"acc-ue1">>, AccountMap),
                  {ok, Event} = charging_rating:rate_usage(AccUE1, <<"sip:ue2@ims.lab">>, <<"voice">>, <<"any">>, 10.0, Tariffs),
                  ?assertEqual(0.0500, Event#rated_event.setup_charge),
                  ?assertEqual(0.2000, Event#rated_event.usage_charge),
                  ?assertEqual(0.2500, Event#rated_event.total_charge),
                  ?assertEqual(<<"domestic">>, Event#rated_event.destination_type),
                  ?assertEqual(<<"tariff-domestic-voice">>, Event#rated_event.tariff_id)
              end},

             {"[RATING-TEST-03] Duration CEIL Rounding Policy (1.1s -> 2s billable)",
              fun() ->
                  AccUE1 = maps:get(<<"acc-ue1">>, AccountMap),
                  {ok, Event} = charging_rating:rate_usage(AccUE1, <<"domestic">>, <<"voice">>, <<"any">>, 1.1, Tariffs),
                  ?assertEqual(2, Event#rated_event.billable_units),
                  ?assertEqual(0.0400, Event#rated_event.usage_charge),
                  ?assertEqual(0.0900, Event#rated_event.total_charge)
              end},

             {"[RATING-TEST-04] Internet Data Usage Rating (2 MB -> 0.0200 LAB)",
              fun() ->
                  AccUE1 = maps:get(<<"acc-ue1">>, AccountMap),
                  {ok, Event} = charging_rating:rate_usage(AccUE1, <<"domestic">>, <<"data">>, <<"internet">>, 2097152, Tariffs),
                  ?assertEqual(0.0200, Event#rated_event.total_charge),
                  ?assertEqual(<<"tariff-domestic-data-internet">>, Event#rated_event.tariff_id)
              end},

             {"[RATING-TEST-05] Vo5G IMS Signaling Bearer Zero-Rated Policy (0.0000 LAB)",
              fun() ->
                  AccUE1 = maps:get(<<"acc-ue1">>, AccountMap),
                  {ok, Event} = charging_rating:rate_usage(AccUE1, <<"domestic">>, <<"data">>, <<"ims">>, 5242880, Tariffs),
                  ?assertEqual(0.0000, Event#rated_event.total_charge),
                  ?assertEqual(<<"tariff-domestic-data-ims">>, Event#rated_event.tariff_id)
              end}
         ]
     end}.
