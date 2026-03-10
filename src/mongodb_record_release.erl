-module(mongodb_record_release).

-export([init/1]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    {ok, State1} = mongodb_record_release_prv:init(State),
    {ok, State1}.
