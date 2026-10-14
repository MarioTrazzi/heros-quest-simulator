class_name HqServer
extends Node
## Servidor online: lobby de salas, assentos e partidas sincronizadas.
##
## Autoritativo: valida cada comando (é a vez de um herói seu? a ação vale?),
## aplica no Match da sala (que também roda Zargon), grava e repassa o comando
## a todos da sala; cada cliente reaplica no seu Match e confere o hash.
## Protocolo em Protocol (scripts/net/protocol.gd).

const MAX_ROOMS_PER_PLAYER := 10
const MAX_WRONG_PASSWORDS := 5
const LOCKOUT_SECONDS := 30.0

var store: RoomStore
var port := 0
## peer → {"ws", "token", "name", "room", "wrong", "locked_until"}
var _peers: Dictionary = {}
## id → Room (só as salas com alguém dentro).
var rooms: Dictionary = {}
var _tcp := TCPServer.new()
var _next_peer := 1


func start(p_port: int, data_dir: String) -> Error:
	store = RoomStore.new(data_dir)
	var err := _tcp.listen(p_port)
	if err == OK:
		port = _tcp.get_local_port()
		print("HeroQuest: servidor na porta %d, dados em %s (%d salas)" % [port, data_dir, store.index.size()])
	return err


func stop() -> void:
	for peer: int in _peers.keys():
		_peers[peer].ws.close()
		_drop(peer)
	_tcp.stop()


func _process(_delta: float) -> void:
	while _tcp.is_listening() and _tcp.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = Protocol.BUFFER_SIZE
		ws.outbound_buffer_size = Protocol.BUFFER_SIZE
		if ws.accept_stream(_tcp.take_connection()) == OK:
			_peers[_next_peer] = {"ws": ws, "token": "", "name": "", "room": "", "wrong": 0, "locked_until": 0.0}
			_next_peer += 1
	for peer: int in _peers.keys():
		var ws: WebSocketPeer = _peers[peer].ws
		ws.poll()
		match ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while _peers.has(peer) and ws.get_available_packet_count() > 0:
					var msg := Protocol.decode(ws.get_packet().get_string_from_utf8())
					if not msg.is_empty():
						_handle(peer, msg)
			WebSocketPeer.STATE_CLOSED:
				_drop(peer)


func _send(peer: int, msg: Dictionary) -> void:
	if _peers.has(peer):
		_peers[peer].ws.send_text(Protocol.encode(msg))


func _error(peer: int, reason: String) -> void:
	_send(peer, {"t": "error", "reason": reason})


## Conexão caiu: sai da sala (se estava numa).
func _drop(peer: int) -> void:
	if not _peers.has(peer):
		return
	_leave_room(peer)
	_peers.erase(peer)


# ---------- mensagens ----------

func _handle(peer: int, msg: Dictionary) -> void:
	var p: Dictionary = _peers[peer]
	if msg.t == "hello":
		_hello(peer, msg)
		return
	if p.token == "":
		_error(peer, "Diga olá primeiro.")
		return
	match msg.t:
		"list_rooms":
			_list_rooms(peer, str(msg.get("search", "")))
		"create_room":
			_create_room(peer, msg)
		"enter_room":
			_enter_room(peer, str(msg.get("id", "")), str(msg.get("password", "")))
		"leave_room":
			_leave_room(peer)
			_send(peer, {"t": "left"})
		"sync":
			var room := _room_of(peer)
			if room != null:
				_send(peer, {"t": "room", "room": room.view_for(p.token)})
		_:
			var room := _room_of(peer)
			if room == null:
				_error(peer, "Entre numa sala primeiro.")
				return
			_room_message(peer, room, msg)


func _hello(peer: int, msg: Dictionary) -> void:
	if int(msg.get("version", 0)) != Protocol.VERSION:
		_error(peer, "Versão diferente do servidor (%d). Atualize o jogo." % Protocol.VERSION)
		_peers[peer].ws.close()
		return
	var token := str(msg.get("token", ""))
	var player_name := Protocol.clean_name(msg.get("name"), Protocol.MAX_NAME)
	if token.length() < 16 or token.length() > 64 or player_name == "":
		_error(peer, "Escolha um nome.")
		return
	_peers[peer].token = token
	_peers[peer].name = player_name
	_send(peer, {"t": "welcome", "version": Protocol.VERSION})


