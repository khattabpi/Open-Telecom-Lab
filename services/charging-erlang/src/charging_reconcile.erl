%%%-------------------------------------------------------------------
%%% @doc charging_reconcile
%%% Multi-point financial reconciliation engine in Erlang.
%%% Formally validates mathematical invariants across accounts and ledger.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_reconcile).

-include("charging_types.hrl").

-export([
    audit/2
]).

-spec audit([#account{}], [#transaction{}]) -> {ok, map()}.
audit(Accounts, Transactions) ->
    %% 1. Invariant 1: Conservation of Account Equity per account
    {EquityAnomalies, AccountDetails} = lists:foldl(fun(Acc, {AnomAcc, DetailsAcc}) ->
        AccTxs = [T || T <- Transactions, T#transaction.account_id =:= Acc#account.id],
        TxNetSum = lists:sum([T#transaction.amount || T <- AccTxs]),
        ExpectedEquity = round4(Acc#account.balance_available + Acc#account.balance_reserved),
        CalculatedEquity = round4(TxNetSum),
        Variance = abs(ExpectedEquity - CalculatedEquity),
        
        IsAnomaly = Variance > 0.001,
        NewAnomAcc = case IsAnomaly of
            true ->
                Msg = iolist_to_binary(io_lib:format("Equity variance on ~s: bal ~4.4f vs tx sum ~4.4f (delta: ~4.4f)", 
                    [Acc#account.id, ExpectedEquity, CalculatedEquity, Variance])),
                [Msg | AnomAcc];
            false ->
                AnomAcc
        end,
        
        AccInfo = #{
            <<"account_id">> => Acc#account.id,
            <<"balance_available">> => Acc#account.balance_available,
            <<"balance_reserved">> => Acc#account.balance_reserved,
            <<"balance_consumed">> => Acc#account.balance_consumed,
            <<"transaction_count">> => length(AccTxs),
            <<"equity_match">> => not IsAnomaly
        },
        {NewAnomAcc, [AccInfo | DetailsAcc]}
    end, {[], []}, Accounts),

    %% 2. Invariant 2: Aggregate Cash Reconciliation
    TotalAvailable = round4(lists:sum([A#account.balance_available || A <- Accounts])),
    TotalReserved  = round4(lists:sum([A#account.balance_reserved || A <- Accounts])),
    TotalConsumed  = round4(lists:sum([A#account.balance_consumed || A <- Accounts])),
    
    TopupTxs = [T || T <- Transactions, T#transaction.transaction_type =:= <<"TOPUP">>],
    TotalTopups = round4(lists:sum([T#transaction.amount || T <- TopupTxs])),

    CashSum = round4(TotalAvailable + TotalConsumed + TotalReserved),
    CashVariance = abs(CashSum - TotalTopups),
    CashAnomalies = case CashVariance > 0.001 of
        true ->
            [iolist_to_binary(io_lib:format("Cash aggregate mismatch: avail+cons+res ~4.4f vs topups ~4.4f (delta ~4.4f)", 
                [CashSum, TotalTopups, CashVariance]))];
        false ->
            []
    end,

    %% 3. Invariant 3: Single-Charge Idempotency per reference_id
    ChargeTxs = [T || T <- Transactions, T#transaction.transaction_type =:= <<"CHARGE">>, T#transaction.reference_id =/= <<>>],
    RefIds = [T#transaction.reference_id || T <- ChargeTxs],
    DupRefAnomalies = find_duplicates(RefIds),

    AllAnomalies = EquityAnomalies ++ CashAnomalies ++ DupRefAnomalies,
    Status = case length(AllAnomalies) of
        0 -> <<"PASS">>;
        _ -> <<"FAIL">>
    end,

    Report = #{
        <<"status">> => Status,
        <<"accounts_audited">> => length(Accounts),
        <<"total_available">> => TotalAvailable,
        <<"total_reserved">> => TotalReserved,
        <<"total_consumed">> => TotalConsumed,
        <<"total_topups">> => TotalTopups,
        <<"anomalies_count">> => length(AllAnomalies),
        <<"anomalies">> => AllAnomalies,
        <<"account_details">> => lists:reverse(AccountDetails)
    },
    {ok, Report}.

find_duplicates(List) ->
    find_duplicates(lists:sort(List), []).

find_duplicates([], Acc) -> Acc;
find_duplicates([_], Acc) -> Acc;
find_duplicates([H, H | Rest], Acc) ->
    Msg = iolist_to_binary(io_lib:format("Duplicate charge transaction for reference_id: ~s", [H])),
    find_duplicates([H | Rest], [Msg | Acc]);
find_duplicates([_ | Rest], Acc) ->
    find_duplicates(Rest, Acc).

round4(Float) ->
    round(Float * 10000.0) / 10000.0.
