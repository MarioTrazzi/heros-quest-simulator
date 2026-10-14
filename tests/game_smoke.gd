extends Node
## Smoke da partida 3D: abre scenes/game.tscn e joga um pouco por código.
##   godot --headless --path . res://tests/game_smoke.tscn
##   godot --path . --write-movie /tmp/f.png res://tests/game_smoke.tscn   # com quadros
## Sai com código ≠ 0 se falhar. Roda com o tempo acelerado (Engine.time_scale).

const MAX_WAIT_MS := 20000

var _failures := 0
var _game: Node


func _ready() -> void:
	Session.preview = false  # os testes contam com a névoa e o bloqueio das quests
	OS.set_environment("HQ_SEED", "11")
	OS.set_environment("HQ_QUEST", "sandbox")
	Engine.time_scale = 4.0
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	var state: GameState = _game.state
	_check(state.round_number == 0, "espera a escolha das escolas")
	await _game.choose_schools("fire", "water")
	await _idle()
	var wizard: Unit = state.alive(Unit.Side.HERO)[3]
	_check(wizard.spells.size() == 9, "Mago recebeu 9 feitiços")

	_check(state.active != null and state.active.def_id == "barbarian", "Bárbaro começa")
	_check(_game.figures.size() == state.units.size(), "uma miniatura por figura")
	_check(state.board.doors.size() == 11, "11 portas na sandbox")

	# Andar exige rolar antes.
	await _game.click_cell(Vector2i(12, 7))
	_check(state.active.pos == Vector2i(10, 7), "sem rolar não anda")
	await _game.roll_movement()
	_check(not state.needs_movement_roll(), "rolou o movimento")

	# Bárbaro passa pelo aliado até a porta de cima da sala central (2 passos).
	var barbarian: Unit = state.active
	await _game.click_cell(Vector2i(12, 7))
	_check(barbarian.pos == Vector2i(12, 7), "andou até (12, 7)")
	_check(_figure(barbarian).position.distance_to(BoardView.cell_center(Vector2i(12, 7))) < 0.01, "miniatura chegou junto")

	# Clique no quadrado atrás da porta abre a porta, sem gastar a ação,
	# e o Bárbaro avista o goblin do corredor.
	var goblin: Unit = state.unit_at(Vector2i(13, 1))
	await _game.click_cell(Vector2i(12, 6))
	_check(goblin.alerted, "goblin do corredor foi avistado")
	_check(state.board.door_between(Vector2i(12, 6), Vector2i(12, 7)).open, "porta aberta pelo clique")
	_check(state.can_act(), "abrir porta não gasta a ação")

	# Rodízio: Anão, Elfo, Mago e depois nova rodada (Zargon ainda passa).
	var order: Array[String] = []
	for i in 4:
		await _game.end_turn()
		await _idle()
		order.append(state.active.def_id)
	_check(Array(order) == ["dwarf", "elf", "wizard", "barbarian"], "ordem dos turnos: %s" % [order])
	_check(state.round_number == 2, "rodada 2 depois de Zargon")

	# Na vez de Zargon o goblin veio até a porta (único quadrado colado no Bárbaro).
	_check(goblin.pos == Vector2i(12, 6), "goblin veio atacar (%s)" % goblin.pos)
	_check(_figure(goblin).position.distance_to(BoardView.cell_center(goblin.pos)) < 0.01, "miniatura do goblin acompanhou")
	await _game.click_cell(Vector2i(12, 6))
	_check(not state.can_act(), "clique no monstro ataca")
	var rounds := 0
	while goblin.is_alive() and barbarian.is_alive() and rounds < 30:
		await _next_barbarian_turn(state)
		await _game.click_cell(Vector2i(12, 6))
		rounds += 1
	await _idle()
	_check(not goblin.is_alive(), "goblin morre")
	_check(not _game.figures.has(goblin), "miniatura do morto sai da cena")

	# Zargon joga, mas o goblin da sala C (porta fechada) nunca foi visto.
	var room_goblin: Unit = state.units.filter(func(u: Unit) -> bool: return u.def_id == "goblin" and u.pos == Vector2i(10, 3))[0]
	for i in 3:
		await _next_barbarian_turn(state)
	_check(room_goblin.pos == Vector2i(10, 3) and not room_goblin.alerted, "monstro trancado não age")
	_check(_party_text().contains("Bárbaro"), "painel do grupo mostra os heróis")

	# Névoa: o goblin da sala C (nunca revelada) nem aparece.
	_check(not state.revealed.has(room_goblin.pos) and not _figure(room_goblin).visible, "monstro na névoa fica escondido")

	# Procurar armadilhas na sala central acha (e desarma) a lança de (14, 9).
	await _next_barbarian_turn(state)
	var hero: Unit = state.active
	hero.pos = Vector2i(13, 9)
	_figure(hero).position = BoardView.cell_center(hero.pos)
	await _game.search_traps()
	_check(not state.traps.has(Vector2i(14, 9)) and not state.can_act(), "F acha a lança e gasta a ação")

	# Procurar tesouro: força um monstro errante no topo do baralho.
	await _next_barbarian_turn(state)
	var monsters_before := state.alive(Unit.Side.MONSTER).size()
	for i in state.treasure_deck.size():
		if state.treasure_deck[i].get("wandering_monster", false):
			state.treasure_deck.push_front(state.treasure_deck.pop_at(i))
			break
	await _game.search_treasure()
	await _idle()
	var monsters_after := state.alive(Unit.Side.MONSTER)
	_check(monsters_after.size() == monsters_before + 1, "monstro errante entra no jogo")
	var wanderer: Unit = monsters_after[-1]
	_check(_game.figures.has(wanderer) and _figure(wanderer).visible, "miniatura do errante aparece")

	# Magia pela interface: o Mago escolhe Pele de Pedra e clica em si mesmo.
	for i in 8:
		if state.active == wizard or not wizard.is_alive():
			break
		await _game.end_turn()
		await _idle()
	if wizard.is_alive() and state.active == wizard:
		_game.select_spell("rock_skin")
		await _game.click_cell(wizard.pos)
		_check(wizard.status.has("rock_skin") and not wizard.spells.has("rock_skin"), "feitiço lançado pelo clique")
		_check(_figure(wizard)._label.text.contains("pele de pedra"), "status aparece sobre a miniatura")

	# Bola de Fogo toda resistida (5 e 5): só a animação, sem mexer no estado.
	await _game._play_spell({"type": "spell", "caster": wizard, "spell": GameData.spell("ball_of_flame"),
		"target": wanderer, "resist": [5, 5], "damage": 0, "killed": false})
	_check(_figure(wanderer).get_children().any(func(n: Node) -> bool: return n is Label3D and n.text == "Resistiu"),
		"Bola de Fogo resistida mostra \"Resistiu\"")

	await _test_barak_tor()
	await _test_rescue()

	Sfx.stop_all()
	await get_tree().create_timer(0.1, true, false, true).timeout
	print("PARTIDA %s (%d falhas)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures else 0)


func _figure(unit: Unit) -> FigureView:
	return _game.figures[unit]


## Espera a animação em curso acabar.
func _idle() -> void:
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while _game.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not _game.busy, "animação travada")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("✗ ", what)


