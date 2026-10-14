extends Node
## Jogo online do lado do cliente: conexão, identidade, lobby e a sala atual.
##
## Identidade sem conta: um token aleatório em user://identity.json (com o nome
## do jogador). O token reconhece o dono do assento; a senha da sala barra estranhos.
##
## A sala chega inteira em "room" (campanha + quest em andamento com o log);
## cada "applied" acrescenta um comando ao log de Session.campaign.in_progress e
## avisa (command_applied) a partida aberta, que reaplica e anima.

signal status_changed(text: String)
signal welcomed
signal rooms_received(rooms: Array)
signal room_changed
signal quest_started(quest_id: String)
signal command_applied(seq: int, cmd: Dictionary, digest: String)
signal error_received(reason: String)
signal left_room

const IDENTITY_PATH := "user://identity.json"
## Sem resposta do servidor nesse tempo, desiste e avisa.
const CONNECT_TIMEOUT_MS := 10000

var client := NetClient.new()
var token := ""
var player_name := ""
var server_url := "ws://localhost:%d" % Protocol.DEFAULT_PORT
## Conectado e reconhecido pelo servidor.
var ready_to_play := false
## Visão da sala atual (ver Room.view_for); {} = fora de sala.
var room: Dictionary = {}
var last_error := ""
var identity_path := IDENTITY_PATH
## Pediu para entrar/criar sala: o próximo "room" vale. Depois de sair, "room" atrasado é ignorado.
var _awaiting_room := false
## Quando começou a conectar (0 = não está esperando o servidor).
var _connecting_since := 0


func _ready() -> void:
	# Perfil (`-- --perfil=2` ou HQ_PROFILE=2): outra identidade no mesmo aparelho,
	# para testar dois jogadores em duas janelas.
	var profile := OS.get_environment("HQ_PROFILE")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perfil="):
			profile = arg.trim_prefix("--perfil=")
	profile = profile.validate_filename()
	if profile != "":
		identity_path = "user://identity_%s.json" % profile
	load_identity()


func load_identity() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(identity_path)) \
		if FileAccess.file_exists(identity_path) else null
	if data is Dictionary:
		token = str(data.get("token", ""))
		player_name = str(data.get("name", ""))
		server_url = str(data.get("server", server_url))
	if token.length() < 16:
		token = Crypto.new().generate_random_bytes(16).hex_encode()
		save_identity()


func save_identity() -> void:
	var file := FileAccess.open(identity_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"token": token, "name": player_name, "server": server_url}))


func connect_server(url: String, name: String) -> Error:
	server_url = url.strip_edges()
	player_name = Protocol.clean_name(name, Protocol.MAX_NAME)
	save_identity()
	ready_to_play = false
	room = {}
	var err := client.connect_to(server_url)
	_connecting_since = Time.get_ticks_msec() if err == OK else 0
	status_changed.emit("Conectando..." if err == OK else "Endereço inválido.")
	return err


func disconnect_server() -> void:
	_connecting_since = 0
	client.close()
	ready_to_play = false
	room = {}


func is_online() -> bool:
	return ready_to_play and client.is_open()


func _process(_delta: float) -> void:
	if _connecting_since > 0 and not ready_to_play and Time.get_ticks_msec() - _connecting_since > CONNECT_TIMEOUT_MS:
		_connecting_since = 0
		client.close()
		status_changed.emit("Não conectou. Confira o endereço (o servidor está no ar?).")
		return
	if client.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and not ready_to_play:
		return
	var messages := client.poll()
	if client.just_opened:
		client.send({"t": "hello", "token": token, "name": player_name, "version": Protocol.VERSION})
	for msg in messages:
		_handle(msg)
	if ready_to_play and client.is_closed():
		ready_to_play = false
		status_changed.emit("Conexão perdida.")


func _handle(msg: Dictionary) -> void:
	match msg.t:
		"welcome":
			_connecting_since = 0
			ready_to_play = true
			status_changed.emit("Conectado.")
			welcomed.emit()
		"error":
			_awaiting_room = false
			last_error = str(msg.get("reason", ""))
			error_received.emit(last_error)
		"rooms":
			rooms_received.emit(msg.get("rooms", []))
		"room":
			if room.is_empty() and not _awaiting_room:
				return
			_awaiting_room = false
			room = msg.room
			Session.online = true
			Session.campaign = Campaign.from_dict(room.campaign)
			room_changed.emit()
		"quest_started":
			quest_started.emit(str(msg.quest))
		"applied":
			_applied(int(msg.seq), Match._ints(msg.cmd), str(msg.hash))
		"left":
			if _awaiting_room:
				return
			room = {}
			left_room.emit()


## Mantém o log local em dia (para quem entrar na partida depois) e avisa a partida aberta.
func _applied(seq: int, cmd: Dictionary, digest: String) -> void:
	var running: Dictionary = Session.campaign.in_progress if Session.campaign != null else {}
	if running.is_empty():
		request_sync()
		return
	var commands: Array = running.commands
	if seq == commands.size() + 1:
		commands.append(cmd)
	elif seq > commands.size() + 1:
		request_sync()
		return
	command_applied.emit(seq, cmd, digest)


# ---------- pedidos ----------

func send(msg: Dictionary) -> void:
	client.send(msg)


func list_rooms(search := "") -> void:
	send({"t": "list_rooms", "search": search})


func create_room(room_name: String, password: String) -> void:
	_awaiting_room = true
	send({"t": "create_room", "name": room_name, "password": password})


func enter_room(id: String, password := "") -> void:
	_awaiting_room = true
	send({"t": "enter_room", "id": id, "password": password})


func leave_room() -> void:
	send({"t": "leave_room"})
	room = {}
	_awaiting_room = false


func sit(hero_id: String) -> void:
	send({"t": "sit", "hero": hero_id})


func free_seat(hero_id: String) -> void:
	send({"t": "free_seat", "hero": hero_id})


func buy(hero_id: String, item_id: String) -> void:
	send({"t": "buy", "hero": hero_id, "item": item_id})


func start_quest(quest_id: String) -> void:
	send({"t": "start_quest", "quest": quest_id})


func abandon_quest() -> void:
	send({"t": "abandon_quest"})


func send_command(cmd: Dictionary) -> void:
	send({"t": "command", "cmd": cmd})


func request_sync() -> void:
	send({"t": "sync"})


# ---------- assentos ----------

func seat(hero_id: String) -> Variant:
	return room.get("seats", {}).get(hero_id)


func my_heroes() -> Array[String]:
	var out: Array[String] = []
	for hero_id: String in room.get("seats", {}):
		var s: Variant = room.seats[hero_id]
		if s != null and s.mine:
			out.append(hero_id)
	return out


## Mesma regra do servidor (Room.can_control): o dono presente joga o seu herói;
## herói de quem faltou, qualquer jogador sentado.
func can_control(hero_id: String) -> bool:
	if my_heroes().is_empty():
		return false
	var s: Variant = seat(hero_id)
	if s == null or not s.online:
		return true
	return s.mine


## Nome de quem joga o herói (para o HUD).
func controller_name(hero_id: String) -> String:
	var s: Variant = seat(hero_id)
	if s == null:
		return "assento vazio"
	return s.name if s.online else "%s (ausente)" % s.name
