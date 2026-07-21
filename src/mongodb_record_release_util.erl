-module(mongodb_record_release_util).

-export([
    init/1,
    init/2,
    parse_file/1,
    parse_files/1,
    find_hrl_files/1,
    get_fields/1,
    get_field/2,
    get_field_index/2,
    get_record/1
]).

-define(DEFAULT_HEADER_PATHS, ["include"]).

init(Paths) ->
    init(Paths, []).

init(Paths, Macros) ->
    DefaultPaths = ?DEFAULT_HEADER_PATHS,
    AllPaths = case Paths of
        undefined -> DefaultPaths;
        [] -> DefaultPaths;
        _ -> Paths
    end,
    put(include_paths, AllPaths),
    put(macros, Macros),
    HrlFiles = find_hrl_files(AllPaths),
    io:format("HrlFiles: ~p~n", [HrlFiles]),
    case parse_files(HrlFiles) of
        {ok, Records} ->
            put(records, Records),
            {ok, Records};
        Error ->
            Error
    end.

-spec parse_file(file:filename()) -> {ok, #{atom() => [atom()]}} | {error, term()}.
parse_file(File) ->
    case file:read_file(File) of
        {ok, _Content} ->
            % 读取文件内容并添加终止符
            % ContentStr = binary_to_list(Content) ++ "\n",
            % 使用 epp 解析文件，这是处理 Erlang 预处理指令的正确方式
            IncludePaths = case get(include_paths) of
                undefined -> [filename:dirname(File)];
                Paths -> lists:usort([filename:dirname(File) | Paths])
            end,
            Macros = case get(macros) of undefined -> []; Value -> Value end,
            case epp:parse_file(File, IncludePaths, Macros) of
                {ok, Forms} ->
                    extract_records_from_forms(Forms, File);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

-spec parse_files([file:filename()]) -> {ok, #{atom() => [atom()]}} | {error, term()}.
parse_files(Files) ->
    parse_files(Files, #{}).

parse_files([], Acc) ->
    {ok, Acc};
parse_files([File | Rest], Acc) ->
    case parse_file(File) of
        {ok, Records} ->
            DuplicateNames = lists:sort([Name || Name <- maps:keys(Records), maps:is_key(Name, Acc)]),
            case DuplicateNames of
                [] -> parse_files(Rest, maps:merge(Acc, Records));
                _ -> {error, {duplicate_records, DuplicateNames, File}}
            end;
        Error ->
            Error
    end.

extract_records_from_forms(Forms, File) ->
    TargetFile = filename:absname(File),
    extract_records_from_forms(Forms, TargetFile, TargetFile, #{}).

extract_records_from_forms([], _TargetFile, _CurrentFile, Acc) ->
    {ok, Acc};
extract_records_from_forms([{attribute, _, file, {SourceFile, _}} | Rest],
                           TargetFile, _CurrentFile, Acc) ->
    extract_records_from_forms(Rest, TargetFile, filename:absname(SourceFile), Acc);
extract_records_from_forms([{attribute, _, record, {RecordName, Fields}} | Rest],
                           TargetFile, TargetFile, Acc) ->
    case maps:is_key(RecordName, Acc) of
        true ->
            {error, {duplicate_record, RecordName, TargetFile}};
        false ->
            FieldNames = extract_field_names(Fields),
            extract_records_from_forms(Rest, TargetFile, TargetFile,
                                       maps:put(RecordName, FieldNames, Acc))
    end;
extract_records_from_forms([_Form | Rest], TargetFile, CurrentFile, Acc) ->
    extract_records_from_forms(Rest, TargetFile, CurrentFile, Acc).

extract_field_names(Fields) ->
    extract_field_names(Fields, []).

extract_field_names([], Acc) ->
    lists:reverse(Acc);
extract_field_names([Field | Rest], Acc) ->
    NewAcc = case Field of
        {record_field, _, {atom, _, FieldName}} ->
            [FieldName | Acc];
        {record_field, _, {atom, _, FieldName}, _Default} ->
            [FieldName | Acc];
        {typed_record_field, {record_field, _, {atom, _, FieldName}}, _Type} ->
            [FieldName | Acc];
        {typed_record_field, {record_field, _, {atom, _, FieldName}, _Default}, _Type} ->
            [FieldName | Acc];
        _ ->
            Acc
    end,
    extract_field_names(Rest, NewAcc).

-spec get_fields(atom()) -> [atom()] | {error, not_found}.
get_fields(RecordName) ->
    case get(records) of
        undefined ->
            {error, not_found};
        Records ->
            case maps:get(RecordName, Records, undefined) of
                undefined ->
                    {error, not_found};
                Fields ->
                    Fields
            end
    end.

-spec get_field(atom(), pos_integer()) -> atom() | {error, not_found | invalid_index}.
get_field(RecordName, Index) when Index >= 2 ->
    case get_fields(RecordName) of
        {error, not_found} ->
            {error, not_found};
        Fields when Index =< length(Fields) + 1 ->
            lists:nth(Index - 1, Fields);
        _ ->
            {error, invalid_index}
    end;
get_field(_RecordName, Index) when Index < 2 ->
    {error, invalid_index}.

-spec get_field_index(atom(), atom()) -> non_neg_integer() | {error, not_found}.
get_field_index(RecordName, FieldName) ->
    case get_fields(RecordName) of
        {error, not_found} ->
            {error, not_found};
        Fields ->
            case lists:member(FieldName, Fields) of
                true ->
                    find_index(FieldName, Fields, 2);
                false ->
                    {error, not_found}
            end
    end.

find_index(FieldName, [FieldName | _], Index) ->
    Index;
find_index(FieldName, [_ | Rest], Index) ->
    find_index(FieldName, Rest, Index + 1).

-spec get_record(atom()) -> map() | {error, not_found}.
get_record(RecordName) ->
    case get(records) of
        undefined ->
            {error, not_found};
        Records ->
            case maps:get(RecordName, Records, undefined) of
                undefined ->
                    {error, not_found};
                Fields ->
                    #{name => RecordName, fields => Fields}
            end
    end.

find_hrl_files(Paths) ->
    lists:usort(lists:append([
        filelib:wildcard(filename:join(Path, "*.hrl")) ++
        filelib:wildcard(filename:join([Path, "**", "*.hrl"])) || Path <- Paths
    ])).
