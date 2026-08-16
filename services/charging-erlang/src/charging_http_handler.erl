%%%-------------------------------------------------------------------
%%% @doc charging_http_handler
%%% Cowboy HTTP request handler for the Telecom Charging REST API.
%%% Handles routing, JSON decoding/encoding via jsx, and status codes.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_http_handler).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    Req = handle_request(Method, Path, Req0),
    {ok, Req, State}.

%%--------------------------------------------------------------------
%% GET /health
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/health">>, Req) ->
    OtpRelease = list_to_binary(erlang:system_info(otp_release)),
    Payload = #{
        <<"status">> => <<"UP">>,
        <<"service">> => <<"charging-erlang">>,
        <<"version">> => <<"1.0.0">>,
        <<"otp_release">> => OtpRelease,
        <<"timestamp">> => current_iso8601()
    },
    reply_json(200, Payload, Req);

%%--------------------------------------------------------------------
%% GET /metrics
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/metrics">>, Req) ->
    {ok, Metrics} = charging_server:get_metrics(),
    reply_json(200, Metrics, Req);

%%--------------------------------------------------------------------
%% GET /v1/reconciliation
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/v1/reconciliation">>, Req) ->
    {ok, Report} = charging_server:reconcile(),
    StatusCode = case maps:get(<<"status">>, Report) of
        <<"PASS">> -> 200;
        _ -> 500
    end,
    reply_json(StatusCode, Report, Req);

