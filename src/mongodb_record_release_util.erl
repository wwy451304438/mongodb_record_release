-module(mongodb_record_release_util).

-export([
    init/1,
    parse_file/1,
    parse_files/1,
    get_fields/1,
    get_field/2,
    get_field_index/2,
    get_record/1
]).

-define(DEFAULT_HEADER_PATHS, ["include"]).

init(Paths) ->
    DefaultPaths = ?DEFAULT_HEADER_PATHS,
    AllPaths = case Paths of
        undefined -> DefaultPaths;
        [] -> DefaultPaths;
        _ -> Paths
    end,
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
            case epp:parse_file(File, [], []) of
                {ok, Forms} ->
                    extract_records_from_forms(Forms);
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
            NewAcc = maps:merge(Acc, Records),
            parse_files(Rest, NewAcc);
        Error ->
            Error
    end.

extract_records_from_forms(Forms) ->
    extract_records_from_forms(Forms, #{}).

extract_records_from_forms([], Acc) ->
    {ok, Acc};
extract_records_from_forms([Form | Rest], Acc) ->
    NewAcc = case Form of
        {attribute, _, record, {RecordName, Fields}} ->
            FieldNames = extract_field_names(Fields),
            maps:put(RecordName, FieldNames, Acc);
        _ ->
            Acc
    end,
    extract_records_from_forms(Rest, NewAcc).

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

-spec get_field(atom(), non_neg_integer()) -> atom() | {error, not_found}.
get_field(RecordName, Index) when Index >= 0 ->
    case get_fields(RecordName) of
        {error, not_found} ->
            {error, not_found};
        Fields when Index < length(Fields) ->
            lists:nth(Index + 1, Fields);
        _ ->
            {error, invalid_index}
    end;
get_field(_RecordName, Index) when Index < 0 ->
    {error, invalid_index}.

-spec get_field_index(atom(), atom()) -> non_neg_integer() | {error, not_found}.
get_field_index(RecordName, FieldName) ->
    case get_fields(RecordName) of
        {error, not_found} ->
            {error, not_found};
        Fields ->
            case lists:member(FieldName, Fields) of
                true ->
                    find_index(FieldName, Fields, 0);
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
