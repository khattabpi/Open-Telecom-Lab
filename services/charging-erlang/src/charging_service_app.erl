%%%-------------------------------------------------------------------
%%% @doc charging_service_app
%%% Application callback module for the Telecom Charging Service.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_service_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    charging_service_sup:start_link().

stop(_State) ->
    ok.
