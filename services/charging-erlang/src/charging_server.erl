%%%-------------------------------------------------------------------
%%% @doc charging_server
%%% Core gen_server for the Erlang/OTP Telecom Charging & Balance Service.
%%% Manages subscriber account state, reservations, transaction ledger,
%%% rating execution, and financial reconciliation.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_server).
-behaviour(gen_server).

-include("charging_types.hrl").

%% API exports
-export([
    start_link/0,
    start_link/1,
    get_balance/1,
    quote_rate/5,
    reserve/4,
    consume/3,
    refund/2,
    charge_event/6,
    charge_call/1,
    topup/3,
    get_transactions/1,
    get_all_accounts/0,
    get_all_tariffs/0,
    reconcile/0,
    get_metrics/0,
    reset_state/0,
    crash_worker/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).

-record(state, {
    accounts = #{} :: #{binary() => #account{}},
    tariffs = [] :: [#tariff{}],
    rate_plans = [] :: [#rate_plan{}],
    reservations = #{} :: #{binary() => #reservation{}},
    transactions = [] :: [#transaction{}],
    operation_counters = #{} :: #{binary() => non_neg_integer()},
    start_time :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

start_link() ->
    start_link([]).

start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec get_balance(binary()) -> {ok, map()} | {error, term()}.
get_balance(AccountId) ->
    gen_server:call(?SERVER, {get_balance, AccountId}).

-spec quote_rate(binary(), binary(), binary(), binary(), number()) -> {ok, map()} | {error, term()}.
quote_rate(AccountId, Destination, ServiceType, DNN, Units) ->
    gen_server:call(?SERVER, {quote_rate, AccountId, Destination, ServiceType, DNN, Units}).

-spec reserve(binary(), binary(), binary(), float()) -> {ok, map()} | {error, term()}.
reserve(AccountId, SessionId, ServiceType, EstimatedAmount) ->
    gen_server:call(?SERVER, {reserve, AccountId, SessionId, ServiceType, EstimatedAmount}).

-spec consume(binary(), binary(), float()) -> {ok, map()} | {error, term()}.
consume(AccountId, SessionId, ActualCharge) ->
    gen_server:call(?SERVER, {consume, AccountId, SessionId, ActualCharge}).

-spec refund(binary(), binary()) -> {ok, map()} | {error, term()}.
refund(AccountId, SessionId) ->
    gen_server:call(?SERVER, {refund, AccountId, SessionId}).

-spec charge_event(binary(), binary(), binary(), binary(), binary(), number()) -> {ok, map()} | {error, term()}.
charge_event(AccountId, SessionId, Destination, ServiceType, DNN, Units) ->
    gen_server:call(?SERVER, {charge_event, AccountId, SessionId, Destination, ServiceType, DNN, Units}).

-spec charge_call(map()) -> {ok, map()} | {error, term()}.
charge_call(CallMap) when is_map(CallMap) ->
    gen_server:call(?SERVER, {charge_call, CallMap}).

-spec topup(binary(), float(), binary()) -> {ok, map()} | {error, term()}.
topup(AccountId, Amount, Description) ->
    gen_server:call(?SERVER, {topup, AccountId, Amount, Description}).

-spec get_transactions(binary()) -> {ok, [map()]} | {error, term()}.
get_transactions(AccountId) ->
    gen_server:call(?SERVER, {get_transactions, AccountId}).

-spec get_all_accounts() -> {ok, [map()]}.
get_all_accounts() ->
    gen_server:call(?SERVER, get_all_accounts).

-spec get_all_tariffs() -> {ok, [map()]}.
get_all_tariffs() ->
    gen_server:call(?SERVER, get_all_tariffs).

-spec reconcile() -> {ok, map()}.
reconcile() ->
    gen_server:call(?SERVER, reconcile).

-spec get_metrics() -> {ok, map()}.
get_metrics() ->
    gen_server:call(?SERVER, get_metrics).

-spec reset_state() -> ok.
reset_state() ->
    gen_server:call(?SERVER, reset_state).

-spec crash_worker() -> no_return().
crash_worker() ->
    gen_server:cast(?SERVER, crash_worker).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init(_Opts) ->
    State = init_seed_state(),
    logger:info("[charging_server] OTP Charging Server started successfully (PID: ~p)", [self()]),
    {ok, State}.

handle_call({get_balance, AccountId}, _From, State) ->
    {Reply, NewState} = do_get_balance(AccountId, State),
    {reply, Reply, inc_op(<<"balance_inquiry">>, NewState)};

handle_call({quote_rate, AccountId, Dest, ServiceType, DNN, Units}, _From, State) ->
    {Reply, NewState} = do_quote_rate(AccountId, Dest, ServiceType, DNN, Units, State),
    {reply, Reply, inc_op(<<"rating_quote">>, NewState)};

handle_call({reserve, AccountId, SessionId, ServiceType, Amount}, _From, State) ->
    {Reply, NewState} = do_reserve(AccountId, SessionId, ServiceType, Amount, State),
    {reply, Reply, inc_op(<<"reservation_hold">>, NewState)};

handle_call({consume, AccountId, SessionId, ActualCharge}, _From, State) ->
    {Reply, NewState} = do_consume(AccountId, SessionId, ActualCharge, State),
    {reply, Reply, inc_op(<<"reservation_consume">>, NewState)};

handle_call({refund, AccountId, SessionId}, _From, State) ->
    {Reply, NewState} = do_refund(AccountId, SessionId, State),
    {reply, Reply, inc_op(<<"reservation_refund">>, NewState)};

handle_call({charge_event, AccountId, SessionId, Dest, ServiceType, DNN, Units}, _From, State) ->
    CallMap = #{
        <<"account_id">> => AccountId,
        <<"session_id">> => SessionId,
        <<"destination">> => Dest,
        <<"service_type">> => ServiceType,
        <<"dnn">> => DNN,
        <<"duration">> => Units
    },
    {Reply, NewState} = do_charge_call(CallMap, State),
    {reply, Reply, inc_op(<<"call_charged">>, NewState)};

handle_call({charge_call, CallMap}, _From, State) ->
    {Reply, NewState} = do_charge_call(CallMap, State),
    {reply, Reply, inc_op(<<"call_charged">>, NewState)};

handle_call({topup, AccountId, Amount, Description}, _From, State) ->
    {Reply, NewState} = do_topup(AccountId, Amount, Description, State),
    {reply, Reply, inc_op(<<"account_topup">>, NewState)};

handle_call({get_transactions, AccountId}, _From, State) ->
    Reply = do_get_transactions(AccountId, State),
    {reply, Reply, inc_op(<<"transactions_query">>, State)};

handle_call(get_all_accounts, _From, State) ->
    AccountsList = [account_to_map(A) || A <- maps:values(State#state.accounts)],
    {reply, {ok, AccountsList}, State};

handle_call(get_all_tariffs, _From, State) ->
    TariffsList = [tariff_to_map(T) || T <- State#state.tariffs],
    {reply, {ok, TariffsList}, State};

handle_call(reconcile, _From, State) ->
    AccountsList = maps:values(State#state.accounts),
    Reply = charging_reconcile:audit(AccountsList, State#state.transactions),
    {reply, Reply, inc_op(<<"reconciliation">>, State)};

handle_call(get_metrics, _From, State) ->
    Reply = do_get_metrics(State),
    {reply, {ok, Reply}, State};

handle_call(reset_state, _From, _State) ->
    NewState = init_seed_state(),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(crash_worker, _State) ->
    logger:warning("[charging_server] Fault simulation triggered. Crashing process for OTP supervisor test..."),
    exit(simulated_worker_fault);

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, _State) ->
    logger:info("[charging_server] Terminating: ~p", [Reason]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Business Logic Handlers
%%====================================================================

init_seed_state() ->
    Accounts = charging_storage:default_accounts(),
    Tariffs = charging_storage:default_tariffs(),
    RatePlans = charging_storage:default_rate_plans(),
    Transactions = charging_storage:default_transactions(),
    
    AccountMap = maps:from_list([{A#account.id, A} || A <- Accounts]),
    
    #state{
        accounts = AccountMap,
        tariffs = Tariffs,
        rate_plans = RatePlans,
        reservations = #{},
        transactions = Transactions,
        operation_counters = #{},
        start_time = erlang:system_time(second)
    }.

do_get_balance(AccountId, State) ->
    case resolve_account(AccountId, State) of
        {ok, Account} ->
            {{ok, account_to_map(Account)}, State};
        {error, not_found} ->
            {{error, account_not_found}, State}
    end.

do_quote_rate(AccountId, Dest, ServiceType, DNN, Units, State) ->
    case resolve_account(AccountId, State) of
        {error, not_found} ->
            {{error, account_not_found}, State};
        {ok, Account} ->
            case charging_rating:rate_usage(Account, Dest, ServiceType, DNN, Units, State#state.tariffs) of
                {ok, RatedEvent} ->
                    QuoteMap = #{
                        <<"account_id">> => RatedEvent#rated_event.account_id,
                        <<"tariff_id">> => RatedEvent#rated_event.tariff_id,
                        <<"service_type">> => RatedEvent#rated_event.service_type,
                        <<"destination_type">> => RatedEvent#rated_event.destination_type,
                        <<"source_units">> => RatedEvent#rated_event.source_units,
                        <<"billable_units">> => RatedEvent#rated_event.billable_units,
                        <<"setup_charge">> => RatedEvent#rated_event.setup_charge,
                        <<"usage_charge">> => RatedEvent#rated_event.usage_charge,
                        <<"total_charge">> => RatedEvent#rated_event.total_charge,
                        <<"currency">> => RatedEvent#rated_event.currency,
                        <<"explanation">> => RatedEvent#rated_event.explanation
                    },
                    {{ok, QuoteMap}, State};
                {error, Reason} ->
                    {{error, Reason}, State}
            end
    end.

do_reserve(AccountId, SessionId, ServiceType, Amount, State) ->
    AmountF = to_float(Amount),
    case AmountF =< 0.0 of
        true ->
            {{error, invalid_amount}, State};
        false ->
            case resolve_account(AccountId, State) of
                {error, not_found} ->
                    {{error, account_not_found}, State};
                {ok, Account} ->
                    case maps:is_key(SessionId, State#state.reservations) of
                        true ->
                            {{error, duplicate_session_id}, State};
                        false ->
                            case Account#account.balance_available < AmountF of
                                true ->
                                    {{error, insufficient_balance}, State};
                                false ->
                                    OldAvail = Account#account.balance_available,
                                    NewAvail = round4(OldAvail - AmountF),
                                    NewRes   = round4(Account#account.balance_reserved + AmountF),
                                    
                                    UpdatedAccount = Account#account{
                                        balance_available = NewAvail,
                                        balance_reserved = NewRes,
                                        updated_at = current_iso8601()
                                    },

                                    ResId = generate_id(<<"res-">>),
                                    Reservation = #reservation{
                                        id = ResId,
                                        account_id = UpdatedAccount#account.id,
                                        session_id = SessionId,
                                        service_type = ServiceType,
                                        reserved_amount = AmountF,
                                        consumed_amount = 0.0,
                                        status = <<"ACTIVE">>,
                                        expires_at = erlang:system_time(second) + 3600,
                                        created_at = current_iso8601()
                                    },

                                    TxId = generate_id(<<"tx-res-">>),
                                    Tx = #transaction{
                                        id = TxId,
                                        account_id = UpdatedAccount#account.id,
                                        transaction_type = <<"RESERVE">>,
                                        amount = 0.0,
                                        balance_before = OldAvail,
                                        balance_after = NewAvail,
                                        reference_type = <<"reservation">>,
                                        reference_id = SessionId,
                                        description = iolist_to_binary(io_lib:format("Session reservation hold (~4.4f LAB)", [AmountF])),
                                        created_at = current_iso8601()
                                    },

                                    NewAccounts = maps:put(UpdatedAccount#account.id, UpdatedAccount, State#state.accounts),
                                    NewReservations = maps:put(SessionId, Reservation, State#state.reservations),
                                    NewTxs = [Tx | State#state.transactions],

                                    Result = #{
                                        <<"status">> => <<"ACTIVE">>,
                                        <<"reservation_id">> => ResId,
                                        <<"session_id">> => SessionId,
                                        <<"account_id">> => UpdatedAccount#account.id,
                                        <<"reserved_amount">> => AmountF,
                                        <<"available_balance">> => NewAvail,
                                        <<"reserved_balance">> => NewRes,
                                        <<"currency">> => UpdatedAccount#account.currency
                                    },
                                    NewState = State#state{
                                        accounts = NewAccounts,
                                        reservations = NewReservations,
                                        transactions = NewTxs
                                    },
                                    {{ok, Result}, NewState}
                            end
                    end
            end
    end.

do_consume(_AccountId, SessionId, ActualCharge, State) ->
    ChargeF = to_float(ActualCharge),
    case ChargeF < 0.0 of
        true ->
            {{error, invalid_charge_amount}, State};
        false ->
            case maps:find(SessionId, State#state.reservations) of
                error ->
                    {{error, reservation_not_found}, State};
                {ok, #reservation{status = <<"CONSUMED">>}} ->
                    {{error, reservation_already_consumed}, State};
                {ok, #reservation{status = <<"RELEASED">>}} ->
                    {{error, reservation_already_released}, State};
                {ok, #reservation{} = Res} ->
                    AccId = Res#reservation.account_id,
                    Account = maps:get(AccId, State#state.accounts),
                    ReservedAmount = Res#reservation.reserved_amount,
                    
                    case ChargeF =< ReservedAmount of
                        true ->
                            Refund = round4(ReservedAmount - ChargeF),
                            OldAvail = Account#account.balance_available,
                            NewAvail = round4(OldAvail + Refund),
                            NewRes   = round4(Account#account.balance_reserved - ReservedAmount),
                            NewCons  = round4(Account#account.balance_consumed + ChargeF),

                            UpdatedAccount = Account#account{
                                balance_available = NewAvail,
                                balance_reserved = NewRes,
                                balance_consumed = NewCons,
                                updated_at = current_iso8601()
                            },

                            UpdatedRes = Res#reservation{
                                status = <<"CONSUMED">>,
                                consumed_amount = ChargeF
                            },

                            TxId = generate_id(<<"tx-cons-">>),
                            Tx = #transaction{
                                id = TxId,
                                account_id = AccId,
                                transaction_type = <<"CHARGE">>,
                                amount = -ChargeF,
                                balance_before = OldAvail,
                                balance_after = NewAvail,
                                reference_type = <<"rated_usage">>,
                                reference_id = SessionId,
                                description = iolist_to_binary(io_lib:format("Consumed reservation: charge for voice (~4.4f LAB)", [ChargeF])),
                                created_at = current_iso8601()
                            },

                            NewAccounts = maps:put(AccId, UpdatedAccount, State#state.accounts),
                            NewReservations = maps:put(SessionId, UpdatedRes, State#state.reservations),
                            NewTxs = [Tx | State#state.transactions],

                            Result = #{
                                <<"status">> => <<"CONSUMED">>,
                                <<"account_id">> => AccId,
                                <<"session_id">> => SessionId,
                                <<"actual_charge">> => ChargeF,
                                <<"refund_amount">> => Refund,
                                <<"available_balance">> => NewAvail,
                                <<"reserved_balance">> => NewRes,
                                <<"consumed_balance">> => NewCons,
                                <<"currency">> => UpdatedAccount#account.currency
                            },
                            NewState = State#state{
                                accounts = NewAccounts,
                                reservations = NewReservations,
                                transactions = NewTxs
                            },
                            {{ok, Result}, NewState};
                        false ->
                            %% Over-consumption
                            ExtraNeeded = round4(ChargeF - ReservedAmount),
                            case Account#account.balance_available < ExtraNeeded of
                                true ->
                                    {{error, insufficient_balance}, State};
                                false ->
                                    OldAvail = Account#account.balance_available,
                                    NewAvail = round4(OldAvail - ExtraNeeded),
                                    NewRes   = round4(Account#account.balance_reserved - ReservedAmount),
                                    NewCons  = round4(Account#account.balance_consumed + ChargeF),

                                    UpdatedAccount = Account#account{
                                        balance_available = NewAvail,
                                        balance_reserved = NewRes,
                                        balance_consumed = NewCons,
                                        updated_at = current_iso8601()
                                    },

                                    UpdatedRes = Res#reservation{
                                        status = <<"CONSUMED">>,
                                        consumed_amount = ChargeF
                                    },

                                    TxId = generate_id(<<"tx-cons-">>),
                                    Tx = #transaction{
                                        id = TxId,
                                        account_id = AccId,
                                        transaction_type = <<"CHARGE">>,
                                        amount = -ChargeF,
                                        balance_before = OldAvail,
                                        balance_after = NewAvail,
                                        reference_type = <<"rated_usage">>,
                                        reference_id = SessionId,
                                        description = iolist_to_binary(io_lib:format("Consumed reservation: charge for voice (~4.4f LAB)", [ChargeF])),
                                        created_at = current_iso8601()
                                    },

                                    NewAccounts = maps:put(AccId, UpdatedAccount, State#state.accounts),
                                    NewReservations = maps:put(SessionId, UpdatedRes, State#state.reservations),
                                    NewTxs = [Tx | State#state.transactions],

                                    Result = #{
                                        <<"status">> => <<"CONSUMED">>,
                                        <<"account_id">> => AccId,
                                        <<"session_id">> => SessionId,
                                        <<"actual_charge">> => ChargeF,
                                        <<"refund_amount">> => 0.0,
                                        <<"available_balance">> => NewAvail,
                                        <<"reserved_balance">> => NewRes,
                                        <<"consumed_balance">> => NewCons,
                                        <<"currency">> => UpdatedAccount#account.currency
                                    },
                                    NewState = State#state{
                                        accounts = NewAccounts,
                                        reservations = NewReservations,
                                        transactions = NewTxs
                                    },
                                    {{ok, Result}, NewState}
                            end
                    end
            end
    end.

do_refund(_AccountId, SessionId, State) ->
    case maps:find(SessionId, State#state.reservations) of
        error ->
            {{error, reservation_not_found}, State};
        {ok, #reservation{status = Status}} when Status =/= <<"ACTIVE">> ->
            {{error, reservation_already_closed}, State};
        {ok, #reservation{} = Res} ->
            AccId = Res#reservation.account_id,
            Account = maps:get(AccId, State#state.accounts),
            ReservedAmount = Res#reservation.reserved_amount,

            OldAvail = Account#account.balance_available,
            NewAvail = round4(OldAvail + ReservedAmount),
            NewRes   = round4(Account#account.balance_reserved - ReservedAmount),

            UpdatedAccount = Account#account{
                balance_available = NewAvail,
                balance_reserved = NewRes,
                updated_at = current_iso8601()
            },

            UpdatedRes = Res#reservation{
                status = <<"RELEASED">>
            },

            TxId = generate_id(<<"tx-rel-">>),
            Tx = #transaction{
                id = TxId,
                account_id = AccId,
                transaction_type = <<"RELEASE">>,
                amount = 0.0,
                balance_before = OldAvail,
                balance_after = NewAvail,
                reference_type = <<"reservation">>,
                reference_id = SessionId,
                description = iolist_to_binary(io_lib:format("Released reservation hold (~4.4f LAB)", [ReservedAmount])),
                created_at = current_iso8601()
            },

            NewAccounts = maps:put(AccId, UpdatedAccount, State#state.accounts),
            NewReservations = maps:put(SessionId, UpdatedRes, State#state.reservations),
            NewTxs = [Tx | State#state.transactions],

            Result = #{
                <<"status">> => <<"RELEASED">>,
                <<"account_id">> => AccId,
                <<"session_id">> => SessionId,
                <<"refunded_amount">> => ReservedAmount,
                <<"available_balance">> => NewAvail,
                <<"reserved_balance">> => NewRes,
                <<"currency">> => UpdatedAccount#account.currency
            },
            NewState = State#state{
                accounts = NewAccounts,
                reservations = NewReservations,
                transactions = NewTxs
            },
            {{ok, Result}, NewState}
    end.

do_charge_call(CallMap, State) when is_map(CallMap) ->
    SessionId = maps:get(<<"session_id">>, CallMap, maps:get(<<"call_id">>, CallMap, undefined)),
    Caller = maps:get(<<"caller">>, CallMap, <<>>),
    Callee = maps:get(<<"callee">>, CallMap, <<>>),
    case SessionId of
        undefined ->
            {{error, missing_session_id}, State};
        _ ->
            %% Step 1: Idempotency check against existing transactions
            case lists:any(fun(T) -> 
                    T#transaction.reference_id =:= SessionId andalso 
                    T#transaction.transaction_type =:= <<"CHARGE">> 
                 end, State#state.transactions) of
                true ->
                    %% Already charged - find account and existing tx info
                    AccQuery = maps:get(<<"account_id">>, CallMap, undefined),
                    {ok, Account} = case AccQuery of
                        undefined ->
                            resolve_call_account(Caller, Callee, State);
                        _ ->
                            resolve_account(AccQuery, State)
                    end,
                    ExistingResult = #{
                        <<"status">> => <<"EXISTING">>,
                        <<"message">> => <<"Call already charged (idempotent)">>,
                        <<"session_id">> => SessionId,
                        <<"account_id">> => Account#account.id,
                        <<"available_balance">> => Account#account.balance_available,
                        <<"consumed_balance">> => Account#account.balance_consumed,
                        <<"currency">> => Account#account.currency
                    },
                    {{ok, ExistingResult}, State};
                false ->
                    %% Step 2: Resolve account
                    AccQuery = maps:get(<<"account_id">>, CallMap, undefined),
                    AccResult = case AccQuery of
                        undefined ->
                            resolve_call_account(Caller, Callee, State);
                        _ ->
                            resolve_account(AccQuery, State)
                    end,
                    case AccResult of
                        {error, not_found} ->
                            {{error, account_not_found}, State};
                        {ok, Account} ->
                            DestHint = maps:get(<<"destination">>, CallMap, undefined),
                            ServiceType = maps:get(<<"service_type">>, CallMap, <<"voice">>),
                            DNN = maps:get(<<"dnn">>, CallMap, <<"ims">>),
                            Units = to_float(maps:get(<<"duration">>, CallMap, 
                                     maps:get(<<"duration_seconds">>, CallMap, 
                                     maps:get(<<"units">>, CallMap, 10.0)))),

                            %% Step 3: Classify destination & Rate usage
                            Dest = case DestHint of
                                undefined -> 
                                    case Account#account.serving_plmn =/= undefined andalso 
                                         Account#account.serving_plmn =/= Account#account.plmn of
                                        true -> <<"roaming_vplmn">>;
                                        false ->
                                            case binary:match(Callee, [<<"ue3">>, <<"21890">>]) of
                                                nomatch -> <<"domestic">>;
                                                _ -> <<"roaming_vplmn">>
                                            end
                                    end;
                                CustomDest -> CustomDest
                            end,

                            case charging_rating:rate_usage(Account, Dest, ServiceType, DNN, Units, State#state.tariffs) of
                                {error, Reason} ->
                                    {{error, Reason}, State};
                                {ok, #rated_event{} = Rated} ->
                                    ChargeF = Rated#rated_event.total_charge,
                                    OldAvail = Account#account.balance_available,
                                    
                                    %% Step 4: Non-negative balance guard
                                    case OldAvail < ChargeF of
                                        true ->
                                            {{error, insufficient_balance}, State};
                                        false ->
                                            %% Step 5: Debit Available, Credit Consumed, Add Tx
                                            NewAvail = round4(OldAvail - ChargeF),
                                            NewCons = round4(Account#account.balance_consumed + ChargeF),

                                            UpdatedAccount = Account#account{
                                                balance_available = NewAvail,
                                                balance_consumed = NewCons,
                                                updated_at = current_iso8601()
                                            },

                                            TxId = generate_id(<<"tx-call-">>),
                                            Tx = #transaction{
                                                id = TxId,
                                                account_id = UpdatedAccount#account.id,
                                                transaction_type = <<"CHARGE">>,
                                                amount = -ChargeF,
                                                balance_before = OldAvail,
                                                balance_after = NewAvail,
                                                reference_type = <<"rated_call">>,
                                                reference_id = SessionId,
                                                description = Rated#rated_event.explanation,
                                                created_at = current_iso8601()
                                            },

                                            NewAccounts = maps:put(UpdatedAccount#account.id, UpdatedAccount, State#state.accounts),
                                            NewTxs = [Tx | State#state.transactions],

                                            Result = #{
                                                <<"status">> => <<"CHARGED">>,
                                                <<"transaction_id">> => TxId,
                                                <<"account_id">> => UpdatedAccount#account.id,
                                                <<"session_id">> => SessionId,
                                                <<"tariff_id">> => Rated#rated_event.tariff_id,
                                                <<"destination_type">> => Dest,
                                                <<"service_type">> => ServiceType,
                                                <<"duration">> => Units,
                                                <<"billable_units">> => Rated#rated_event.billable_units,
                                                <<"setup_charge">> => Rated#rated_event.setup_charge,
                                                <<"usage_charge">> => Rated#rated_event.usage_charge,
                                                <<"total_charge">> => ChargeF,
                                                <<"available_balance">> => NewAvail,
                                                <<"consumed_balance">> => NewCons,
                                                <<"currency">> => UpdatedAccount#account.currency,
                                                <<"explanation">> => Rated#rated_event.explanation
                                            },
                                            NewState = State#state{
                                                accounts = NewAccounts,
                                                transactions = NewTxs
                                            },
                                            {{ok, Result}, NewState}
                                    end
                            end
                    end
            end
    end.

resolve_call_account(Caller, Callee, State) ->
    case binary:match(Caller, [<<"ue3">>]) =/= nomatch orelse binary:match(Callee, [<<"ue3">>]) =/= nomatch of
        true -> resolve_account(<<"acc-ue3">>, State);
        false ->
            case resolve_account(Caller, State) of
                {ok, Acc} -> {ok, Acc};
                {error, not_found} -> resolve_account(Callee, State)
            end
    end.

do_topup(AccountId, Amount, Description, State) ->
    AmountF = to_float(Amount),
    case AmountF =< 0.0 of
        true ->
            {{error, invalid_topup_amount}, State};
        false ->
            case resolve_account(AccountId, State) of
                {error, not_found} ->
                    {{error, account_not_found}, State};
                {ok, Account} ->
                    OldAvail = Account#account.balance_available,
                    NewAvail = round4(OldAvail + AmountF),

                    UpdatedAccount = Account#account{
                        balance_available = NewAvail,
                        updated_at = current_iso8601()
                    },

                    TxId = generate_id(<<"tx-topup-">>),
                    Tx = #transaction{
                        id = TxId,
                        account_id = UpdatedAccount#account.id,
                        transaction_type = <<"TOPUP">>,
                        amount = AmountF,
                        balance_before = OldAvail,
                        balance_after = NewAvail,
                        reference_type = <<"manual">>,
                        reference_id = TxId,
                        description = Description,
                        created_at = current_iso8601()
                    },

                    NewAccounts = maps:put(UpdatedAccount#account.id, UpdatedAccount, State#state.accounts),
                    NewTxs = [Tx | State#state.transactions],

                    Result = account_to_map(UpdatedAccount),
                    NewState = State#state{
                        accounts = NewAccounts,
                        transactions = NewTxs
                    },
                    {{ok, Result}, NewState}
            end
    end.

do_get_transactions(AccountId, State) ->
    case resolve_account(AccountId, State) of
        {error, not_found} ->
            {error, account_not_found};
        {ok, Account} ->
            AccTxs = [transaction_to_map(T) || T <- State#state.transactions, T#transaction.account_id =:= Account#account.id],
            {ok, AccTxs}
    end.

do_get_metrics(State) ->
    Accounts = maps:values(State#state.accounts),
    TotalAvail = lists:sum([A#account.balance_available || A <- Accounts]),
    TotalRes = lists:sum([A#account.balance_reserved || A <- Accounts]),
    TotalCons = lists:sum([A#account.balance_consumed || A <- Accounts]),
    UptimeSec = erlang:system_time(second) - State#state.start_time,
    
    #{
        <<"service">> => <<"charging-erlang">>,
        <<"status">> => <<"HEALTHY">>,
        <<"uptime_seconds">> => UptimeSec,
        <<"active_accounts_count">> => length(Accounts),
        <<"total_available_balance">> => round4(TotalAvail),
        <<"total_reserved_balance">> => round4(TotalRes),
        <<"total_revenue_charged">> => round4(TotalCons),
        <<"total_transactions_count">> => length(State#state.transactions),
        <<"operations_breakdown">> => State#state.operation_counters
    }.

%% Resolves by ID, SIP URI, IMSI, or MSISDN
resolve_account(Query, State) when is_binary(Query) ->
    case maps:find(Query, State#state.accounts) of
        {ok, Acc} -> {ok, Acc};
        error ->
            Matches = [A || A <- maps:values(State#state.accounts),
                            A#account.sip_uri =:= Query orelse
                            A#account.imsi =:= Query orelse
                            A#account.msisdn =:= Query],
            case Matches of
                [Single | _] -> {ok, Single};
                [] -> {error, not_found}
            end
    end.

inc_op(OpName, #state{operation_counters = Ops} = State) ->
    NewCount = maps:get(OpName, Ops, 0) + 1,
    State#state{operation_counters = maps:put(OpName, NewCount, Ops)}.

account_to_map(#account{} = A) ->
    #{
        <<"account_id">> => A#account.id,
        <<"name">> => A#account.name,
        <<"imsi">> => A#account.imsi,
        <<"msisdn">> => A#account.msisdn,
        <<"sip_uri">> => A#account.sip_uri,
        <<"plmn">> => A#account.plmn,
        <<"serving_plmn">> => A#account.serving_plmn,
        <<"rate_plan">> => A#account.rate_plan,
        <<"balance_available">> => A#account.balance_available,
        <<"balance_reserved">> => A#account.balance_reserved,
        <<"balance_consumed">> => A#account.balance_consumed,
        <<"currency">> => A#account.currency,
        <<"status">> => A#account.status,
        <<"created_at">> => A#account.created_at,
        <<"updated_at">> => A#account.updated_at
    }.

tariff_to_map(#tariff{} = T) ->
    #{
        <<"tariff_id">> => T#tariff.id,
        <<"rate_plan_id">> => T#tariff.rate_plan_id,
        <<"service_type">> => T#tariff.service_type,
        <<"destination_type">> => T#tariff.destination_type,
        <<"dnn">> => T#tariff.dnn,
        <<"setup_charge">> => T#tariff.setup_charge,
        <<"unit_rate">> => T#tariff.unit_rate,
        <<"unit_size">> => T#tariff.unit_size,
        <<"min_units">> => T#tariff.min_units,
        <<"granularity_units">> => T#tariff.granularity_units,
        <<"rounding_policy">> => T#tariff.rounding_policy
    }.

transaction_to_map(#transaction{} = T) ->
    #{
        <<"transaction_id">> => T#transaction.id,
        <<"account_id">> => T#transaction.account_id,
        <<"transaction_type">> => T#transaction.transaction_type,
        <<"amount">> => T#transaction.amount,
        <<"balance_before">> => T#transaction.balance_before,
        <<"balance_after">> => T#transaction.balance_after,
        <<"reference_type">> => T#transaction.reference_type,
        <<"reference_id">> => T#transaction.reference_id,
        <<"description">> => T#transaction.description,
        <<"created_at">> => T#transaction.created_at
    }.

to_float(N) when is_integer(N) -> float(N);
to_float(N) when is_float(N) -> N;
to_float(B) when is_binary(B) ->
    try binary_to_float(B)
    catch _:_ -> float(binary_to_integer(B))
    end.

round4(Float) ->
    round(Float * 10000.0) / 10000.0.

generate_id(Prefix) ->
    Unique = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    <<Prefix/binary, Unique/binary>>.

current_iso8601() ->
    {{Y, M, D}, {H, MM, S}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ", [Y, M, D, H, MM, S])).
