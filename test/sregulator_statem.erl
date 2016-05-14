%%-------------------------------------------------------------------
%%
%% Copyright (c) 2016, James Fish <james@fishcakez.com>
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License. You may obtain
%% a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied. See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%%-------------------------------------------------------------------
-module(sregulator_statem).

%% ask_r is replaced by bid to help separate the difference between ask and
%% ask_r.

-include_lib("proper/include/proper.hrl").

-export([quickcheck/0]).
-export([quickcheck/1]).
-export([check/1]).
-export([check/2]).

-export([initial_state/0]).
-export([command/1]).
-export([precondition/2]).
-export([next_state/3]).
-export([postcondition/3]).
-export([cleanup/1]).

-export([start_link/1]).
-export([init/1]).
-export([spawn_client/2]).
-export([client_init/2]).
-export([continue/2]).
-export([done/2]).
-export([cancel/2]).
-export([change_config/2]).
-export([shutdown_client/2]).
-export([replace_state/2]).
-export([change_code/3]).

-record(state, {sregulator, queue=[], queue_mod, queue_out, queue_drops,
                queue_state=[], valve=[], valve_mod, valve_opens,
                valve_state=[], valve_status, cancels=[], done=[], sys=running,
                change}).

-define(TIMEOUT, 5000).

quickcheck() ->
    quickcheck([]).

quickcheck(Opts) ->
    proper:quickcheck(prop_sregulator(), Opts).

check(CounterExample) ->
    check(CounterExample, []).

check(CounterExample, Opts) ->
    proper:check(prop_sregulator(), CounterExample, Opts).

prop_sregulator() ->
    ?FORALL(Cmds, commands(?MODULE),
            ?TRAPEXIT(begin
                          {History, State, Result} = run_commands(?MODULE, Cmds),
                          cleanup(State),
                          ?WHENFAIL(begin
                                        io:format("History~n~p", [History]),
                                        io:format("State~n~p", [State]),
                                        io:format("Result~n~p", [Result])
                                    end,
                                    aggregate(command_names(Cmds), Result =:= ok))
                      end)).


initial_state() ->
    #state{}.

