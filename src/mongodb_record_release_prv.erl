-module(mongodb_record_release_prv).
-export([init/1, do/1, format_error/1]).

-behaviour(provider).

-define(PROVIDER, mongodb_record_release).
-define(DEPS, [compile]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {deps, ?DEPS},
        {description, "Parse Erlang record definitions from header files"},
        {hooks, []},
        {example, "rebar3 mongodb_record_release"},
        {opts, []}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    Config = rebar_state:get(State, mongodb_record_release_plugin, []),
    HeaderPaths = proplists:get_value(header_paths, Config, ["include"]),
    OutputPath = proplists:get_value(output_path, Config, "src"),
    
    case mongodb_record_release_util:init(HeaderPaths) of
        {ok, Records} ->
            io:format("Parsed ~p records~n", [map_size(Records)]),
            io:format("Available records: ~p~n", [maps:keys(Records)]),
            case generate_mongodb_record_data(Records, OutputPath, HeaderPaths) of
                ok ->
                    io:format("Generated mongodb_record_data.erl~n"),
                    {ok, State};
                {error, Reason} ->
                    {error, io_lib:format("Failed to generate file: ~p", [Reason])}
            end;
        {error, Reason} ->
            {error, io_lib:format("Failed to parse records: ~p", [Reason])}
    end.

-spec format_error(iodata()) -> string().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

generate_mongodb_record_data(Records, OutputPath, HeaderPaths) ->
    RecordList = maps:to_list(Records),
    Content = build_mongodb_record_data_module(RecordList, HeaderPaths),
    FileName = filename:join(OutputPath, "mongodb_record_data.erl"),
    %% 1. 首先确保文件所在的所有父目录都存在
    case filelib:ensure_dir(FileName) of
        ok ->
            %% 2. 目录存在或已创建，现在可以安全地写入文件
            file:write_file(FileName, Content);
        {error, Reason} ->
            %% 处理目录创建失败的情况
            {error, {failed_to_create_dir, Reason}}
    end.

build_mongodb_record_data_module(RecordList, HeaderPaths) ->
    FieldsFun = build_get_fields_fun(RecordList),
    FieldFun = build_get_field_fun(RecordList),
    FieldIndexFun = build_get_field_index_fun(RecordList),
    GetRecordFun = build_get_record_fun(RecordList),
    
    IncludeDirectives = generate_include_directives(HeaderPaths),
    
    Header = "-module(mongodb_record_data).\n"
             ++ IncludeDirectives
             ++ "-export([\n"
             "    get_fields/1,\n"
             "    get_field/2,\n"
             "    get_field_index/2,\n"
             "    get_record/1\n"
             "]).\n\n",
             
    Header ++ FieldsFun ++ "\n" ++ FieldFun ++ "\n" ++ FieldIndexFun ++ "\n" ++ GetRecordFun.

generate_include_directives(HeaderPaths) ->
    HrlFiles = find_hrl_files(HeaderPaths),
    lists:foldl(fun(File, Acc) ->
        Acc ++ "-include(\"" ++ File ++ "\").\n"
    end, "", HrlFiles).

find_hrl_files(Paths) ->
    find_hrl_files(Paths, []).

find_hrl_files([], Acc) ->
    Acc;
find_hrl_files([Path | Rest], Acc) ->
    case file:list_dir(Path) of
        {ok, Files} ->
            HrlFiles = [filename:join(Path, File) || 
                        File <- Files, 
                        filename:extension(File) =:= ".hrl"],
            find_hrl_files(Rest, Acc ++ HrlFiles);
        {error, _} ->
            find_hrl_files(Rest, Acc)
    end.

build_get_fields_fun(RecordList) ->
    case RecordList of
        [] ->
            "get_fields(_) ->\n    {error, not_found}.\n";
        _ ->
            Clauses = [build_get_fields_clause(RecordName, Fields) || {RecordName, Fields} <- RecordList],
            AllClauses = Clauses ++ ["get_fields(_) ->\n    {error, not_found}"],
            LastClause = lists:last(AllClauses),
            OtherClauses = lists:droplast(AllClauses),
            FormattedClauses = [Clause ++ ";" || Clause <- OtherClauses] ++ [LastClause ++ "."],
            string:join(FormattedClauses, "\n") ++ "\n"
    end.

build_get_fields_clause(RecordName, Fields) ->
    AtomName = atom_to_list(RecordName),
    FieldAtoms = [atom_to_list(F) || F <- Fields],
    "get_fields(" ++ AtomName ++ ") ->\n" ++
    "    [" ++ AtomName ++ ", " ++ string:join(FieldAtoms, ", ") ++ "]".

build_get_field_fun(RecordList) ->
    Clauses = lists:flatmap(fun({RecordName, Fields}) ->
        build_get_field_clauses(RecordName, Fields)
    end, RecordList),
    InvalidIndexClause = "get_field(_, Index) when Index < 1 ->\n    {error, invalid_index}",
    NotFoundClause = "get_field(_, _) ->\n    {error, not_found}",
    AllClauses = Clauses ++ [InvalidIndexClause, NotFoundClause],
    case AllClauses of
        [] ->
            "get_field(_, _) ->\n    {error, not_found}.\n";
        _ ->
            LastClause = lists:last(AllClauses),
            OtherClauses = lists:droplast(AllClauses),
            FormattedClauses = [Clause ++ ";" || Clause <- OtherClauses] ++ [LastClause ++ "."],
            string:join(FormattedClauses, "\n") ++ "\n"
    end.

build_get_field_clauses(RecordName, Fields) ->
    AtomName = atom_to_list(RecordName),
    FieldCount = length(Fields),
    ["get_field(" ++ AtomName ++ ", Index) when Index >= 1, Index =< " ++ integer_to_list(FieldCount) ++ " ->\n" ++
     "    lists:nth(Index + 1, get_fields(" ++ AtomName ++ "))"].

build_get_field_index_fun(RecordList) ->
    Clauses = lists:flatmap(fun({RecordName, Fields}) ->
        build_get_field_index_clauses(RecordName, Fields)
    end, RecordList),
    NotFoundClause = "get_field_index(_, _) ->\n    {error, not_found}",
    AllClauses = Clauses ++ [NotFoundClause],
    case AllClauses of
        [] ->
            "get_field_index(_, _) ->\n    {error, not_found}.\n";
        _ ->
            LastClause = lists:last(AllClauses),
            OtherClauses = lists:droplast(AllClauses),
            FormattedClauses = [Clause ++ ";" || Clause <- OtherClauses] ++ [LastClause ++ "."],
            string:join(FormattedClauses, "\n") ++ "\n"
    end.

build_get_field_index_clauses(RecordName, Fields) ->
    AtomName = atom_to_list(RecordName),
    ["get_field_index(" ++ AtomName ++ ", " ++ atom_to_list(Field) ++ ") ->\n" ++
     "    " ++ integer_to_list(Index + 2) || {Field, Index} <- lists:zip(Fields, lists:seq(0, length(Fields) - 1))].

build_get_record_fun(RecordList) ->
    Clauses = [build_get_record_clause(RecordName, Fields) || {RecordName, Fields} <- RecordList],
    NotFoundClause = "get_record(_) ->\n    {error, not_found}",
    AllClauses = Clauses ++ [NotFoundClause],
    case AllClauses of
        [] ->
            "get_record(_) ->\n    {error, not_found}.\n";
        _ ->
            LastClause = lists:last(AllClauses),
            OtherClauses = lists:droplast(AllClauses),
            FormattedClauses = [Clause ++ ";" || Clause <- OtherClauses] ++ [LastClause ++ "."],
            string:join(FormattedClauses, "\n") ++ "\n"
    end.

build_get_record_clause(RecordName, _Fields) ->
    AtomName = atom_to_list(RecordName),
    "get_record(" ++ AtomName ++ ") ->\n" ++
    "    #" ++ AtomName ++ "{}".