func _list_rooms(peer: int, search: String) -> void:
	var token: String = _peers[peer].token
	var out: Array = []
	for line: Dictionary in store.list(search):
		var room: Room = rooms.get(line.id)
		out.append({
			"id": line.id, "name": line.name, "owner": line.owner, "locked": line.locked,
			"seats": int(line.seats), "online": room.peers.size() if room != null else 0,
			"quest": line.quest, "completed": int(line.completed), "last_played": int(line.last_played),
			"mine": line.owner_token == token or line.seat_tokens.has(token),
		})
	# As salas do jogador primeiro.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.mine and not b.mine)
	_send(peer, {"t": "rooms", "rooms": out})


func _create_room(peer: int, msg: Dictionary) -> void:
	var p: Dictionary = _peers[peer]
	var room_name := Protocol.clean_name(msg.get("name"), Protocol.MAX_ROOM_NAME)
	var password := str(msg.get("password", ""))
	if room_name == "":
		_error(peer, "Dê um nome à sala.")
	elif password.length() > Protocol.MAX_PASSWORD:
		_error(peer, "Senha longa demais.")
	elif store.count_owned(p.token) >= MAX_ROOMS_PER_PLAYER:
		_error(peer, "Você já criou %d salas." % MAX_ROOMS_PER_PLAYER)
	else:
		var rec := store.create(room_name, password, p.token, p.name)
		_join(peer, _wake(rec.id))


func _enter_room(peer: int, id: String, password: String) -> void:
	var p: Dictionary = _peers[peer]
	var now := Time.get_ticks_msec() / 1000.0
	if now < p.locked_until:
		_error(peer, "Senha errada demais. Espere um pouco.")
		return
	var room := _wake(id)
	if room == null:
		_error(peer, "Sala não encontrada.")
		return
	# Quem já tem assento (ou criou a sala) não precisa digitar a senha de novo.
	var known := room.is_owner(p.token) or room.is_seated(p.token)
	if not known and not RoomStore.check_password(room.record, password):
		p.wrong += 1
		if p.wrong >= MAX_WRONG_PASSWORDS:
			p.wrong = 0
			p.locked_until = now + LOCKOUT_SECONDS
		_sleep_if_empty(room)
		_error(peer, "Senha errada.")
		return
	p.wrong = 0
	_join(peer, room)


func _join(peer: int, room: Room) -> void:
	_leave_room(peer)
	var p: Dictionary = _peers[peer]
	p.room = room.id()
	room.peers[peer] = {"token": p.token, "name": p.name}
	_broadcast_room(room)


func _leave_room(peer: int) -> void:
	var room := _room_of(peer)
	if room == null:
		return
	room.peers.erase(peer)
	_peers[peer].room = ""
	_broadcast_room(room)
	_sleep_if_empty(room)


func _room_message(peer: int, room: Room, msg: Dictionary) -> void:
	var token: String = _peers[peer].token
	var hero_id := str(msg.get("hero", ""))
	match msg.t:
		"sit":
			if not room.record.seats.has(hero_id) or room.record.seats[hero_id] != null:
				_error(peer, "Assento ocupado.")
				return
			room.record.seats[hero_id] = {"name": _peers[peer].name, "token": token}
			_save_and_broadcast(room)
		"free_seat":
			var seat: Variant = room.record.seats.get(hero_id)
			if seat == null or not (room.is_owner(token) or seat.token == token):
				_error(peer, "Só o dono do assento ou quem criou a sala pode liberá-lo.")
				return
			room.record.seats[hero_id] = null
			_save_and_broadcast(room)
		"buy":
			_buy(peer, room, hero_id, str(msg.get("item", "")))
		"start_quest":
			_start_quest(peer, room, str(msg.get("quest", "")))
		"abandon_quest":
			if not room.is_seated(token):
				_error(peer, "Sente-se num assento primeiro.")
				return
			room.quest_match = null
			room.campaign.in_progress = {}
			_save_and_broadcast(room)
		"command":
			_command(peer, room, msg.get("cmd"))
		_:
			_error(peer, "Mensagem desconhecida: %s" % msg.t)


