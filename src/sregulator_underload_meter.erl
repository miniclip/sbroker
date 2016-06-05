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
%% @doc Sets a SASL `alarm_handler' alarm when the regulator's valve is slow to
%% get match for an interval. Once the valve becomes fast for an interval the
%% alarm is cleared.
%%
%% `sregulator_underload_meter' can be used in a `sregulator'. Its argument is
%% of the form:
%% ```
%% {Target :: integer(), Interval :: pos_integer(), AlarmId :: any()}
%% '''
%% `Target' is the target relative time of the valve in milliseconds. The
%% meter will set the alarm `AlarmId' in `alarm_handler' if the relative time of
%% the valve is above the target for `Interval' milliseconds. Once set
%% if the relative time is below `Target'  for `Interval' milliseconds the alarm
%% is cleared. The description of the alarm is `{valve_slow, Pid}' where
%% `Pid' is the `pid()' of the process.
%%
%% This meter is only intended for a `sregulator' because a `sregulator_valve'
%% will remain open when processes that should be available are not sending
%% requests and can not do anything to correct this. Whereas a `sbroker' can
%% not distinguish between one queue receiving too many requests or the other
%% too few. In either situation the congested `sbroker_queue' would drop
%% requests to correct the imbalance, causing a congestion alarm to be cleared
%% very quickly.
-module(sregulator_underload_meter).

-behaviour(sbroker_meter).

-export([init/2]).
-export([handle_update/5]).
-export([handle_info/3]).
-export([code_change/4]).
-export([config_change/3]).
-export([terminate/2]).

-record(state, {target :: integer(),
                interval :: pos_integer(),
                alarm_id :: any(),
                status = clear :: clear | set,
                toggle_next = infinity :: integer() | infinity}).

%% @private
-spec init(Time, {Target, Interval, AlarmId}) -> {State, infinity} when
      Time :: integer(),
      Target :: integer(),
      Interval :: pos_integer(),
      AlarmId :: any(),
      State :: #state{}.
init(_, {Target, Interval, AlarmId}) ->
    alarm_handler:clear_alarm(AlarmId),
    State = #state{target=sbroker_util:relative_target(Target),
                   interval=sbroker_util:interval(Interval), alarm_id=AlarmId},
    {State, infinity}.

%% @private
-spec handle_update(QueueDelay, ProcessDelay, RelativeTime, Time, State) ->
    {NState, Next} when
      QueueDelay :: non_neg_integer(),
      ProcessDelay :: non_neg_integer(),
      RelativeTime :: integer(),
      Time :: integer(),
      State :: #state{},
      NState :: #state{},
      Next :: integer() | infinity.
handle_update(_, _, RelativeTime, Time,
              #state{status=clear, target=Target, interval=Interval,
                     alarm_id=AlarmId, toggle_next=ToggleNext} = State) ->
    if
        -RelativeTime < Target andalso ToggleNext == infinity ->
            {State, ToggleNext};
        -RelativeTime < Target ->
            {State#state{toggle_next=infinity}, infinity};
        ToggleNext =:= infinity ->
            NToggleNext = Time + Interval,
            {State#state{toggle_next=NToggleNext}, NToggleNext};
        ToggleNext > Time ->
            {State, ToggleNext};
        true ->
            alarm_handler:set_alarm({AlarmId, {valve_slow, self()}}),
            {State#state{status=set, toggle_next=infinity}, infinity}
    end;
handle_update(_, _, RelativeTime, Time,
              #state{status=set, target=Target, interval=Interval,
                     alarm_id=AlarmId, toggle_next=ToggleNext} = State) ->
    if
        -RelativeTime < Target andalso ToggleNext == infinity ->
            NToggleNext = Time + Interval,
            {State#state{toggle_next=NToggleNext}, NToggleNext};
        -RelativeTime < Target andalso ToggleNext > Time ->
            {State, ToggleNext};
        -RelativeTime < Target ->
            alarm_handler:clear_alarm(AlarmId),
            {State#state{status=clear, toggle_next=infinity}, infinity};
        ToggleNext =:= infinity ->
            {State, infinity};
        true ->
            {State#state{toggle_next=infinity}, infinity}
    end.

%% @private
-spec handle_info(Msg, Time, State) -> {State, Next} when
      Msg :: any(),
      Time :: integer(),
      State :: #state{},
      Next :: integer() | infinity.
handle_info(_, Time, #state{toggle_next=ToggleNext} = State) ->
    {State, max(Time, ToggleNext)}.

%% @private
-spec code_change(OldVsn, Time, State, Extra) -> {NState, Next} when
      OldVsn :: any(),
      Time :: integer(),
      State :: #state{},
      Extra :: any(),
      NState :: #state{},
      Next :: integer() | infinity.
code_change(_, Time, #state{toggle_next=ToggleNext} = State, _) ->
    {State, max(Time, ToggleNext)}.

%% @private
-spec config_change({Target, Interval, AlarmId}, Time, State) ->
    {NState, Next} when
      Target :: integer(),
      Interval :: pos_integer(),
      AlarmId :: any(),
      Time :: integer(),
      State :: #state{},
      NState :: #state{},
      Next :: integer() | infinity.
config_change({Target, NInterval, AlarmId}, Time,
              #state{alarm_id=AlarmId, interval=Interval,
                     toggle_next=ToggleNext} = State) ->
    NTarget = sbroker_util:relative_target(Target),
    NInterval2 = sbroker_util:interval(NInterval),
    NState = State#state{target=NTarget, interval=NInterval2, alarm_id=AlarmId},
    case ToggleNext of
        infinity ->
            {NState, infinity};
        _ ->
            NToggleNext = ToggleNext+NInterval2-Interval,
            {NState#state{toggle_next=NToggleNext}, max(Time, NToggleNext)}
    end;
config_change(Args, Time, #state{status=set, alarm_id=AlarmId}) ->
    alarm_handler:clear_alarm(AlarmId),
    init(Time, Args);
config_change(Args, Time, _) ->
    init(Time, Args).

%% @private
-spec terminate(Reason, State) -> ok when
      Reason :: any(),
      State :: #state{}.
terminate(_, #state{status=set, alarm_id=AlarmId}) ->
    alarm_handler:clear_alarm(AlarmId);
terminate(_, _) ->
    ok.
