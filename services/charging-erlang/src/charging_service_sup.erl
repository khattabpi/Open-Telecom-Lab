%%%-------------------------------------------------------------------
%%% @doc charging_service_sup
%%% Root OTP Supervisor for the Telecom Charging Service.
%%% Manages charging_server (state & business logic) and charging_http (API).
%%% Implements one_for_one fault-tolerant supervision.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_service_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },

    ChildSpecs = [
        #{
            id => charging_server,
            start => {charging_server, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [charging_server]
        },
        #{
            id => charging_http,
            start => {charging_http, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [charging_http]
        }
    ],

    {ok, {SupFlags, ChildSpecs}}.