func _buy(peer: int, room: Room, hero_id: String, item_id: String) -> void:
	var token: String = _peers[peer].token
	if not room.heroes_of(token).has(hero_id):
		_error(peer, "Só o dono do herói compra para ele.")
	elif room.quest_match != null:
		_error(peer, "Termine ou abandone a quest em andamento antes de comprar.")
	else:
		var reason := Armory.buy(room.campaign.hero(hero_id), item_id)
		if reason != "":
			_error(peer, reason)
		else:
			_save_and_broadcast(room)


## Começa a quest (ou, se é a que está em andamento, só chama todos para ela).
func _start_quest(peer: int, room: Room, quest_id: String) -> void:
	if not room.is_seated(_peers[peer].token):
		_error(peer, "Sente-se num assento primeiro.")
		return
	if room.quest_match == null or room.quest_match.quest_id != quest_id:
		if not room.campaign.is_unlocked(quest_id):
			_error(peer, "Quest bloqueada.")
			return
		# Só os heróis com dono entram; a iniciativa (1d6 cada) decide a ordem.
		var seated := room.campaign.heroes.filter(func(rec: Dictionary) -> bool: return room.record.seats.get(rec.id) != null)
		var seed_value := randi()
		var order := Match.roll_initiative(seated.map(func(rec: Dictionary) -> String: return rec.id), seed_value)
		room.quest_match = Match.create(quest_id, seed_value, order.map(func(o: Dictionary) -> Dictionary: return room.campaign.hero(o.hero)))
		room.quest_match.initiative = order
		room.quest_match.begin()
		_save(room)
	for other: int in room.peers:
		_send(other, {"t": "room", "room": room.view_for(room.peers[other].token)})
		_send(other, {"t": "quest_started", "quest": quest_id})


func _command(peer: int, room: Room, cmd: Variant) -> void:
	if not cmd is Dictionary:
		_error(peer, "Comando inválido.")
		return
	cmd = Match._ints(cmd)
	if not room.can_command(_peers[peer].token, cmd):
		_error(peer, "Não é a vez de um herói seu.")
		return
	if room.quest_match.apply(cmd).is_empty():
		_error(peer, "Essa ação não vale agora.")
		return
	var seq := room.quest_match.commands.size()
	var digest := room.quest_match.state_hash()
	for other: int in room.peers:
		_send(other, {"t": "applied", "seq": seq, "cmd": cmd, "hash": digest})
	if room.quest_match.state.outcome() != "":
		room.campaign.record(room.quest_match.state, room.quest_match.quest_id)
		room.quest_match = null
		_save_and_broadcast(room)
	else:
		_save(room)


# ---------- salas ----------

func _room_of(peer: int) -> Room:
	return rooms.get(_peers[peer].room) if _peers.has(peer) else null


## Carrega a sala do disco (se ainda não está na memória). null se não existe.
func _wake(id: String) -> Room:
	if rooms.has(id):
		return rooms[id]
	var rec := store.load_room(id)
	if rec.is_empty():
		return null
	var room := Room.new(rec)
	rooms[id] = room
	return room


func _sleep_if_empty(room: Room) -> void:
	if room.peers.is_empty():
		rooms.erase(room.id())


func _save(room: Room) -> void:
	room.sync_record()
	store.save_room(room.record)


func _save_and_broadcast(room: Room) -> void:
	_save(room)
	_broadcast_room(room)


func _broadcast_room(room: Room) -> void:
	room.sync_record()
	for peer: int in room.peers:
		_send(peer, {"t": "room", "room": room.view_for(room.peers[peer].token)})
