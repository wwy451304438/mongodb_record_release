-module(mongodb_record_release_prv).

-export([init/1, do/1, format_error/1]).

-behaviour(provider).

-define(PROVIDER, mongodb_record_release).
-define(DEPS, [app_discovery]).

init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, true},
        {deps, ?DEPS},
        {short_desc, "Generate MongoDB record metadata"},
        {desc, "Generate MongoDB record metadata from Erlang headers"},
        {example, "rebar3 mongodb_record_release"},
        {opts, []}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

do(State) ->
    Config = rebar_state:get(State, mongodb_record_release_plugin, []),
    HeaderPaths = proplists:get_value(header_paths, Config, ["include"]),
    OutputPath = proplists:get_value(output_path, Config, "src"),
    Macros = proplists:get_value(macros, Config, []),
    case mongodb_record_release_util:init(HeaderPaths, Macros) of
        {ok, Records} when map_size(Records) > 0 ->
            case validate_records(Records) of
                ok -> generate_mongodb_record_data(Records, OutputPath, HeaderPaths, State);
                {error, Reason} -> {error, io_lib:format("Invalid record definitions: ~p", [Reason])}
            end;
        {ok, _Records} ->
            {error, "No record definitions found in configured header paths"};
        {error, Reason} ->
            {error, io_lib:format("Failed to parse records: ~p", [Reason])}
    end.

format_error(Reason) ->
    io_lib:format("~ts", [Reason]).

validate_records(Records) ->
    Reserved = ['_record', '_erlang_type', '_codec_version'],
    Invalid = lists:sort([
        {RecordName, FieldName}
        || {RecordName, Fields} <- maps:to_list(Records),
           FieldName <- Fields,
           lists:member(FieldName, Reserved)
    ]),
    case Invalid of
        [] -> ok;
        _ -> {error, {reserved_record_fields, Invalid}}
    end.

generate_mongodb_record_data(Records, OutputPath, HeaderPaths, State) ->
    RecordList = lists:sort(maps:to_list(Records)),
    Content = iolist_to_binary(build_module(RecordList, HeaderPaths)),
    FileName = filename:join(OutputPath, "mongodb_record_data.erl"),
    case write_if_changed(FileName, Content) of
        unchanged ->
            io:format("mongodb_record_data.erl is up to date~n"),
            {ok, State};
        ok ->
            io:format("Generated ~ts (~p records)~n", [FileName, map_size(Records)]),
            {ok, State};
        {error, Reason} ->
            {error, io_lib:format("Failed to generate ~ts: ~p", [FileName, Reason])}
    end.

write_if_changed(FileName, Content) ->
    case file:read_file(FileName) of
        {ok, Content} -> unchanged;
        _ ->
            case filelib:ensure_dir(FileName) of
                ok -> file:write_file(FileName, Content);
                {error, Reason} -> {error, {failed_to_create_dir, Reason}}
            end
    end.

build_module(RecordList, HeaderPaths) ->
    [
        "-module(mongodb_record_data).\n",
        generate_include_directives(HeaderPaths),
        "-export([\n",
        "    get_fields/1,\n",
        "    get_field/2,\n",
        "    get_field_index/2,\n",
        "    get_record/1,\n",
        "    get_record_by_name/1,\n",
        "    get_field_index_by_name/2\n",
        "]).\n\n",
        build_get_fields(RecordList), "\n",
        build_get_field(RecordList), "\n",
        build_get_field_index(RecordList), "\n",
        build_get_record(RecordList), "\n",
        build_get_record_by_name(RecordList), "\n",
        build_get_field_index_by_name(RecordList)
    ].

generate_include_directives(HeaderPaths) ->
    [io_lib:format("-include(~p).~n", [File])
     || File <- mongodb_record_release_util:find_hrl_files(HeaderPaths)].

build_get_fields(RecordList) ->
    Clauses = [io_lib:format("get_fields(~p) ->~n    ~p", [Name, Fields])
               || {Name, Fields} <- RecordList],
    join_clauses(Clauses, "get_fields(_) ->\n    {error, not_found}").

build_get_field(RecordList) ->
    Clauses = [
        io_lib:format(
            "get_field(~p, Index) when Index >= 2, Index =< ~p ->~n"
            "    lists:nth(Index - 1, get_fields(~p))",
            [Name, length(Fields) + 1, Name])
        || {Name, Fields} <- RecordList
    ],
    join_clauses(Clauses ++ ["get_field(_, Index) when Index < 2 ->\n    {error, invalid_index}"],
                 "get_field(_, _) ->\n    {error, not_found}").

build_get_field_index(RecordList) ->
    Clauses = [io_lib:format("get_field_index(~p, ~p) ->~n    ~p", [Name, Field, Index])
               || {Name, Fields} <- RecordList,
                  {Field, Index} <- lists:zip(Fields, lists:seq(2, length(Fields) + 1))],
    join_clauses(Clauses, "get_field_index(_, _) ->\n    {error, not_found}").

build_get_record(RecordList) ->
    Clauses = [io_lib:format("get_record(~p) ->~n    #~p{}", [Name, Name])
               || {Name, _Fields} <- RecordList],
    join_clauses(Clauses, "get_record(_) ->\n    {error, not_found}").

build_get_record_by_name(RecordList) ->
    Clauses = [io_lib:format("get_record_by_name(~p) ->~n    {ok, ~p, #~p{}}",
                             [atom_to_binary(Name, utf8), Name, Name])
               || {Name, _Fields} <- RecordList],
    join_clauses(Clauses, "get_record_by_name(_) ->\n    {error, not_found}").

build_get_field_index_by_name(RecordList) ->
    Clauses = [io_lib:format("get_field_index_by_name(~p, ~p) ->~n    {ok, ~p}",
                             [Name, atom_to_binary(Field, utf8), Index])
               || {Name, Fields} <- RecordList,
                  {Field, Index} <- lists:zip(Fields, lists:seq(2, length(Fields) + 1))],
    join_clauses(Clauses, "get_field_index_by_name(_, _) ->\n    {error, not_found}").

join_clauses(Clauses, FinalClause) ->
    [lists:join(";\n", Clauses ++ [FinalClause]), ".\n"].