command(#state{sregulator=undefined} = State) ->
    {call, ?MODULE, start_link, start_link_args(State)};
command(#state{sys=running} = State) ->
    frequency([{20, {call, sregulator, update, update_args(State)}},
               {10, {call, ?MODULE, spawn_client,
                     spawn_client_args(State)}},
               {4, {call, ?MODULE, continue, continue_args(State)}},
               {3, {call, ?MODULE, done, done_args(State)}},
               {3, {call, sregulator, timeout, timeout_args(State)}},
               {3, {call, ?MODULE, cancel, cancel_args(State)}},
               {2, {call, sregulator, len, len_args(State)}},
               {2, {call, sregulator, size, size_args(State)}},
               {2, {call, ?MODULE, change_config,
                    change_config_args(State)}},
               {2, {call, ?MODULE, shutdown_client,
                    shutdown_client_args(State)}},
               {1, {call, sys, get_status, get_status_args(State)}},
               {1, {call, sys, get_state, get_state_args(State)}},
               {1, {call, ?MODULE, replace_state, replace_state_args(State)}},
               {1, {call, sys, suspend, suspend_args(State)}}]);
command(#state{sys=suspended} = State) ->
    frequency([{5, {call, sys, resume, resume_args(State)}},
               {2, {call, ?MODULE, change_code, change_code_args(State)}},
               {1, {call, sys, get_status, get_status_args(State)}},
               {1, {call, sys, get_state, get_state_args(State)}},
               {1, {call, ?MODULE, replace_state, replace_state_args(State)}}]).

precondition(State, {call, _, start_link, Args}) ->
    start_link_pre(State, Args);
precondition(#state{sregulator=undefined}, _) ->
    false;
precondition(State, {call, _, suspend, Args}) ->
    suspend_pre(State, Args);
precondition(State, {call, _, change_code, Args}) ->
    change_code_pre(State, Args);
precondition(State, {call, _, resume, Args}) ->
    resume_pre(State, Args);
precondition(#state{sys=suspended}, _) ->
    false;
precondition(_State, _Call) ->
    true.

next_state(State, Value, {call, _, start_link, Args}) ->
    start_link_next(State, Value, Args);
next_state(State, Value, {call, _, update, Args}) ->
    update_next(State, Value, Args);
next_state(State, Value, {call, _, spawn_client, Args}) ->
    spawn_client_next(State, Value, Args);
next_state(State, Value, {call, _, continue, Args}) ->
    continue_next(State, Value, Args);
next_state(State, Value, {call, _, done, Args}) ->
    done_next(State, Value, Args);
next_state(State, Value, {call, _, timeout, Args}) ->
    timeout_next(State, Value, Args);
next_state(State, Value, {call, _, cancel, Args}) ->
    cancel_next(State, Value, Args);
next_state(State, Value, {call, _, len, Args}) ->
    len_next(State, Value, Args);
next_state(State, Value, {call, _, size, Args}) ->
    size_next(State, Value, Args);
next_state(State, Value, {call, _, change_config, Args}) ->
    change_config_next(State, Value, Args);
next_state(State, Value, {call, _, shutdown_client, Args}) ->
    shutdown_client_next(State, Value, Args);
next_state(State, Value, {call, _, get_status, Args}) ->
    get_status_next(State, Value, Args);
next_state(State, Value, {call, _, get_state, Args}) ->
    get_state_next(State, Value, Args);
next_state(State, Value, {call, _, replace_state, Args}) ->
    replace_state_next(State, Value, Args);
next_state(State, Value, {call, _, suspend, Args}) ->
    suspend_next(State, Value, Args);
next_state(State, Value, {call, _, change_code, Args}) ->
    change_code_next(State, Value, Args);
next_state(State, Value, {call, _, resume, Args}) ->
    resume_next(State, Value, Args);
next_state(State, _Value, _Call) ->
    State.

postcondition(State, {call, _, start_link, Args}, Result) ->
    start_link_post(State, Args, Result);
postcondition(State, {call, _, update, Args}, Result) ->
    update_post(State, Args, Result);
postcondition(State, {call, _, spawn_client, Args}, Result) ->
    spawn_client_post(State, Args, Result);
postcondition(State, {call, _, continue, Args}, Result) ->
    continue_post(State, Args, Result);
postcondition(State, {call, _, done, Args}, Result) ->
    done_post(State, Args, Result);
postcondition(State, {call, _, timeout, Args}, Result) ->
   timeout_post(State, Args, Result);
postcondition(State, {call, _, cancel, Args}, Result) ->
    cancel_post(State, Args, Result);
postcondition(State, {call, _, len, Args}, Result) ->
    len_post(State, Args, Result);
postcondition(State, {call, _, size, Args}, Result) ->
    size_post(State, Args, Result);
postcondition(State, {call, _, change_config, Args}, Result) ->
    change_config_post(State, Args, Result);
postcondition(State, {call, _, shutdown_client, Args}, Result) ->
    shutdown_client_post(State, Args, Result);
postcondition(State, {call, _, get_status, Args}, Result) ->
    get_status_post(State, Args, Result);
postcondition(State, {call, _, get_state, Args}, Result) ->
    get_state_post(State, Args, Result);
postcondition(State, {call, _, replace_state, Args}, Result) ->
    replace_state_post(State, Args, Result);
postcondition(State, {call, _, suspend, Args}, Result) ->
    suspend_post(State, Args, Result);
postcondition(State, {call, _, change_code, Args}, Result) ->
    change_code_post(State, Args, Result);
postcondition(State, {call, _, resume, Args}, Result) ->
    resume_post(State, Args, Result);
postcondition(_State, _Call, _Result) ->
    true.

cleanup(#state{sregulator=undefined}) ->
    application:unset_env(sbroker, ?MODULE);
cleanup(#state{sregulator=Regulator}) ->
    application:unset_env(sbroker, ?MODULE),
    Trap = process_flag(trap_exit, true),
    exit(Regulator, shutdown),
    receive
        {'EXIT', Regulator, shutdown} ->
            _ = process_flag(trap_exit, Trap),
            ok
    after
        3000 ->
            exit(Regulator, kill),
            _ = process_flag(trap_exit, Trap),
            exit(timeout)
    end.

start_link_args(_) ->
    [init()].

init() ->
    frequency([{30, {ok, {queue_spec(), valve_spec(), meter_spec()}}},
               {1, ignore},
               {1, bad}]).

queue_spec() ->
    {oneof([sbroker_statem_queue, sbroker_statem2_queue]),
     {oneof([out, out_r]),
      ?SUCHTHAT(Drops, resize(4, list(oneof([0, choose(1, 2)]))),
                Drops =/= [])}}.

valve_spec() ->
    {oneof([sregulator_statem_valve, sregulator_statem2_valve]),
     ?SUCHTHAT(Opens, list(oneof([open, closed])), Opens =/= [])}.

meter_spec() ->
    {sbroker_alarm_meter, {0, 10, ?MODULE}}.

start_link(Init) ->
    application:set_env(sbroker, ?MODULE, Init),
    Trap = process_flag(trap_exit, true),
    case sregulator:start_link(?MODULE, [], [{read_time_after, 2}]) of
        {error, Reason} = Error ->
            receive
                {'EXIT', _, Reason} ->
                    process_flag(trap_exit, Trap),
                    Error
            after
                100 ->
                    exit({timeout, Error})
            end;
        Other ->
            process_flag(trap_exit, Trap),
            Other
    end.

init([]) ->
    {ok, Result} = application:get_env(sbroker, ?MODULE),
    Result.

start_link_pre(#state{sregulator=Regulator}, _) ->
    Regulator =:= undefined.

start_link_next(State, Value,
                [{ok, {{QMod, {QOut, QDrops}},
                       {VMod, [Open | VState] = VOpens},
                       _}}]) ->
    Regulator = {call, erlang, element, [2, Value]},
    State#state{sregulator=Regulator, queue_mod=QMod, queue_out=QOut,
                queue_drops=QDrops, queue_state=QDrops, valve_mod=VMod,
                valve_opens=VOpens, valve_state=VState, valve_status=Open};
start_link_next(State, _, [ignore]) ->
    State;
start_link_next(State, _, [bad]) ->
    State.

start_link_post(_, [{ok, _}], {ok, Regulator}) when is_pid(Regulator) ->
    true;
start_link_post(_, [ignore], ignore) ->
    true;
start_link_post(_, [bad], {error, {bad_return_value, bad}}) ->
    true;
start_link_post(_, _, _) ->
    false.

update_args(#state{sregulator=Regulator}) ->
    [Regulator, choose(-10, 10), ?TIMEOUT].

update_next(State, _, _) ->
    valve_next(State).

update_post(State, _, _) ->
    valve_post(State).

spawn_client_args(#state{sregulator=Regulator}) ->
    [Regulator, oneof([async_ask, nb_ask])].

spawn_client(Broker, Fun) ->
    {ok, Pid, MRef} = proc_lib:start(?MODULE, client_init, [Broker, Fun]),
    {Pid, MRef}.

spawn_client_next(#state{valve_status=open, queue=[], valve=V} = State, Client,
             [_, _]) ->
    valve_next(State#state{valve=V++[Client]});
spawn_client_next(#state{valve_status=closed} = State, _, [_, nb_ask]) ->
    queue_next(State);
spawn_client_next(#state{valve_status=closed, queue=Q} = State, Client,
                  [_, async_ask]) ->
    queue_next(State#state{queue=Q++[Client]}).

spawn_client_post(#state{valve_status=open, queue=[], valve=V} = State,
                  [_, _], Client) ->
    go_post(Client) andalso valve_post(State#state{valve=V++[Client]});
spawn_client_post(#state{valve_status=closed} = State, [_, nb_ask], _) ->
    queue_post(State);
spawn_client_post(#state{valve_status=closed, queue=Q} = State, [_, async_ask],
                  Client) ->
    queue_post(State#state{queue=Q++[Client]}).

continue(Regulator, undefined) ->
    Result = sregulator:continue(Regulator, make_ref()),
    element(1, Result);
continue(_, Client) ->
    client_call(Client, continue).

continue_args(#state{sregulator=Regulator, queue=Q, valve=V, done=Done,
                     cancels=Cancels}) ->
    case Q ++ V ++ Done ++ Cancels of
        [] ->
            [Regulator, undefined];
        Clients ->
            [Regulator, frequency([{9, elements(Clients)},
                                   {1, undefined}])]
    end.

continue_next(#state{valve_state=[], valve_opens=VState} = State, Value,
              Args) ->
    continue_next(State#state{valve_state=VState}, Value, Args);
continue_next(#state{valve_state=[open | VState], valve=V} = State, _,
              [_, Client]) ->
    case lists:member(Client, V) of
        true ->
            valve_next(State#state{valve_status=open, valve_state=VState});
        false ->
            valve_next(State)
    end;
continue_next(#state{valve_state=[closed | VState], valve=V} = State, _,
              [_, Client]) ->
    case lists:member(Client, V) of
        true ->
            NState = State#state{valve_status=closed, valve_state=VState,
                                 valve=V--[Client]},
            valve_next(NState);
        false ->
            valve_next(State)
    end.

continue_post(#state{valve_state=[], valve_opens=VState} = State, Args,
              Result) ->
    continue_post(State#state{valve_state=VState}, Args, Result);
continue_post(#state{valve_state=[open | VState], valve=V} = State, [_, Client],
              Result) ->
    case lists:member(Client, V) of
        true ->
            NState = State#state{valve_status=open, valve_state=VState},
            call_post(Client,go, Result) andalso valve_post(NState);
        false ->
            call_post(Client, not_found, Result) andalso valve_post(State)
    end;
continue_post(#state{valve_state=[closed | VState], valve=V} = State,
              [_, Client], Result) ->
    case lists:member(Client, V) of
        true ->
            NState = State#state{valve_status=closed, valve_state=VState,
                                 valve=V--[Client]},
            call_post(Client, stop, Result) andalso valve_post(NState);
        false ->
            call_post(Client, not_found, Result) andalso valve_post(State)
    end.

done(Regulator, undefined) ->
    Result = sregulator:done(Regulator, make_ref(), ?TIMEOUT),
    element(1, Result);
done(_, Client) ->
    client_call(Client, done).

done_args(State) ->
    continue_args(State).

done_next(#state{valve_state=[], valve_opens=VState} = State, Value,
              Args) ->
    done_next(State#state{valve_state=VState}, Value, Args);
done_next(#state{valve=V} = State, _, [_, Client]) ->
    valve_next(State#state{valve=V--[Client]}).

done_post(#state{valve_state=[], valve_opens=VState} = State, Args,
              Result) ->
    done_post(State#state{valve_state=VState}, Args, Result);
done_post(#state{valve=V} = State, [_, Client], Result) ->
    Post = valve_post(State#state{valve=V--[Client]}),
    case lists:member(Client, V) of
        true ->
            Post andalso call_post(Client, stop, Result);
        false ->
            Post andalso call_post(Client, not_found, Result)
    end.

timeout_args(#state{sregulator=Regulator}) ->
    [Regulator].

timeout_next(State, _, _) ->
    queue_next(State).

timeout_post(State, _, _) ->
    queue_post(State).

cancel_args(State) ->
    continue_args(State).

cancel(Regulator, undefined) ->
    sregulator:cancel(Regulator, make_ref(), ?TIMEOUT);
cancel(_, Client) ->
    client_call(Client, cancel).

cancel_next(#state{queue=Q, cancels=Cancels} =State, _, [_, Client]) ->
    case lists:member(Client, Q) of
        true ->
            queue_next(State#state{queue=Q--[Client],
                                   cancels=Cancels++[Client]});
        false ->
            queue_next(State)
    end.

cancel_post(#state{queue=Q} = State, [_, Client], Result) ->
    case lists:member(Client, Q) of
        true when Result =:= 1 ->
            queue_post(State#state{queue=Q--[Client]});
        true ->
            ct:pal("Cancel: ~p", [Result]),
            false;
        false when Result =:= false ->
            queue_post(State#state{queue=Q--[Client]});
        false ->
            ct:pal("Cancel: ~p", [Result]),
            false
    end.

len_args(#state{sregulator=Regulator}) ->
    [Regulator, ?TIMEOUT].

len_next(State, _, _) ->
    queue_next(State).

len_post(#state{queue=Q} = State, _, Len) ->
    length(Q) =:= Len andalso queue_post(State).

size_args(State) ->
    len_args(State).

size_next(State, _, _) ->
    queue_next(State).

size_post(#state{valve=V} = State, _, Size) ->
    length(V) =:= Size andalso queue_post(State).

change_config_args(#state{sregulator=Regulator}) ->
    [Regulator, init()].

change_config(Regulator, Init) ->
    application:set_env(sbroker, ?MODULE, Init),
    sregulator:change_config(Regulator, 100).

change_config_next(State, _, [_, ignore]) ->
    queue_next(State);
change_config_next(State, _, [_, bad]) ->
    queue_next(State);
change_config_next(State, _, [_, {ok, {QSpec, VSpec, _}}]) ->
    NState = queue_change_next(QSpec, State),
    valve_change_next(VSpec, NState).

change_config_post(State, [_, ignore], ok) ->
    queue_post(State);
change_config_post(State, [_, bad], {error, {bad_return_value, bad}}) ->
    queue_post(State);
change_config_post(State, [_, {ok, {QSpec, VSpec, _}}], ok) ->
    queue_change_post(QSpec, State) andalso
    valve_change_post(VSpec, queue_change_next(QSpec, State));
change_config_post(_, _, _) ->
    false.


shutdown_client_args(State) ->
    continue_args(State).

shutdown_client(Regulator, undefined) ->
    _ = Regulator ! {'DOWN', make_ref(), process, self(), shutdown},
    ok;
shutdown_client(_, Client) ->
    Pid = client_pid(Client),
    MRef = monitor(process, Pid),
    exit(Pid, shutdown),
    receive
        {'DOWN', MRef, _, _, shutdown} ->
            timer:sleep(50),
            ok;
        {'DOWN', MRef, _, _, Reason} ->
            exit(Reason)
    after
        100 ->
            exit(timeout)
    end.


shutdown_client_next(State, _, [_, undefined]) ->
    queue_next(State, fun valve_next/1);
shutdown_client_next(#state{queue=Q, valve=V, cancels=Cancels,
                            done=Done} = State, _, [_, Client]) ->
    case lists:member(Client, Q) orelse lists:member(Client, V) of
        true ->
            queue_next(State#state{queue=Q--[Client]},
                       fun(#state{valve=NV, done=NDone} = NState) ->
                               NState2 = NState#state{valve=NV--[Client],
                                                      done=NDone--[Client]},
                               valve_next(NState2)
                       end);
        false ->
            State#state{cancels=Cancels--[Client], done=Done--[Client]}
    end.

shutdown_client_post(State, [_, undefined], _) ->
    queue_post(State, fun valve_post/1);
shutdown_client_post(#state{queue=Q, valve=V} = State, [_, Client], _) ->
    case lists:member(Client, Q) orelse lists:member(Client, V) of
        true ->
            {Drops, NState} = queue_aqm(State#state{queue=Q--[Client]}),
            #state{valve=NV, cancels=Cancels, done=Done} = NState,
            NState2 = NState#state{valve=NV--[Client],
                                   cancels=Cancels--[Client],
                                   done=Done--[Client]},
            drops_post(Drops--[Client]) andalso valve_post(NState2);
        false ->
            true
    end.

get_status_args(State) ->
    sys_args(State).

get_status_next(State, _, _) ->
    sys_next(State).

get_status_post(#state{sregulator=Regulator, sys=Sys} = State, _,
                {status, Pid, {module, Mod},
                 [_, SysState, Parent, _, Status]}) ->
    Pid =:= Regulator andalso Mod =:= sregulator andalso
    SysState =:= Sys andalso Parent =:= self() andalso
    status_post(State, Status) andalso sys_post(State);
get_status_post(_, _, Result) ->
    ct:pal("Full status: ~p", [Result]),
    false.

get_state_args(State) ->
    sys_args(State).

get_state_next(State, _, _) ->
    sys_next(State).

get_state_post(State, _, Result) ->
    get_state_post(State, Result) andalso sys_post(State).

replace_state_args(State) ->
    sys_args(State).

replace_state(Regulator, Timeout) ->
    sys:replace_state(Regulator, fun(Q) -> Q end, Timeout).

replace_state_next(State, _, _) ->
    sys_next(State).

replace_state_post(State, _, Result) ->
    get_state_post(State, Result) andalso sys_post(State).

suspend_args(State) ->
    sys_args(State).

suspend_pre(#state{sys=SysState}, _) ->
    SysState =:= running.

suspend_next(State, _, _) ->
    State#state{sys=suspended}.

suspend_post(_, _, _) ->
    true.

change_code_args(#state{sregulator=Regulator}) ->
    [Regulator, init(), ?TIMEOUT].

change_code(Broker, Init, Timeout) ->
    application:set_env(sbroker, ?MODULE, Init),
    sys:change_code(Broker, undefined, undefined, undefined, Timeout).

change_code_pre(#state{sys=SysState}, _) ->
    SysState =:= suspended.

change_code_next(State, _, [_, {ok, _} = Init, _]) ->
    State#state{change=Init};
change_code_next(State, _, _) ->
    State.

change_code_post(_, [_, {ok, _}, _], ok) ->
    true;
change_code_post(_, [_, ignore, _], ok) ->
    true;
change_code_post(_, [_, bad, _], {error, {bad_return_value, bad}}) ->
    true;
change_code_post(_, _, _) ->
    false.

resume_args(State) ->
    sys_args(State).

resume_pre(#state{sys=SysState}, _) ->
    SysState =:= suspended.

resume_next(#state{change={ok, {QSpec, VSpec, _}}} = State, _, _) ->
    NState = State#state{sys=running, change=undefined},
    NState2 = queue_change_next(QSpec, NState),
    valve_change_next(VSpec, NState2);
resume_next(State, _, _) ->
    queue_next(State#state{sys=running}).

resume_post(#state{change={ok, {QSpec, VSpec, _}}} = State, _,
            _) ->
    queue_change_post(QSpec, State) andalso
    valve_change_post(VSpec, queue_change_next(QSpec, State));
resume_post(State, _, _) ->
    queue_post(State).

%% helpers

valve_next(#state{valve_state=[], valve_opens=[_|_] = VState} = State) ->
    valve_next(State#state{valve_state=VState});
valve_next(#state{valve_state=[open | VState]} = State) ->
    NState = State#state{valve_status=open, valve_state=VState},
    queue_next(NState,
               fun(#state{queue=[], queue_drops=QDrops} = NState2) ->
                       NState2#state{queue_state=QDrops};
                  (#state{queue_out=out, queue=Q, valve=V} = NState2) ->
                       NState3 = NState2#state{queue=tl(Q),
                                               valve=V++[hd(Q)]},
                       valve_next(NState3);
                  (#state{queue_out=out_r, queue=Q, valve=V} = NState2) ->
                       NState3 = NState2#state{queue=lists:droplast(Q),
                                               valve=V++[lists:last(Q)]},
                       valve_next(NState3)
               end);
valve_next(#state{valve_state=[closed | VState]} = State) ->
    State#state{valve_status=closed, valve_state=VState}.

valve_post(#state{valve_state=[], valve_opens=VState} = State) ->
    valve_post(State#state{valve_state=VState});
valve_post(#state{valve_state=[open | VState]} = State) ->
    NState = State#state{valve_status=open, valve_state=VState},
    queue_post(NState,
               fun(#state{queue=[]}) ->
                       true;
                  (#state{queue_out=out, queue=Q, valve=V} = NState2) ->
                       Client = hd(Q),
                       NState3 = NState2#state{queue=tl(Q),
                                               valve=V++[Client]},
                       go_post(Client) andalso valve_post(NState3);
                  (#state{queue_out=out_r, queue=Q, valve=V} = NState2) ->
                       Client = lists:last(Q),
                       NState3 = NState2#state{queue=lists:droplast(Q),
                                               valve=V++[Client]},
                       go_post(Client) andalso valve_post(NState3)
               end);
valve_post(_) ->
    true.

queue_next(State) ->
    queue_next(State, fun(NState) -> NState end).

queue_next(State, Fun) ->
    {_, NState} = queue_aqm(State),
    Fun(NState).

queue_post(State) ->
    queue_post(State, fun(_) -> true end).

queue_post(State, Fun) ->
    {Drops, NState} = queue_aqm(State),
    drops_post(Drops) andalso Fun(NState).

queue_aqm(#state{queue_state=[], queue_drops=QDrops} = State) ->
    queue_aqm(State#state{queue_state=QDrops});
queue_aqm(#state{queue=[]} = State) ->
    {[], State};
queue_aqm(#state{queue=Q, queue_state=[Drop | QState], done=Done} = State) ->
    Drop2 = min(length(Q), Drop),
    {Drops, NQ} = lists:split(Drop2, Q),
    {Drops, State#state{queue=NQ, queue_state=QState, done=Done++Drops}}.

go_post(Client) ->
    case client_call(Client, result) of
        {go, _, _, _, _} ->
            true;
        Other ->
            ct:pal("~p Go: ~p", [Client, Other]),
            false
    end.

drops_post([Client | Drops]) ->
    case client_result(Client) of
        {drop, _} ->
            drops_post(Drops);
        Other ->
            ct:pal("~p Drop: ~p", [Client, Other]),
            false
    end;
drops_post([]) ->
    true.

call_post(_, Expected, Observed) when Expected == Observed ->
    true;
call_post(Client, Expected, Observed) ->
    ct:pal("Call for ~p~nExpected: ~p~nObserved: ~p",
           [Client, Expected, Observed]),
    false.

queue_change_next({QMod, {QOut, QDrops}},
           #state{queue_mod=QMod, queue_drops=QDrops} = State) ->
    queue_next(State#state{queue_out=QOut});
%% If module and/or args different reset the backend state.
queue_change_next({QMod, {QOut, QDrops}}, State) ->
    queue_next(State#state{queue_mod=QMod, queue_out=QOut, queue_drops=QDrops,
                           queue_state=QDrops}).

queue_change_post({QMod, {QOut, QDrops}},
           #state{queue_mod=QMod, queue_drops=QDrops} = State) ->
    queue_post(State#state{queue_out=QOut});
%% If module and/or args different reset the backend state.
queue_change_post({QMod, {QOut, QDrops}}, State) ->
    queue_post(State#state{queue_mod=QMod, queue_out=QOut, queue_drops=QDrops,
                           queue_state=QDrops}).

valve_change_next({VMod, VOpens},
           #state{valve_mod=VMod, valve_opens=VOpens} = State) ->
    valve_next(State);
%% If module and/or args different reset the backend state.
valve_change_next({VMod, VOpens}, State) ->
    valve_next(State#state{valve_mod=VMod, valve_opens=VOpens,
                           valve_state=VOpens}).

valve_change_post({VMod, VOpens},
           #state{valve_mod=VMod, valve_opens=VOpens} = State) ->
    valve_post(State);
%% If module and/or args different reset the backend state.
valve_change_post({VMod, VOpens}, State) ->
    valve_post(State#state{valve_mod=VMod, valve_opens=VOpens,
                           valve_state=VOpens}).

sys_args(#state{sregulator=Regulator}) ->
    [Regulator, ?TIMEOUT].

sys_next(#state{sys=running} = State) ->
    queue_next(State);
sys_next(#state{sys=suspended} = State) ->
    State.

sys_post(#state{sys=running} = State) ->
    queue_post(State);
sys_post(#state{sys=suspended}) ->
    true.

status_post(#state{valve_status=VStatus, sys=Sys} = State,
            [{header, "Status for sregulator <" ++_ },
             {data, [{"Status", SysState},
                     {"Parent", Self},
                     {"State", RegState},
                     {"Time", {TimeMod, Time}}]},
             {items, {"Installed handlers", Handlers}}]) ->
    SysState =:= Sys andalso Self =:= self() andalso
    RegState == VStatus andalso
    ((erlang:function_exported(erlang, monotonic_time, 0) andalso
      TimeMod =:= erlang) orelse TimeMod =:= sbroker_legacy) andalso
    is_integer(Time) andalso
    get_state_post(State, Handlers);
status_post(_, Status) ->
    ct:pal("Status: ~p", [Status]),
    false.

get_state_post(State, Handlers) ->
    get_queue_post(State, Handlers) andalso get_valve_post(State, Handlers).

get_queue_post(#state{queue_mod=QMod, queue=Q}, Handlers) ->
    case lists:keyfind(queue, 2, Handlers) of
        {QMod, queue, QState} ->
            QMod:len(QState) == length(Q);
        QInfo ->
            ct:pal("Queue: ~p", [QInfo]),
            false
    end.

get_valve_post(#state{valve_mod=VMod, valve=V}, Handlers) ->
    case lists:keyfind(valve, 2, Handlers) of
        {VMod, valve, VState} ->
            VMod:size(VState) == length(V);
        VInfo ->
            ct:pal("Valve: ~p", [VInfo]),
            false
    end.

%% client

client_result(Client) ->
    client_call(Client, result).

client_pid({Pid, _}) ->
    Pid.

client_call({Pid, MRef}, Call) ->
    try gen:call(Pid, MRef, Call, 100) of
        {ok, Response} ->
            Response
    catch
        exit:Reason ->
            {exit, Reason}
    end.

client_init(Regulator, async_ask) ->
    MRef = monitor(process, Regulator),
    ARef = make_ref(),
    {await, ARef, Regulator} = sregulator:async_ask(Regulator, ARef),
    client_init(MRef, Regulator, ARef, undefined, queued);
client_init(Regulator, nb_ask) ->
    MRef = monitor(process, Regulator),
    case sregulator:nb_ask(Regulator) of
        {go, VRef, _, _, _} = State ->
            client_init(MRef, Regulator, undefined, VRef, State);
        State ->
            client_init(MRef, Regulator, undefined, undefined, State)
    end.

client_init(MRef, Regulator, ARef, VRef, State) ->
    proc_lib:init_ack({ok, self(), MRef}),
    client_loop(MRef, Regulator, ARef, VRef, State, []).

client_loop(MRef, Regulator, ARef, VRef, State, Froms) ->
    receive
        {'DOWN', MRef, _, _, _} ->
            exit(normal);
        {ARef, {go, NVRef, _, _, _} = Result} when State =:= queued ->
            _ = [gen:reply(From, Result) || From <- Froms],
            client_loop(MRef, Regulator, ARef, NVRef, Result, []);
        {ARef, Result} when State =:= queued ->
            _ = [gen:reply(From, Result) || From <- Froms],
            client_loop(MRef, Regulator, ARef, VRef, Result, []);
        {ARef, Result} when State =/= queued ->
            exit(Regulator, {double_result, {self(), MRef}, State, Result}),
            exit(normal);
        {MRef, From, continue} ->
            case sregulator:continue(Regulator, VRef) of
                {go, VRef, Regulator, _, _} ->
                    gen:reply(From, go),
                    client_loop(MRef, Regulator, ARef, VRef, State, Froms);
                {stop, _} ->
                    gen:reply(From, stop),
                    client_loop(MRef, Regulator, ARef, VRef, done, Froms);
                {not_found, _} ->
                    gen:reply(From, not_found),
                    client_loop(MRef, Regulator, ARef, VRef, State, Froms)
            end;
        {MRef, From, done} ->
            case sregulator:done(Regulator, VRef, ?TIMEOUT) of
                {stop, _} ->
                    gen:reply(From, stop),
                    client_loop(MRef, Regulator, ARef, VRef, done, Froms);
                {not_found, _} ->
                    gen:reply(From, not_found),
                    client_loop(MRef, Regulator, ARef, VRef, State, Froms)
            end;
        {MRef, From, cancel} ->
            case sregulator:cancel(Regulator, ARef, ?TIMEOUT) of
                N when is_integer(N) ->
                    gen:reply(From, N),
                    client_loop(MRef, Regulator, ARef, VRef, cancelled, Froms);
                false ->
                    gen:reply(From, false),
                    client_loop(MRef, Regulator, ARef, VRef, State, Froms)
            end;
        {MRef, From, result} when State =:= queued ->
            client_loop(MRef, Regulator, ARef, VRef, State, [From | Froms]);
        {MRef, From, result} ->
            gen:reply(From, State),
            client_loop(MRef, Regulator, ARef, VRef, State, Froms)
    end.