%%%-------------------------------------------------------------------
%%% @doc charging_http
%%% GenServer managing the Cowboy HTTP listener lifecycle.
%%% @end
%%%-------------------------------------------------------------------
-module(charging_http).
-behaviour(gen_server).

-export([
    start_link/0,
    start_link/1,
    get_port/0,
    stop/0
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 8085).

-record(state, {
    port :: pos_integer(),
    listener_ref :: atom()
}).

%%====================================================================
%% API Functions
%%====================================================================

start_link() ->
    Port = application:get_env(charging_service, http_port, ?DEFAULT_PORT),
    start_link(Port).

start_link(Port) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Port], []).

get_port() ->
    gen_server:call(?SERVER, get_port).

stop() ->
    gen_server:stop(?SERVER).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([Port]) ->
    ListenerRef = charging_http_listener,
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/[...]", charging_http_handler, []}
        ]}
    ]),
    
    %% Stop existing listener if any
    try cowboy:stop_listener(ListenerRef) catch _:_ -> ok end,

    case cowboy:start_clear(ListenerRef, [{port, Port}], #{env => #{dispatch => Dispatch}}) of
        {ok, _Pid} ->
            logger:info("[charging_http] Cowboy HTTP listener running on port ~p", [Port]),
            {ok, #state{port = Port, listener_ref = ListenerRef}};
        {error, Reason} ->
            logger:error("[charging_http] Failed to start Cowboy on port ~p: ~p", [Port, Reason]),
            {stop, Reason}
    end.

handle_call(get_port, _From, State) ->
    {reply, {ok, State#state.port}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    try cowboy:stop_listener(State#state.listener_ref) catch _:_ -> ok end,
    logger:info("[charging_http] Cowboy HTTP listener stopped"),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
