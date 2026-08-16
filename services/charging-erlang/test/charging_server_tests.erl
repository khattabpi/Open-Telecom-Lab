%%%-------------------------------------------------------------------
%%% @doc charging_server_tests
%%% EUnit tests for the Erlang Charging Server (gen_server).
%%% Tests balance lifecycle, reservations, refunds, and reconciliation.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_server_tests).
-include_lib("eunit/include/eunit.hrl").

server_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(charging_service),
         charging_server:reset_state(),
         ok
     end,
     fun(_) ->
         charging_server:reset_state(),
         ok
     end,
     [
         {"[SERVER-TEST-01] Balance inquiry for acc-ue3",
          fun() ->
              {ok, Bal} = charging_server:get_balance(<<"acc-ue3">>),
              ?assertEqual(<<"acc-ue3">>, maps:get(<<"account_id">>, Bal)),
              ?assertEqual(30.0000, maps:get(<<"balance_available">>, Bal)),
              ?assertEqual(0.0000, maps:get(<<"balance_reserved">>, Bal)),
              ?assertEqual(0.0000, maps:get(<<"balance_consumed">>, Bal))
          end},

         {"[SERVER-TEST-02] Reservation hold (30.0 -> Avail: 29.5, Res: 0.5)",
          fun() ->
              {ok, Res} = charging_server:reserve(<<"acc-ue3">>, <<"sess-test-01">>, <<"voice">>, 0.5000),
              ?assertEqual(<<"ACTIVE">>, maps:get(<<"status">>, Res)),
              ?assertEqual(0.5000, maps:get(<<"reserved_amount">>, Res)),
              ?assertEqual(29.5000, maps:get(<<"available_balance">>, Res)),
              
              {ok, Bal} = charging_server:get_balance(<<"acc-ue3">>),
              ?assertEqual(29.5000, maps:get(<<"balance_available">>, Bal)),
              ?assertEqual(0.5000, maps:get(<<"balance_reserved">>, Bal))
          end},

         {"[SERVER-TEST-03] Consume reservation (0.50 -> Avail: 29.5, Res: 0.0, Cons: 0.5)",
          fun() ->
              {ok, Cons} = charging_server:consume(<<"acc-ue3">>, <<"sess-test-01">>, 0.5000),
              ?assertEqual(<<"CONSUMED">>, maps:get(<<"status">>, Cons)),
              ?assertEqual(0.5000, maps:get(<<"actual_charge">>, Cons)),
              ?assertEqual(0.0000, maps:get(<<"refund_amount">>, Cons)),
              ?assertEqual(29.5000, maps:get(<<"available_balance">>, Cons)),
              ?assertEqual(0.5000, maps:get(<<"consumed_balance">>, Cons))
          end},

         {"[SERVER-TEST-04] Reservation with unused credit refund",
          fun() ->
              %% Reserve 5.00 LAB on acc-ue2 (starts at 25.0 -> avail: 20.0, res: 5.0)
              {ok, Res} = charging_server:reserve(<<"acc-ue2">>, <<"sess-test-02">>, <<"voice">>, 5.0000),
              ?assertEqual(20.0000, maps:get(<<"available_balance">>, Res)),
              
              %% Consume only 1.50 LAB -> 3.50 refund returned to available (avail: 23.5, res: 0.0, cons: 1.5)
              {ok, Cons} = charging_server:consume(<<"acc-ue2">>, <<"sess-test-02">>, 1.5000),
              ?assertEqual(3.5000, maps:get(<<"refund_amount">>, Cons)),
              ?assertEqual(23.5000, maps:get(<<"available_balance">>, Cons)),
              ?assertEqual(0.0000, maps:get(<<"reserved_balance">>, Cons)),
              ?assertEqual(1.5000, maps:get(<<"consumed_balance">>, Cons))
          end},

         {"[SERVER-TEST-05] Reservation release (cancelled call)",
          fun() ->
              {ok, _} = charging_server:reserve(<<"acc-ue1">>, <<"sess-test-03">>, <<"voice">>, 2.0000),
              {ok, Rel} = charging_server:refund(<<"acc-ue1">>, <<"sess-test-03">>),
              ?assertEqual(<<"RELEASED">>, maps:get(<<"status">>, Rel)),
              ?assertEqual(2.0000, maps:get(<<"refunded_amount">>, Rel)),
              ?assertEqual(50.0000, maps:get(<<"available_balance">>, Rel)),
              ?assertEqual(0.0000, maps:get(<<"reserved_balance">>, Rel))
          end},

         {"[SERVER-TEST-06] Insufficient balance rejection without balance corruption",
          fun() ->
              %% acc-test-broke has 0.0200 LAB available
              Res = charging_server:reserve(<<"acc-test-broke">>, <<"sess-broke">>, <<"voice">>, 0.5000),
              ?assertEqual({error, insufficient_balance}, Res),
              
              %% Verify balance remains unmodified
              {ok, Bal} = charging_server:get_balance(<<"acc-test-broke">>),
              ?assertEqual(0.0200, maps:get(<<"balance_available">>, Bal)),
              ?assertEqual(0.0000, maps:get(<<"balance_reserved">>, Bal))
          end},

         {"[SERVER-TEST-07] Account topup transaction",
          fun() ->
              {ok, Acc} = charging_server:topup(<<"acc-ue1">>, 20.0000, <<"Test topup">>),
              ?assertEqual(70.0000, maps:get(<<"balance_available">>, Acc))
          end},

         {"[SERVER-TEST-08] Transaction ledger history and audit trail",
          fun() ->
              {ok, Txs} = charging_server:get_transactions(<<"acc-ue3">>),
              ?assert(length(Txs) >= 3),
              TxTypes = [maps:get(<<"transaction_type">>, T) || T <- Txs],
              ?assert(lists:member(<<"TOPUP">>, TxTypes)),
              ?assert(lists:member(<<"RESERVE">>, TxTypes)),
              ?assert(lists:member(<<"CHARGE">>, TxTypes))
          end},

         {"[SERVER-TEST-09] Multi-point financial reconciliation audit",
          fun() ->
              {ok, Report} = charging_server:reconcile(),
              ?assertEqual(<<"PASS">>, maps:get(<<"status">>, Report)),
              ?assertEqual(0, maps:get(<<"anomalies_count">>, Report)),
              ?assertEqual(4, maps:get(<<"accounts_audited">>, Report))
          end}
     ]}.
