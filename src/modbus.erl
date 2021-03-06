%% @author Caleb Tennis <caleb.tennis@gmail.com>
%% @copyright 2010 Data Cave, Inc.  www.thedatacave.com
%% @version 0.9
%% @doc A way to interact with modbus-tcp devices on an ethernet network

-module(modbus).

-include("modbus.hrl").

-include_lib("eunit/include/eunit.hrl").

-export([send_request_message/1,generate_request_message/1,get_response_header/1,get_response_data/1]).

%% @doc Function to generate and send the request message throw the tcp socket.
%% @end
-spec send_request_message(State::#tcp_request{}) -> term().
send_request_message(State) ->
	Message =  generate_request_message(State),
	gen_tcp:send(State#tcp_request.sock, Message).


%% @doc Function to generate  the request message from State.
%% @end
-spec generate_request_message(State::#tcp_request{}) -> binary().
generate_request_message(#tcp_request{tid = Tid, address = Address, function = ?FC_WRITE_HREGS, start = Start, data = Data}) ->
	Quantity = length(Data),
	ValuesBin = list_word16_to_binary(Data),
	ByteCount = length(binary_to_list(ValuesBin)),
	Message = <<Address:8, ?FC_WRITE_HREGS:8, Start:16, Quantity:16, ByteCount:8, ValuesBin/binary>>,

	Size = size(Message),
	<<Tid:16, 0, 0, Size:16, Message/binary>>;

generate_request_message(#tcp_request{tid = Tid, address = Address, function = Code, start = Start, data = Offset}) ->
	Message = <<Address:8, Code:8, Start:16, Offset:16>>,
	Size = size(Message),
	<<Tid:16, 0, 0, Size:16, Message/binary>>.


%% @doc Function to get and validate the response header from the tcp socket.
%% @end
-spec get_response_header(State::#tcp_request{}) -> ok | {error, term()}.
get_response_header(State) ->
	TID = State#tcp_request.tid,
	{ok, [Tid1, Tid2, 0, 0, _, _TcpSize, Address, Code]} = gen_tcp:recv(State#tcp_request.sock, 8),
	% validate the tid
	<<TID:16/integer>> = <<Tid1, Tid2>>,

	% validate the header
	OrigAddress = State#tcp_request.address,	
	OrigCode = State#tcp_request.function,
	BadCode = OrigCode + 128,

 	case {Address,Code} of
		{OrigAddress,OrigCode} -> ok;
		{OrigAddress,BadCode} -> 
			{ok, [ErrorCode]} = gen_tcp:recv(State#tcp_request.sock, 1),

			case ErrorCode of
				1 -> {error, illegal_function};
				2 -> {error, illegal_data_address};
				3 -> {error, illegal_data_value};
				4 -> {error, slave_device_failure};
				5 -> {error, acknowledge};
				6 -> {error, slave_device_busy};
				_ -> {error, unknown_response_code}
			end;
			
		{_,_}=Junk -> io:format("Junk: ~w~n", [Junk]), {error,junkResponse}
  	end.

%% @doc Function to get the response data from the tcp socket.
%% @end
-spec get_response_data(State::#tcp_request{}) -> {ok, term()}.
get_response_data(State) ->

	case State#tcp_request.function of
		?FC_WRITE_HREGS -> 
			Size = 4;
		_ ->
			{ok, [Size]} = gen_tcp:recv(State#tcp_request.sock, 1)
	end,

	gen_tcp:recv(State#tcp_request.sock, Size).


%%% %%% -------------------------------------------------------------------
%% Util
%%% %%% -------------------------------------------------------------------

%% @private
%% @doc Function to convert a list of words to binary.
%% @end
-spec list_word16_to_binary(Values::list()) -> binary().
list_word16_to_binary(Values) when is_list(Values) ->
	concat_binary([<<X:16>> || X <- Values]).

%% @hidden
concat_binary([]) ->
    <<>>;
concat_binary([Part]) ->
    Part;
concat_binary(List) ->
    lists:foldr(fun (A, B) ->
			if
			    bit_size(B) > 0 -> <<A/binary, B/binary>>;
			    true            -> A
			end
		end, <<>>, List).

