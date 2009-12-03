%%
%% Partial Git Implementation
%%

-module(git).
-export([open/1, read_object/2, object_exists/2, rev_list/2]).

-include("git.hrl").

%%-define(cassandra_ZERO, 0).

%-record(git_dir, {path}).
%-record(commit, {commit_sha, tree_sha, parents, author, committer, encoding, message}).

% Cp = #commit{sha=Sha, tree=Tree},

open(Path) ->
  % normalize the path (look for .git, etc)
  {Path}.

%references(Git) ->
  % read all the refs from disk/packed-refs and return an array
  %{Git}.

%print_branches(Git) ->
  % print branches out to stdout
  %io:fwrite("Branches:~n").

%print_log(Git, Ref) ->
  % traverse the reference, printing out all the log information to stdout
  %io:fwrite("Log:~n").

rev_list(Git, Shas) ->
  rev_list(Git, Shas, []).

rev_list(Git, [Sha|Shas], Gathered) ->
  Commit = commit(Git, Sha),
  Parents = git_object:get_parents(Commit),
  rev_list(Git, Parents ++ Shas, [Sha|Gathered]);
rev_list(Git, [], Gathered) ->
  Gathered.

commit(Git, Sha) ->
  {Type, Size, Data} = read_object(Git, Sha),
  git_object:parse_commit(Data).

git_dir(Git) ->
  {Path} = Git,
  Path.

object_exists(Git, ObjectSha) ->
  LoosePath = get_loose_object_path(Git, ObjectSha),
  case filelib:is_file(LoosePath) of
    true ->
      true;
    false ->
      case find_packfile_with_object(Git, ObjectSha) of
        {ok, _PackFilePath, _Offset} ->
          true;
        _Else ->
          false
      end
  end.

% get the raw object data out of loose or packed formats
% see if the object is loose, read the data
% else check the packfile indexes and get the object out of a packfile
read_object(Git, ObjectSha) ->
  LoosePath = get_loose_object_path(Git, ObjectSha),
  case file:read_file(LoosePath) of
    {ok, Data} ->
      extract_loose_object_data(Data);
    _Else ->
      get_packfile_object_data(Git, ObjectSha)
  end.

get_loose_object_path(Git, ObjectSha) ->
  First = string:substr(ObjectSha, 1, 2),
  Second = string:substr(ObjectSha, 3, 38),
  git_dir(Git) ++ "/objects/" ++ First ++ "/" ++ Second.

%% TODO: make this more efficient - this is ridiculous
%%       should be able to do this as a binary
extract_loose_object_data(CompData) ->
  RawData = binary_to_list(zlib:uncompress(CompData)),
  Split = string:chr(RawData, 0),
  {Header, Data} = lists:split(Split, RawData),
  Split2 = string:chr(Header, 32),
  Header2 = lists:sublist(Header, length(Header) - 1),
  {Type, Size} = lists:split(Split2, Header2),
  Type2 = lists:sublist(Type, length(Type) - 1),
  {binary_to_atom(list_to_binary(Type2), latin1), list_to_integer(Size), list_to_binary(Data)}.

get_packfile_object_data(Git, ObjectSha) ->
  case find_packfile_with_object(Git, ObjectSha) of
    {ok, PackFilePath, Offset} ->
      packfile:get_packfile_data(Git, PackFilePath, Offset);
    _Else ->
      invalid
  end.

find_packfile_with_object(Git, ObjectSha) ->
  %io:fwrite("SHA:~p~n", [ObjectSha]),
  PackIndex = git_dir(Git) ++ "/objects/pack",
  case file:list_dir(PackIndex) of
    {ok, Filenames} ->
      Indexes = lists:filter(fun(X) -> string_ends_with(X, ".idx") end, Filenames),
      case get_packfile_with_object(Git, Indexes, ObjectSha) of
        {ok, Packfile, Offset} ->
          PackFilePath = git_dir(Git) ++ "/objects/pack/" ++ Packfile,
          {ok, PackFilePath, Offset};
        _Else ->
          invalid
      end;
    _Else ->
      invalid
  end.

get_packfile_with_object(Git, [Index|Rest], ObjectSha) ->
  PackIndex = git_dir(Git) ++ "/objects/pack/" ++ Index,
  %io:fwrite("Looking for ~p in ~p~n", [ObjectSha, PackIndex]),
  case file:read_file(PackIndex) of
    {ok, Data} ->
      case packindex:extract_packfile_index(Data) of
        {ok, IndexData} ->
          %io:fwrite("PackIndex Size:~p~n", [IndexData#index.size]),
          %io:fwrite("IndexData:~p~n", [IndexData]),
          case packindex:object_offset(IndexData, ObjectSha) of
            {ok, Offset} ->
              Packfile = replace_string_ending(Index, ".idx", ".pack"),
              {ok, Packfile, Offset};
            not_found ->
              get_packfile_with_object(Git, Rest, ObjectSha)
          end;
        Else ->
          io:fwrite("Invalid, Biatch~p~n", [Else]),
          invalid
      end;
    _Else ->
      invalid
  end;
get_packfile_with_object(_Git, [], _ObjectSha) ->
  not_found.

replace_string_ending(String, Ending, NewEnding) ->
  Base = string:substr(String, 1, length(String) - length(Ending)),
  Base ++ NewEnding.

string_ends_with(File, Ending) ->
  FileEnding = string:substr(File, length(File) - length(Ending) + 1, length(Ending)),
  FileEnding =:= Ending.

