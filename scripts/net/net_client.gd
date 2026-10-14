class_name NetClient
extends RefCounted
## Conexão WebSocket com o servidor: manda e recebe mensagens do Protocol.
## Quem usa chama poll() a cada quadro e trata as mensagens devolvidas.

var ws := WebSocketPeer.new()
## Abriu nesta chamada de poll() (hora de mandar o hello).
var just_opened := false
var _was_open := false


func connect_to(url: String) -> Error:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = Protocol.BUFFER_SIZE
	ws.outbound_buffer_size = Protocol.BUFFER_SIZE
	_was_open = false
	return ws.connect_to_url(url)


func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_closed() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_CLOSED


func poll() -> Array[Dictionary]:
	ws.poll()
	var out: Array[Dictionary] = []
	just_opened = is_open() and not _was_open
	_was_open = is_open()
	while is_open() and ws.get_available_packet_count() > 0:
		var msg := Protocol.decode(ws.get_packet().get_string_from_utf8())
		if not msg.is_empty():
			out.append(msg)
	return out


func send(msg: Dictionary) -> void:
	if is_open():
		ws.send_text(Protocol.encode(msg))


func close() -> void:
	ws.close()