%%--------------------------------------------------------------------
%% GET /v1/accounts
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/v1/accounts">>, Req) ->
    {ok, Accounts} = charging_server:get_all_accounts(),
    reply_json(200, #{<<"accounts">> => Accounts, <<"count">> => length(Accounts)}, Req);

%%--------------------------------------------------------------------
%% GET /v1/tariffs
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/v1/tariffs">>, Req) ->
    {ok, Tariffs} = charging_server:get_all_tariffs(),
    reply_json(200, #{<<"tariffs">> => Tariffs, <<"count">> => length(Tariffs)}, Req);

%%--------------------------------------------------------------------
%% GET /v1/accounts/:account_id/balance
%%--------------------------------------------------------------------
handle_request(<<"GET">>, <<"/v1/accounts/", Rest/binary>>, Req) ->
    case binary:split(Rest, <<"/">>, [global]) of
        [AccountId, <<"balance">>] ->
            case charging_server:get_balance(AccountId) of
                {ok, Account} ->
                    reply_json(200, Account, Req);
                {error, account_not_found} ->
                    reply_error(404, <<"Account not found">>, Req);
                {error, Reason} ->
                    reply_error(500, Reason, Req)
            end;
        [AccountId, <<"transactions">>] ->
            case charging_server:get_transactions(AccountId) of
                {ok, Txs} ->
                    reply_json(200, #{<<"account_id">> => AccountId, <<"transactions">> => Txs, <<"count">> => length(Txs)}, Req);
                {error, account_not_found} ->
                    reply_error(404, <<"Account not found">>, Req);
                {error, Reason} ->
                    reply_error(500, Reason, Req)
            end;
        _ ->
            reply_error(404, <<"Endpoint not found">>, Req)
    end;

%%--------------------------------------------------------------------
%% POST /v1/rating/quote
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/rating/quote">>, Req0) ->
    with_json_body(Req0, fun(Body, Req) ->
        AccountId   = maps:get(<<"account_id">>, Body, undefined),
        Destination = maps:get(<<"destination">>, Body, <<"domestic">>),
        ServiceType = maps:get(<<"service_type">>, Body, <<"voice">>),
        DNN         = maps:get(<<"dnn">>, Body, <<"any">>),
        Duration    = maps:get(<<"duration">>, Body, maps:get(<<"units">>, Body, 0.0)),

        case AccountId =/= undefined of
            false ->
                reply_error(400, <<"Missing required field: account_id">>, Req);
            true ->
                case charging_server:quote_rate(AccountId, Destination, ServiceType, DNN, Duration) of
                    {ok, Quote} ->
                        reply_json(200, Quote, Req);
                    {error, account_not_found} ->
                        reply_error(404, <<"Account not found">>, Req);
                    {error, Reason} ->
                        reply_error(400, iolist_to_binary(io_lib:format("Rating failed: ~p", [Reason])), Req)
                end
        end
    end);

%%--------------------------------------------------------------------
%% POST /v1/charging/reserve
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/charging/reserve">>, Req0) ->
    with_json_body(Req0, fun(Body, Req) ->
        AccountId   = maps:get(<<"account_id">>, Body, undefined),
        SessionId   = maps:get(<<"session_id">>, Body, undefined),
        ServiceType = maps:get(<<"service_type">>, Body, <<"voice">>),
        EstAmount   = maps:get(<<"estimated_amount">>, Body, maps:get(<<"amount">>, Body, undefined)),

        case {AccountId, SessionId, EstAmount} of
            {undefined, _, _} -> reply_error(400, <<"Missing required field: account_id">>, Req);
            {_, undefined, _} -> reply_error(400, <<"Missing required field: session_id">>, Req);
            {_, _, undefined} -> reply_error(400, <<"Missing required field: estimated_amount">>, Req);
            _ ->
                case charging_server:reserve(AccountId, SessionId, ServiceType, EstAmount) of
                    {ok, Res} ->
                        reply_json(200, Res, Req);
                    {error, insufficient_balance} ->
                        reply_error(402, <<"Insufficient balance for reservation">>, Req);
                    {error, account_not_found} ->
                        reply_error(404, <<"Account not found">>, Req);
                    {error, duplicate_session_id} ->
                        reply_error(409, <<"Duplicate active session reservation">>, Req);
                    {error, Reason} ->
                        reply_error(400, iolist_to_binary(io_lib:format("Reservation failed: ~p", [Reason])), Req)
                end
        end
    end);

%%--------------------------------------------------------------------
%% POST /v1/charging/consume
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/charging/consume">>, Req0) ->
    with_json_body(Req0, fun(Body, Req) ->
        AccountId   = maps:get(<<"account_id">>, Body, undefined),
        SessionId   = maps:get(<<"session_id">>, Body, undefined),
        ActualCharge = maps:get(<<"actual_charge">>, Body, maps:get(<<"amount">>, Body, undefined)),

        case {AccountId, SessionId, ActualCharge} of
            {undefined, _, _} -> reply_error(400, <<"Missing required field: account_id">>, Req);
            {_, undefined, _} -> reply_error(400, <<"Missing required field: session_id">>, Req);
            {_, _, undefined} -> reply_error(400, <<"Missing required field: actual_charge">>, Req);
            _ ->
                case charging_server:consume(AccountId, SessionId, ActualCharge) of
                    {ok, Result} ->
                        reply_json(200, Result, Req);
                    {error, reservation_not_found} ->
                        reply_error(404, <<"Active reservation not found">>, Req);
                    {error, insufficient_balance} ->
                        reply_error(402, <<"Insufficient balance for over-consumption">>, Req);
                    {error, Reason} ->
                        reply_error(400, iolist_to_binary(io_lib:format("Consume failed: ~p", [Reason])), Req)
                end
        end
    end);

%%--------------------------------------------------------------------
%% POST /v1/charging/refund
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/charging/refund">>, Req0) ->
    with_json_body(Req0, fun(Body, Req) ->
        AccountId = maps:get(<<"account_id">>, Body, undefined),
        SessionId = maps:get(<<"session_id">>, Body, undefined),

        case {AccountId, SessionId} of
            {undefined, _} -> reply_error(400, <<"Missing required field: account_id">>, Req);
            {_, undefined} -> reply_error(400, <<"Missing required field: session_id">>, Req);
            _ ->
                case charging_server:refund(AccountId, SessionId) of
                    {ok, Result} ->
                        reply_json(200, Result, Req);
                    {error, reservation_not_found} ->
                        reply_error(404, <<"Active reservation not found">>, Req);
                    {error, Reason} ->
                        reply_error(400, iolist_to_binary(io_lib:format("Refund failed: ~p", [Reason])), Req)
                end
        end
    end);

%%--------------------------------------------------------------------
%% POST /v1/charging/events
%% POST /v1/charging/call
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/charging/events">>, Req0) ->
    handle_charge_call_request(Req0);
handle_request(<<"POST">>, <<"/v1/charging/call">>, Req0) ->
    handle_charge_call_request(Req0);

%%--------------------------------------------------------------------
%% POST /v1/accounts/:account_id/topup
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/accounts/", Rest/binary>>, Req0) ->
    case binary:split(Rest, <<"/">>, [global]) of
        [AccountId, <<"topup">>] ->
            with_json_body(Req0, fun(Body, Req) ->
                Amount = maps:get(<<"amount">>, Body, undefined),
                Description = maps:get(<<"description">>, Body, <<"Manual Account Topup">>),
                case Amount of
                    undefined ->
                        reply_error(400, <<"Missing required field: amount">>, Req);
                    _ ->
                        case charging_server:topup(AccountId, Amount, Description) of
                            {ok, Account} ->
                                reply_json(200, Account, Req);
                            {error, account_not_found} ->
                                reply_error(404, <<"Account not found">>, Req);
                            {error, Reason} ->
                                reply_error(400, iolist_to_binary(io_lib:format("Topup failed: ~p", [Reason])), Req)
                        end
                end
            end);
        _ ->
            reply_error(404, <<"Endpoint not found">>, Req0)
    end;

%%--------------------------------------------------------------------
%% POST /v1/fault/simulate (Supervision Test)
%%--------------------------------------------------------------------
handle_request(<<"POST">>, <<"/v1/fault/simulate">>, Req) ->
    charging_server:crash_worker(),
    reply_json(200, #{<<"message">> => <<"Simulated worker fault injected. Supervisor will restart charging_server.">>}, Req);

%%--------------------------------------------------------------------
%% Fallthrough 404
%%--------------------------------------------------------------------
handle_request(_Method, _Path, Req) ->
    reply_error(404, <<"Endpoint not found">>, Req).

%%--------------------------------------------------------------------
%% Helper Functions
%%--------------------------------------------------------------------
handle_charge_call_request(Req0) ->
    with_json_body(Req0, fun(Body, Req) ->
        case charging_server:charge_call(Body) of
            {ok, Result} ->
                reply_json(200, Result, Req);
            {error, insufficient_balance} ->
                reply_error(402, <<"Insufficient balance for call charging">>, Req);
            {error, account_not_found} ->
                reply_error(404, <<"Account not found">>, Req);
            {error, missing_session_id} ->
                reply_error(400, <<"Missing required field: session_id or call_id">>, Req);
            {error, Reason} ->
                reply_error(400, iolist_to_binary(io_lib:format("Call charging failed: ~p", [Reason])), Req)
        end
    end).

with_json_body(Req0, Fun) ->
    case cowboy_req:has_body(Req0) of
        false ->
            reply_error(400, <<"Missing request body">>, Req0);
        true ->
            {ok, RawBody, Req1} = cowboy_req:read_body(Req0),
            try jsx:decode(RawBody, [return_maps]) of
                Body when is_map(Body) ->
                    Fun(Body, Req1);
                _ ->
                    reply_error(400, <<"Invalid JSON body format">>, Req1)
            catch
                _:_ ->
                    reply_error(400, <<"Malformed JSON payload">>, Req1)
            end
    end.

reply_json(Status, MapData, Req) ->
    Headers = #{
        <<"content-type">> => <<"application/json">>,
        <<"server">> => <<"Erlang-OTP/25 cowboy/2.10.0">>
    },
    Body = jsx:encode(MapData),
    cowboy_req:reply(Status, Headers, Body, Req).

reply_error(Status, Message, Req) when is_binary(Message) ->
    Payload = #{
        <<"error">> => true,
        <<"status_code">> => Status,
        <<"message">> => Message,
        <<"timestamp">> => current_iso8601()
    },
    reply_json(Status, Payload, Req);
reply_error(Status, Message, Req) ->
    reply_error(Status, iolist_to_binary(io_lib:format("~p", [Message])), Req).

current_iso8601() ->
    {{Y, M, D}, {H, MM, S}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, M, D, H, MM, S])).