## Encerra turnos até ser a vez do Bárbaro de novo (passando por Zargon).
func _next_barbarian_turn(state: GameState) -> void:
	for i in 6:
		await _game.end_turn()
		await _idle()
		if state.active != null and state.active.def_id == "barbarian":
			return


func _party_text() -> String:
	return _game.hud.party_text()


## A quest real (mapa do HeroScribe) abre, mostra a área escura e roda rodadas.
func _test_barak_tor() -> void:
	_game.queue_free()
	await get_tree().process_frame
	OS.set_environment("HQ_QUEST", "barak_tor")
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	var state: GameState = _game.state
	await _game.choose_schools("air", "earth")
	await _idle()
	_check(state.quest.id == "barak_tor" and _game.figures.size() == state.units.size(), "Barak Tor abre com todas as miniaturas")
	_check(state.active != null and state.stairway.has(state.active.pos), "começa na escada")
	_check(not _game.board_view._tiles[Vector2i(20, 2)].visible, "área escura sem piso")
	for i in 8:
		await _game.end_turn()
		await _idle()
	_check(state.round_number >= 2, "rodadas passam no Barak Tor")

	# Herói entra na sala da tumba: o Rei Bruxo desperta e golpe comum não o fere.
	var hero: Unit = state.alive(Unit.Side.HERO)[0]
	var path: Array[Vector2i] = [Vector2i(2, 13)]
	hero.pos = path[0]
	var ambush := state._spring_ambush(hero)
	await _game._play({"type": "move", "unit": hero, "from": hero.pos, "path": path, "ambush": ambush})
	var lord: Unit = ambush.get("monster")
	_check(lord != null and _game.figures.has(lord) and _game.figures[lord].visible, "Rei Bruxo aparece na sala da tumba")
	await _game._play(state.strike(hero, lord))
	_check(lord.is_alive(), "Rei Bruxo resiste ao golpe")


## Resgate de Sir Ragnar: achar o prisioneiro mostra o aliado, abre as portas e revela tudo.
func _test_rescue() -> void:
	_game.queue_free()
	await get_tree().process_frame
	OS.set_environment("HQ_QUEST", "rescue_sir_ragnar")
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().process_frame
	var state: GameState = _game.state
	await _game.choose_schools("air", "earth")
	await _idle()
	var hero: Unit = state.active
	var path: Array[Vector2i] = [state.captive.pos + Vector2i(1, 0)]
	hero.pos = path[0]
	var ev := {"type": "move", "unit": hero, "from": hero.pos, "path": path}
	ev.merge(state.update_visibility())
	await _game._play(ev)
	var ally: Unit = ev.get("rescue", {}).get("ally")
	_check(ally != null and _game.figures.has(ally) and _game.figures[ally].visible, "Sir Ragnar aparece ao ser achado")
	_check(state.board.doors.values().all(func(d: Dictionary) -> bool: return d.open or d.secret or d.fake), "alarme abre as portas")
	await get_tree().create_timer(0.5).timeout
