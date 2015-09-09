%%%-------------------------------------------------------------------
%%% @author Shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 25. Aug 2015 9:11 PM
%%%-------------------------------------------------------------------
-module(login_server).
-author("Shuieryin").

-behaviour(gen_server).

%% API
-export([start_link/0,
    is_uid_registered/1,
    is_in_registration/1,
    register_uid/2,
    registration_done/1,
    get_uid_profile/1,
    remove_user/1]).

-define(R_REGISTERED_UID_MAP, registered_uid_map).
-define(REGISTRATION_FSM_MAP, registration_fsm_map).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    format_status/2]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() ->
    {ok, Pid} |
    ignore |
    {error, Reason} when

    Pid :: pid(),
    Reason :: term().
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Check if uid is registered
%%
%% @end
%%--------------------------------------------------------------------
-spec is_uid_registered(Uid) -> boolean() when
    Uid :: atom().
is_uid_registered(Uid) ->
    gen_server:call(?MODULE, {is_uid_registered, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Get user profile
%%
%% @end
%%--------------------------------------------------------------------
-spec get_uid_profile(Uid) -> UidProfile | null when
    UidProfile :: map(),
    Uid :: atom().
get_uid_profile(Uid) ->
    gen_server:call(?MODULE, {get_uid_profile, Uid}).

%%--------------------------------------------------------------------
%% @doc
%% Check if uid is in registration process
%%
%% @end
%%--------------------------------------------------------------------
-spec is_in_registration(Uid) -> boolean() when
    Uid :: atom().
is_in_registration(Uid) ->
    gen_server:call(?MODULE, {is_in_registration, Uid}).

-spec register_uid(DispatcherUid, Uid) -> no_return() when
    Uid :: atom(),
    DispatcherUid :: pid().
register_uid(DispatcherUid, Uid) ->
    gen_server:cast(?MODULE, {register_uid, DispatcherUid, Uid}).

-spec registration_done(State) -> ok when
    State :: map().
registration_done(State) ->
    gen_server:cast(?MODULE, {registration_done, State}),
    ok.

-spec remove_user(Uid) -> no_return() when
    Uid :: atom().
remove_user(Uid) ->
    gen_server:call(?MODULE, {remove_user, Uid}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec init(Args) ->
    {ok, State} |
    {ok, State, timeout() | hibernate} |
    {stop, Reason} |
    ignore when

    Args :: term(),
    State :: map(),
    Reason :: term().
init([]) ->
    io:format("~p starting~n", [?MODULE]),
    RegisteredUidMap = case redis_client_server:get(?R_REGISTERED_UID_MAP) of
                           undefined ->
                               NewMap = #{},
                               redis_client_server:set(?R_REGISTERED_UID_MAP, NewMap, true),
                               NewMap;
                           ExistingMap ->
                               error_logger:info_msg("ExistingMap found:~p~n", [ExistingMap]),
                               ExistingMap
                       end,
    {ok, #{?R_REGISTERED_UID_MAP => RegisteredUidMap, ?REGISTRATION_FSM_MAP => #{}}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request, From, State) ->
    {reply, Reply, NewState} |
    {reply, Reply, NewState, timeout() | hibernate} |
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, Reply, NewState} |
    {stop, Reason, NewState} when

    Request :: {is_uid_registered | is_in_registration | registration_done | get_uid_profile | remove_user, Uid},
    Uid :: atom(),
    From :: {pid(), Tag :: term()},
    Reply :: term(),
    State :: map(),
    NewState :: map(),
    Reason :: term().
handle_call({is_uid_registered, Uid}, _From, State) ->
    RegisteredUidMap = maps:get(?R_REGISTERED_UID_MAP, State),
    {reply, maps:is_key(Uid, RegisteredUidMap), State};
handle_call({is_in_registration, Uid}, _From, State) ->
    RegistrationFsmMap = maps:get(?REGISTRATION_FSM_MAP, State),
    Result = maps:is_key(Uid, RegistrationFsmMap),
    {reply, Result, State};
handle_call({get_uid_profile, Uid}, _From, State) ->
    {reply, maps:get(Uid, maps:get(?R_REGISTERED_UID_MAP, State), null), State};
handle_call({remove_user, Uid}, _From, State) ->
    RegisteredUidMap = maps:get(?R_REGISTERED_UID_MAP, State),
    UpdatedRegisteredUidMap = maps:remove(Uid, RegisteredUidMap),
    redis_client_server:set(?R_REGISTERED_UID_MAP, UpdatedRegisteredUidMap, true),
    {reply, ok, State#{?R_REGISTERED_UID_MAP := UpdatedRegisteredUidMap}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request, State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Request :: {registration_done, UserState} | {register_uid, DispatcherPid, Uid},
    DispatcherPid :: pid(),
    Uid :: atom(),
    UserState :: map(),
    State :: map(),
    NewState :: map(),
    Reason :: term().
handle_cast({registration_done, UserState}, State) ->
    RegistrationFsmMap = maps:get(?REGISTRATION_FSM_MAP, State),
    RedisRegistrationUidMap = maps:get(?R_REGISTERED_UID_MAP, State),

    Uid = maps:get(uid, UserState),
    UpdatedRedisRegistrationUidMap = maps:put(Uid, UserState, RedisRegistrationUidMap),
    redis_client_server:set(?R_REGISTERED_UID_MAP, UpdatedRedisRegistrationUidMap, true),

    {noreply, State#{?R_REGISTERED_UID_MAP => UpdatedRedisRegistrationUidMap, ?REGISTRATION_FSM_MAP => maps:remove(Uid, RegistrationFsmMap)}};
handle_cast({register_uid, DispatcherPid, Uid}, State) ->
    RegistrationFsmMap = maps:get(?REGISTRATION_FSM_MAP, State),
    case maps:is_key(Uid, RegistrationFsmMap) of
        false ->
            {ok, FsmPid} = register_fsm:start(DispatcherPid, Uid),
            UpdatedState = State#{?REGISTRATION_FSM_MAP => maps:put(Uid, FsmPid, RegistrationFsmMap)};
        _ ->
            gen_fsm:send_all_state_event(Uid, {restart, DispatcherPid}),
            UpdatedState = State
    end,
    {noreply, UpdatedState}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info | term(), State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Info :: timeout(),
    State :: map(),
    NewState :: map(),
    Reason :: term().
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason, State) -> term() when
    Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: map().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn, State, Extra) ->
    {ok, NewState} |
    {error, Reason} when

    OldVsn :: term() | {down, term()},
    State :: map(),
    Extra :: term(),
    NewState :: map(),
    Reason :: term().
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is useful for customising the form and
%% appearance of the gen_server status for these cases.
%%
%% @spec format_status(Opt, StatusData) -> Status
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt, StatusData) -> Status when
    Opt :: 'normal' | 'terminate',
    StatusData :: [PDict | State],
    PDict :: [{Key :: term(), Value :: term()}],
    State :: term(),
    Status :: term().
format_status(Opt, StatusData) ->
    gen_server:format_status(Opt, StatusData).

%%%===================================================================
%%% Internal functions
%%%===================================================================
