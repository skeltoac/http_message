-module(http_message).
-author('andy@automattic.com').
-include("jlib.hrl").
-include("ejabberd_http.hrl").
-include("ejabberd.hrl").
-export([process/2]).

-compile(export_all).

process(_Path, Request)->
    process_method(Request).

process_method(#request{method = 'POST'} = Request) ->
    process_auth(Request);
process_method(_) ->
    {405, [{"Allow", "POST"}], "Method not allowed. Use POST."}.

process_auth(#request{auth = Auth} = Request) ->
    case check_auth(Auth) of
	{User, Domain} ->
	    process_data(Request#request{auth = User++"@"++Domain});
	_ ->
	    {401, [{"WWW-Authenticate", "basic realm=\"XMPP\""}], "Unauthorized. Use your Jabber ID (user@domain.com) and password.\n"}
    end.

process_data(#request{data = Data} = Request) ->
    %% TODO: Reduce parser spawn. xml_stream:parse_element always opens a new port. Use a single port or a pool of them.
    case xml_stream:parse_element(Data) of
	{error, _} = Error ->
	    ?ERROR_MSG("xml_stream:parse_element -> ~p~n", [{Error, Data}]),
	    {500, [], "Internal server error: XML parsing failed. The payload must be valid XML.\n"};
	Element ->
	    process_message(Request#request{data = Element})
    end.

process_message(#request{data = {xmlelement, "message", _, _}} = Request) ->
    From = xml:get_tag_attr_s("from", Request#request.data),
    To = xml:get_tag_attr_s("to", Request#request.data),
    process_sender(From, To, Request);
process_message(_) ->
    {400, [], "Bad request: the payload must be an XMPP message element.\n"}.

process_sender("", To, #request{auth = From} = Request) ->
    process_recipient(From, To, Request);
process_sender(From, To, #request{auth = From} = Request) ->
    process_recipient(From, To, Request);
process_sender(From, To, Request) ->
    case acl:match_rule(global, forge_sender, jlib:string_to_jid(Request#request.auth)) of
	allow ->
	    process_recipient(From, To, Request);
	_ ->
	    {403, [], "Forbidden: the authenticated user does not have permission to forge senders.\n"}
    end.

process_recipient(From, "multicast", Request) ->
    case acl:match_rule(global, multicast, jlib:string_to_jid(Request#request.auth)) of
	allow ->
	    process_multicast(From, Request#request.data);
	_ ->
	    {403, [], "Forbidden: the authenticated user does not have permission to multicast.\n"}
    end;
process_recipient(From, To, Request) ->
    send(From, To, Request#request.data).

process_multicast(From, Message) ->
    {Recipients, CleanMessage} = extract_addresses(Message),
    multicast(Recipients, From, CleanMessage).

multicast(Tos, From, Message) ->
    multicast(Tos, From, Message, {400, [], "Bad request: multicast requires addresses; see XEP-0033. This module treats all addresses as BCC.\n"}).

multicast([], _From, _Message, Response) ->
    Response;
multicast([To | Tos], From, Message, _Response) ->
    Response = send(From, To, Message),
    multicast(Tos, From, Message, Response).

extract_addresses({xmlelement, "message", Atts, Els}) ->
    ?ERROR_MSG("~p~n", [Els]),
    lists:foldr(
      fun({xmlelement, "addresses", _, AddEls}, {_, Message}) ->
	      {lists:foldl(
		 fun(Address, Acc) ->
			 case xml:get_tag_attr_s("jid", Address) of
			     "" -> Acc;
			     JID -> [JID | Acc]
			 end
		 end, [], AddEls),
	       Message};
	 (El, {Adds, {_, _, _, Acc}}) ->
	      {Adds, {xmlelement, "message", Atts, [El | Acc]}}
      end, {[], {xmlelement, "message", [], []}}, Els).

send(From, To, Message) ->
    case ejabberd_router:route(jlib:string_to_jid(From), jlib:string_to_jid(To), Message) of
	ok ->
	    {200, [], "OK\n"};
	Other ->
	    {500, [], io_lib:format("Internal server error: unexpected router response:~n~p~n", [Other])}
    end.

check_auth(Auth) ->
    case Auth of
        {SJID, P} ->
            case jlib:string_to_jid(SJID) of
                error ->
                    unauthorized;
                #jid{user = U, server = S} ->
                    case ejabberd_auth:check_password(U, S, P) of
                        true ->
                            {U, S};
                        false ->
                            unauthorized
                    end
            end;
	_ ->
            unauthorized
    end.
