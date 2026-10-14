extends Node
## Smoke do jogo online, tudo no mesmo processo:
##   godot --headless --path . res://tests/net_smoke.tscn
## Servidor (HqServer) + cliente A pelas telas de verdade (Net, lobby, campanha,
## partida) + cliente B cru (NetClient) com seu próprio Match.
## Lobby, senha, assentos, quest sincronizada (hash igual nos três), vez de
## outro jogador recusada, queda e volta de B, servidor reiniciado lendo do disco.
## Sai com código ≠ 0 se falhar.

const MAX_WAIT_MS := 15000
const DATA := "user://net_smoke_data"
const IDENTITY_A := "user://net_smoke_identity.json"

var _failures := 0
var _server: HqServer
var _url := ""
# Cliente B.
var _b := NetClient.new()
var _b_token := "b".repeat(32)
var _b_inbox: Array[Dictionary] = []
var _b_room: Dictionary = {}
var _b_match: Match
var _b_errors: Array[String] = []


func _ready() -> void:
	Session.preview = false  # os testes contam com a névoa e o bloqueio das quests
	Engine.time_scale = 4.0
	_wipe(ProjectSettings.globalize_path(DATA))
	if FileAccess.file_exists(IDENTITY_A):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IDENTITY_A))
	Net.identity_path = IDENTITY_A
	Net.load_identity()
	# As telas trocam dentro de um nó próprio (Session.go apaga os filhos do anfitrião).
	var screens := Node.new()
	add_child(screens)
	Session.host = screens
	_start_server()

	# --- A cria a sala pelo lobby ---
	Session.go(Session.LOBBY)
	await _frames(2)
	var lobby := Session.current_screen()
	lobby.connect_server(_url, "Ana")
	_check(await _until(func() -> bool: return Net.is_online()), "A conecta e é reconhecido")
	lobby.create_room("Mesa de sexta", "segredo")
	_check(await _until(func() -> bool: return Session.current_screen().has_method("sit")), "criar sala leva à tela da campanha")
	var hub := Session.current_screen()
	_check(Session.online and Net.room.name == "Mesa de sexta" and Net.room.is_owner, "A está na sala que criou")
	var room_id: String = Net.room.id
	hub.sit("barbarian")
	hub.sit("wizard")
	_check(await _until(func() -> bool: return Net.my_heroes().size() == 2), "A senta no Bárbaro e no Mago")

	# --- B acha a sala no lobby e entra com a senha ---
	_b.connect_to(_url)
	_check(await _until(func() -> bool: return _b.is_open()), "B conecta")
	_b.send({"t": "hello", "token": _b_token, "name": "Bia", "version": Protocol.VERSION})
	_check(await _b_wait("welcome") != {}, "B é reconhecido")
	_b.send({"t": "list_rooms", "search": "sexta"})
	var listing := await _b_wait("rooms")
	var rooms: Array = listing.get("rooms", [])
	_check(rooms.size() == 1 and rooms[0].locked and rooms[0].seats == 2 and not rooms[0].mine, "lobby lista a sala com cadeado e 2 assentos")
	_b.send({"t": "enter_room", "id": room_id, "password": "errada"})
	_check(await _b_wait("error") != {} and _b_room.is_empty(), "senha errada é recusada")
	_b.send({"t": "enter_room", "id": room_id, "password": "segredo"})
	_check(await _b_wait("room") != {}, "senha certa entra na sala")
	_b.send({"t": "sit", "hero": "barbarian"})
	_check(await _b_wait("error") != {}, "assento ocupado é recusado")
	_b.send({"t": "sit", "hero": "dwarf"})
	_check(await _until(func() -> bool: return Net.seat("dwarf") != null and Net.seat("dwarf").online), "A vê B sentado e online")
	_check(Net.room.online.size() == 2, "dois jogadores online na sala")

	# Armeria: só o dono compra para o herói.
	_b.send({"t": "buy", "hero": "barbarian", "item": "helmet"})
	_check(await _b_wait("error") != {}, "B não compra para o herói de A")

	# --- A começa a quest; todos vão para ela ---
	hub.play("sandbox")
	_check(await _until(func() -> bool: return Session.current_screen().has_method("choose_schools")), "A entra na quest")
	_check(await _b_wait("quest_started") != {}, "B é chamado para a quest")
	_b_match = Match.from_dict(_b_room.campaign.in_progress)
	_check(_b_match != null and _b_match.state.round_number == 0, "B monta a partida a partir da sala")
	var order: Array = _b_match.initiative.map(func(o: Dictionary) -> String: return o.hero)
	order.sort()
	_check(order == ["barbarian", "dwarf", "wizard"], "só os heróis escolhidos rolam a iniciativa (Elfo livre fica fora)")
	_check(_b_match.state.alive(Unit.Side.HERO).size() == 3, "Elfo sem dono fica fora da quest")
	var game := Session.current_screen()
	await _frames(2)
	await game.choose_schools("fire", "water")
	_check(await _until(func() -> bool: return game.state.round_number == 1 and not game.busy), "escolas chegam pelo servidor e a rodada 1 começa")
	await _until(func() -> bool: return _b_match.commands.size() == 1)
	_check(_synced(game, room_id), "A, B e o servidor no mesmo estado depois das escolas")

	_check(game.state.active.def_id == _b_match.initiative[0].hero, "quem ganhou a iniciativa começa")

	# Rodada 1: cada um joga o seu herói; o outro jogador é recusado.
	for turn in 3:
		var hero: String = game.state.active.def_id
		var before := _turn_key(game)
		if _a_owns(hero):
			_b_command({"type": "end_turn"})
			_check(await _b_wait("error") != {}, "B não joga pelo %s de A" % hero)
		else:
			await game.end_turn()
			await _frames(5)
			_check(_turn_key(game) == before, "A não joga pelo %s de B, que está online" % hero)
		_check(await _pass_turn(game, _a_owns(hero)), "vez do %s passa" % hero)
	_check(game.state.round_number == 2, "Zargon joga e começa a rodada 2")
	await _until(func() -> bool: return _b_match.commands.size() == _server.rooms[room_id].quest_match.commands.size())
	_check(_synced(game, room_id), "A, B e o servidor no mesmo estado na rodada 2")

	# --- B cai: o Anão fica ausente e A pode jogar por ele ---
	_b.close()
	_check(await _until(func() -> bool: return Net.seat("dwarf") != null and not Net.seat("dwarf").online), "A vê B offline")
	for turn in 3:
		_check(await _pass_turn(game, true), "A joga a rodada 2 inteira (o Anão ausente também)")
	_check(game.state.round_number == 3, "rodada 3")

	# --- B volta: entra sem senha (já tem assento) e recebe a partida inteira ---
	_b = NetClient.new()
	_b_room = {}
	_b.connect_to(_url)
	await _until(func() -> bool: return _b.is_open())
	_b.send({"t": "hello", "token": _b_token, "name": "Bia", "version": Protocol.VERSION})
	await _b_wait("welcome")
	_b.send({"t": "enter_room", "id": room_id})
	_check(await _b_wait("room") != {}, "B volta sem digitar a senha")
	_b_match = Match.from_dict(_b_room.campaign.in_progress)
	_check(_b_match != null and _synced(game, room_id), "B retoma a partida no mesmo estado")

	# --- A sai da partida e volta pela tela da campanha ---
	game.leave()
	await _frames(2)
	hub = Session.current_screen()
	_check(hub.has_method("sit"), "sair da partida volta à sala")
	var hash_before: String = _server.rooms[room_id].quest_match.state_hash()
	hub.play("sandbox")
	_check(await _until(func() -> bool: return Session.current_screen().has_method("choose_schools")), "Continuar reabre a quest")
	game = Session.current_screen()
	await _frames(2)
	_check(game.quest_match.state_hash() == hash_before, "A retoma no mesmo ponto")

	# --- Servidor reinicia e lê a sala do disco ---
	_server.stop()
	_server.queue_free()
	await _frames(2)
	_start_server()
	var reloaded := _server._wake(room_id)
	_check(reloaded != null and reloaded.quest_match != null and reloaded.quest_match.state_hash() == hash_before, "servidor reiniciado retoma a quest do disco")
	_check(reloaded != null and Array(reloaded.heroes_of(_b_token)) == ["dwarf"], "assentos gravados")
	_check(_server.store.list("").size() == 1, "índice do lobby gravado")

	# Limpeza.
	_b.close()
	Net.disconnect_server()
	_server.stop()
	Session.host = null
	Session.online = false
	Session.campaign = null
	_wipe(ProjectSettings.globalize_path(DATA))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IDENTITY_A))
	Sfx.stop_all()
	await get_tree().create_timer(0.1, true, false, true).timeout
	print("ONLINE %s (%d falhas)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures else 0)


func _start_server() -> void:
	_server = HqServer.new()
	add_child(_server)
	var port := 18765
	while _server.start(port, ProjectSettings.globalize_path(DATA)) != OK and port < 18800:
		port += 1
	_url = "ws://127.0.0.1:%d" % _server.port


func _process(_delta: float) -> void:
	if _b.ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return
	for msg in _b.poll():
		match msg.t:
			"room":
				_b_room = msg.room
			"applied":
				if _b_match != null and int(msg.seq) == _b_match.commands.size() + 1:
					_b_match.apply(Match._ints(msg.cmd))
					_check(_b_match.state_hash() == msg.hash, "B confere o hash do comando %d" % int(msg.seq))
			"error":
				_b_errors.append(str(msg.reason))
		_b_inbox.append(msg)


## Espera B receber uma mensagem do tipo `t` ({} se não chegou).
func _b_wait(t: String) -> Dictionary:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		for i in _b_inbox.size():
			if _b_inbox[i].t == t:
				var msg: Dictionary = _b_inbox[i]
				_b_inbox = _b_inbox.slice(i + 1)
				return msg
		await get_tree().process_frame
	return {}


func _b_command(cmd: Dictionary) -> void:
	_b.send({"t": "command", "cmd": cmd})


func _a_owns(hero: String) -> bool:
	return hero == "barbarian" or hero == "wizard"


func _turn_key(game: Node) -> Array:
	return [game.state.round_number, game.state.active.def_id if game.state.active != null else ""]


## Encerra a vez do herói ativo (por A ou por B) e espera a próxima vez começar.
func _pass_turn(game: Node, by_a: bool) -> bool:
	var before := _turn_key(game)
	if by_a:
		await game.end_turn()
	else:
		_b_command({"type": "end_turn"})
	return await _until(func() -> bool: return _turn_key(game) != before and game.state.active != null and not game.busy)


## Servidor, A e B com o mesmo log e o mesmo hash.
func _synced(game: Node, room_id: String) -> bool:
	var server_match: Match = _server.rooms[room_id].quest_match
	var digest := server_match.state_hash()
	return game.quest_match.state_hash() == digest and _b_match.state_hash() == digest \
		and game.quest_match.commands.size() == server_match.commands.size()


func _until(cond: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_wipe(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("✗ ", what)
