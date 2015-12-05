%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 29. Nov 2015 8:09 PM
%%%-------------------------------------------------------------------
-module(register_fsm_test).
-author("shuieryin").

%% API
-export([
]).

-export([
    test/1
]).

-include_lib("wechat_mud_test.hrl").
-include_lib("wechat_mud/src/data_type/player_profile.hrl").

%%%===================================================================
%%% API
%%%===================================================================

test(_Config) ->
    ?assert(proper:quickcheck(?FORALL(_L, integer(), test()), 50)).

test() ->
    TestUid = cm:uuid(),
    [TestIdBin | _] = re:split(atom_to_list(TestUid), "-"),
    TestId = binary_to_atom(TestIdBin, utf8),
    FsmId = register_fsm:fsm_server_name(TestUid),

    login_server:register_uid(self(), TestUid),

    ValidLangs = cm:type_values(nls_server, support_lang),
    ValidGenders = cm:type_values(player_fsm, gender),
    ValidBornMonths = apply(lists, seq, cm:type_values(player_fsm, born_month)),
    InvalidLangs = [kr, jp, 124134, <<"fasdf">>],
    InvalidInputs = [<<"@342342KKK">>, <<"$%^^$%^@!%$@">>],
    PlayerProfile = #player_profile{uid = TestUid},

    Ref = monitor(process, FsmId),

    ?assertNot(login_server:is_uid_registered(TestUid)),
    ?assert(login_server:is_in_registration(TestUid)),
    ?assertNot(login_server:is_id_registered(TestId)),
    ?assertNot(login_server:is_uid_logged_in(TestUid)),

    % =================select lang - Start=================
    ValidLang = ?ONE_OF(ValidLangs),
    SelectLang = input(
        ?ONE_OF(InvalidLangs),
        atom_to_binary(ValidLang, utf8),
        ValidLang,
        lang,
        PlayerProfile
    ),
    % =================select lang - End===================

    NormalFlow1 = normal_flow(ValidGenders, ValidBornMonths, InvalidInputs, SelectLang, TestId),
    % =================input confirmation - Start=================
    ResetPlayerProfile = input(
        ?ONE_OF(InvalidInputs),
        <<"n">>,
        n,
        {clear, PlayerProfile#player_profile{lang = ValidLang}},
        NormalFlow1
    ),
    % =================input confirmation - End===================

    NormalFlow2 = normal_flow(ValidGenders, ValidBornMonths, InvalidInputs, ResetPlayerProfile, TestId),
    % =================input confirmation - Start=================
    input(
        ?ONE_OF(InvalidInputs),
        <<"y">>,
        y,
        nil,
        NormalFlow2,
        false
    ),
    % =================input confirmation - End===================

    receive
        {'DOWN', Ref, process, _, _} ->
            ?assert(login_server:is_uid_registered(TestUid)),
            ?assertNot(login_server:is_in_registration(TestUid)),
            ?assert(login_server:is_id_registered(TestId)),
            ?assert(login_server:is_uid_logged_in(TestUid))
    end,
    true.

%%%===================================================================
%%% Internal functions
%%%===================================================================
normal_flow(ValidGenders, ValidBornMonths, InvalidInputs, PlayerProfile, TestId) ->
    % =================input id - Start=================
    InputId = input(
        ?ONE_OF(InvalidInputs),
        atom_to_binary(TestId, utf8),
        TestId,
        id,
        PlayerProfile
    ),
    % =================input id - End===================

    % =================input gender - Start=================
    ValidGender = ?ONE_OF(ValidGenders),
    InputGender = input(
        ?ONE_OF(InvalidInputs),
        atom_to_binary(ValidGender, utf8),
        ValidGender,
        gender,
        InputId
    ),
    % =================input gender - End===================

    % =================input born month - Start=================
    ValidBornMonth = ?ONE_OF(ValidBornMonths),
    InputBornMonth = input(
        ?ONE_OF([23, 2345, 112 | InvalidInputs]),
        integer_to_binary(ValidBornMonth),
        ValidBornMonth,
        born_month,
        InputGender
    ),
% =================input born month - End===================
    InputBornMonth.

validatePlayerProfile(#player_profile{uid = Uid} = CurrentPlayerProfile) ->
    ServerPlayerProfile = register_fsm:current_player_profile(Uid),
    Result = CurrentPlayerProfile == ServerPlayerProfile,
    case Result of
        false ->
            io:format("CurrentPlayerProfile:~p~nServerPlayerProfile:~p~n", [CurrentPlayerProfile, ServerPlayerProfile]);
        true ->
            do_nothing
    end,
    ?assert(Result).

input(InvalidInput, ValidInput, Value, FieldName, PlayerProfile) ->
    input(InvalidInput, ValidInput, Value, FieldName, PlayerProfile, true).
input(InvalidInput, ValidInput, Value, FieldName, #player_profile{uid = Uid} = PlayerProfile, IsValidate) ->
%%    io:format("ValidInput:~p~nValue:~p~n", [ValidInput, Value]),
    Self = self(),
    register_fsm:input(Self, Uid, InvalidInput),
    register_fsm:input(Self, Uid, ValidInput),

    UpdatedPlayerProfile =
        case FieldName of
            nil ->
                PlayerProfile;
            {clear, ResetPlayerProfile} ->
                ResetPlayerProfile;
            _ ->
                RecordInfo = [player_profile | record_info(fields, player_profile)],
                Pos = cm:index_of(FieldName, RecordInfo),
                UpdatedList = replace_pos(Value, Pos, tuple_to_list(PlayerProfile)),
                list_to_tuple(UpdatedList)
        end,

    case IsValidate of
        true ->
            validatePlayerProfile(UpdatedPlayerProfile);
        false ->
            do_nothing
    end,
    UpdatedPlayerProfile.

replace_pos(Value, Pos, List) ->
    replace_pos(Value, Pos, List, [], 1).
replace_pos(_, _, [], AccList, _) ->
    lists:reverse(AccList);
replace_pos(Value, Pos, [_ | Rest], AccList, Pos) ->
    replace_pos(Value, Pos, Rest, [Value | AccList], Pos + 1);
replace_pos(Value, Pos, [Elem | Tail], AccList, Counter) ->
    replace_pos(Value, Pos, Tail, [Elem | AccList], Counter + 1).