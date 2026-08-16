%%%-------------------------------------------------------------------
%%% @doc charging_http_tests
%%% EUnit tests for Cowboy HTTP REST API endpoints.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_http_tests).
-include_lib("eunit/include/eunit.hrl").

http_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(inets),
         application:ensure_all_started(charging_service),
         charging_server:reset_state(),
         "http://127.0.0.1:8085"
     end,
     fun(_) ->
         charging_server:reset_state(),
         ok
     end,
     fun(BaseUrl) ->
         [
             {"[HTTP-TEST-01] GET /health",
              fun() ->
                  {ok, {{_, 200, _}, _, Body}} = httpc:request(get, {BaseUrl ++ "/health", []}, [], []),
                  Json = jsx:decode(list_to_binary(Body), [return_maps]),
                  ?assertEqual(<<"UP">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(<<"charging-erlang">>, maps:get(<<"service">>, Json))
              end},

             {"[HTTP-TEST-02] GET /metrics",
              fun() ->
                  {ok, {{_, 200, _}, _, Body}} = httpc:request(get, {BaseUrl ++ "/metrics", []}, [], []),
                  Json = jsx:decode(list_to_binary(Body), [return_maps]),
                  ?assertEqual(<<"HEALTHY">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(4, maps:get(<<"active_accounts_count">>, Json))
              end},

             {"[HTTP-TEST-03] GET /v1/accounts/acc-ue3/balance",
              fun() ->
                  {ok, {{_, 200, _}, _, Body}} = httpc:request(get, {BaseUrl ++ "/v1/accounts/acc-ue3/balance", []}, [], []),
                  Json = jsx:decode(list_to_binary(Body), [return_maps]),
                  ?assertEqual(<<"acc-ue3">>, maps:get(<<"account_id">>, Json)),
                  ?assertEqual(30.0000, maps:get(<<"balance_available">>, Json)),
                  ?assertEqual(<<"premium-roaming">>, maps:get(<<"rate_plan">>, Json))
              end},

             {"[HTTP-TEST-04] POST /v1/rating/quote for UE3 Roaming 10s -> 0.5000 LAB",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue3">>,
                      <<"destination">> => <<"roaming_vplmn">>,
                      <<"duration">> => 10.0,
                      <<"service_type">> => <<"voice">>
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/rating/quote", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(0.5000, maps:get(<<"total_charge">>, Json)),
                  ?assertEqual(<<"tariff-premium-roaming-voice">>, maps:get(<<"tariff_id">>, Json))
              end},

             {"[HTTP-TEST-05] POST /v1/rating/quote for UE1 Domestic 10s -> 0.2500 LAB",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue1">>,
                      <<"destination">> => <<"domestic">>,
                      <<"duration">> => 10.0,
                      <<"service_type">> => <<"voice">>
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/rating/quote", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(0.2500, maps:get(<<"total_charge">>, Json)),
                  ?assertEqual(<<"tariff-domestic-voice">>, maps:get(<<"tariff_id">>, Json))
              end},

             {"[HTTP-TEST-06] POST /v1/charging/reserve (0.50 LAB)",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue3">>,
                      <<"session_id">> => <<"http-sess-01">>,
                      <<"service_type">> => <<"voice">>,
                      <<"estimated_amount">> => 0.5000
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/reserve", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(<<"ACTIVE">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(29.5000, maps:get(<<"available_balance">>, Json))
              end},

             {"[HTTP-TEST-07] POST /v1/charging/consume (0.50 LAB)",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue3">>,
                      <<"session_id">> => <<"http-sess-01">>,
                      <<"actual_charge">> => 0.5000
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/consume", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(<<"CONSUMED">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(29.5000, maps:get(<<"available_balance">>, Json)),
                  ?assertEqual(0.5000, maps:get(<<"consumed_balance">>, Json))
              end},

             {"[HTTP-TEST-08] Insufficient balance reservation rejected (402)",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-test-broke">>,
                      <<"session_id">> => <<"http-sess-broke">>,
                      <<"service_type">> => <<"voice">>,
                      <<"estimated_amount">> => 1.0000
                  }),
                  {ok, {{_, 402, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/reserve", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(true, maps:get(<<"error">>, Json))
              end},

             {"[HTTP-TEST-09] Malformed JSON input rejected (400)",
              fun() ->
                  {ok, {{_, 400, _}, _, _}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/reserve", [{"content-type", "application/json"}], "application/json", "{invalid json"}, [], [])
              end},

             {"[HTTP-TEST-10] Non-existent account query returns 404",
              fun() ->
                  {ok, {{_, 404, _}, _, _}} = httpc:request(get, {BaseUrl ++ "/v1/accounts/nonexistent/balance", []}, [], [])
              end},

             {"[HTTP-TEST-11] GET /v1/reconciliation audit returns PASS",
              fun() ->
                  {ok, {{_, 200, _}, _, Body}} = httpc:request(get, {BaseUrl ++ "/v1/reconciliation", []}, [], []),
                  Json = jsx:decode(list_to_binary(Body), [return_maps]),
                  ?assertEqual(<<"PASS">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(0, maps:get(<<"anomalies_count">>, Json))
              end},

             {"[HTTP-TEST-12] POST /v1/charging/events rates and debits call",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue3">>,
                      <<"session_id">> => <<"http-call-event-01">>,
                      <<"caller">> => <<"sip:ue1@ims.lab">>,
                      <<"callee">> => <<"sip:ue3@ims.lab">>,
                      <<"duration">> => 10.0,
                      <<"service_type">> => <<"voice">>
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/events", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(<<"CHARGED">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(0.5000, maps:get(<<"total_charge">>, Json)),
                  ?assertEqual(29.0000, maps:get(<<"available_balance">>, Json)),
                  ?assertEqual(1.0000, maps:get(<<"consumed_balance">>, Json))
              end},

             {"[HTTP-TEST-13] POST /v1/charging/events idempotency check",
              fun() ->
                  ReqBody = jsx:encode(#{
                      <<"account_id">> => <<"acc-ue3">>,
                      <<"session_id">> => <<"http-call-event-01">>,
                      <<"caller">> => <<"sip:ue1@ims.lab">>,
                      <<"callee">> => <<"sip:ue3@ims.lab">>,
                      <<"duration">> => 10.0,
                      <<"service_type">> => <<"voice">>
                  }),
                  {ok, {{_, 200, _}, _, RespBody}} = httpc:request(post, 
                      {BaseUrl ++ "/v1/charging/events", [{"content-type", "application/json"}], "application/json", binary_to_list(ReqBody)}, [], []),
                  Json = jsx:decode(list_to_binary(RespBody), [return_maps]),
                  ?assertEqual(<<"EXISTING">>, maps:get(<<"status">>, Json)),
                  ?assertEqual(29.0000, maps:get(<<"available_balance">>, Json))
              end}
         ]
     end}.
