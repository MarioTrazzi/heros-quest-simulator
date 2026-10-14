class_name Match
extends RefCounted
## Partida = quest + seed + heróis do começo + lista de comandos.
##
## Toda ação de jogador entra aqui como um comando serializável ({"type", ...},
## só números, textos e listas), é validada, aplicada no GameState e anotada no
## log. Como as regras são determinísticas (único RNG é o Dice com seed),
## reaplicar o log num GameState novo chega exatamente ao mesmo estado: é assim
## que a partida é gravada no meio, retomada e sincronizada em rede.
##
## A vez de Zargon também roda aqui (a apresentação só anima): os eventos de
## cada monstro vêm num {"type": "zargon_turn", "unit", "events"}.
##
## Comandos (células como [x, y]):
##   {"type": "schools", "wizard": escola, "elf": escola}
##   {"type": "roll"} · {"type": "end_turn"}
##   {"type": "move", "to": [x, y]} · {"type": "jump", "to": [x, y]}
##   {"type": "open_door", "from": [x, y], "to": [x, y]}
##   {"type": "attack", "target": índice em state.units}
##   {"type": "disarm", "cell": [x, y]}
##   {"type": "search_treasure"} · {"type": "search_traps"}
##   {"type": "use_item", "index": n}
##   {"type": "cast", "spell": id, "target": {"unit": n} | {"door": [[x, y], [x, y]]}}

var quest_id := ""
var seed_value := 0
## Registros da campanha ({"id", "gold", "equipment"}) na ordem dos turnos; vazio = heróis novos.
var heroes: Array[Dictionary] = []
var commands: Array[Dictionary] = []
## Online: a rolagem que decidiu a ordem dos heróis ([{"hero", "rolls"}] na ordem dos turnos; ver roll_initiative).
var initiative: Array = []
var state: GameState
## Eventos de begin() guardados por from_dict (a partida que abre ainda sem comandos os anima).
var opening: Array[Dictionary] = []


static func create(p_quest_id: String, p_seed: int, hero_records: Array = []) -> Match:
	var m := Match.new()
	m.quest_id = p_quest_id
	m.seed_value = p_seed
	for rec: Dictionary in hero_records:
		m.heroes.append({"id": rec.id, "gold": int(rec.gold), "equipment": rec.equipment.duplicate()})
	m._build()
	return m


func _build() -> void:
	var units: Array[Unit] = []
	for rec in heroes:
		units.append(Campaign.unit_from_record(rec))
	state = QuestLoader.build(GameData.quest(quest_id), seed_value, units)


## Eventos de abertura: a rodada 1 (ou nada, se Mago/Elfo ainda escolhem as escolas).
func begin() -> Array[Dictionary]:
	if Magic.needs_school_choice(state):
		return []
	return _follow([state.start_round()])


## Aplica o comando; [] se não vale agora (e aí não entra no log).
func apply(cmd: Dictionary) -> Array[Dictionary]:
	var ev := _execute(cmd)
	if ev.is_empty():
		return []
	commands.append(cmd.duplicate(true))
	return _follow([ev])


func _execute(cmd: Dictionary) -> Dictionary:
	if cmd.get("type") == "schools":
		return _schools(cmd)
	var hero := state.active
	if hero == null or not hero.is_hero() or state.round_number == 0:
		return {}
	match cmd.get("type"):
		"roll":
			if state.needs_movement_roll() and state.can_move():
				return state.roll_movement()
		"end_turn":
			return state.end_turn()
		"move":
			var to: Variant = _cell(cmd.get("to"))
			if to != null and state.flood_for(hero, state.move_left).has(to):
				return state.move_active(to)
		"jump":
			var to: Variant = _cell(cmd.get("to"))
			if to != null:
				return state.jump_pit(to)
		"open_door":
			var from: Variant = _cell(cmd.get("from"))
			var to: Variant = _cell(cmd.get("to"))
			if from != null and to != null:
				return state.open_door(from, to)
		"attack":
			var target := _unit(cmd.get("target"))
			if target != null and target.is_alive():
				return state.attack(target)
		"disarm":
			var cell: Variant = _cell(cmd.get("cell"))
			if cell != null:
				return Exploration.disarm(state, cell)
		"search_treasure":
			return Exploration.search_treasure(state)
		"search_traps":
			return Exploration.search_traps(state)
		"use_item":
			return Exploration.use_item(state, int(cmd.get("index", -1)))
		"cast":
			var target: Variant = _spell_target(cmd.get("target"))
			if target != null:
				return Magic.cast(state, str(cmd.get("spell", "")), target)
	return {}


func _schools(cmd: Dictionary) -> Dictionary:
	if state.round_number != 0 or not Magic.needs_school_choice(state):
		return {}
	var schools: Dictionary = GameData.module("spells").schools
	var wizard := str(cmd.get("wizard", ""))
	var elf := str(cmd.get("elf", ""))
	if not schools.has(wizard) or not schools.has(elf) or wizard == elf:
		return {}
	Magic.assign_schools(state, wizard, elf)
	var ev := state.start_round()
	ev["schools"] = {"wizard": wizard, "elf": elf}
	return ev


## Encadeia o que vem sozinho depois de um evento: quem saiu pela escada encerra
## o turno, e a fase de Zargon roda os monstros e começa a rodada seguinte.
func _follow(out: Array[Dictionary]) -> Array[Dictionary]:
	while true:
		var last: Dictionary = out[-1]
		if last.get("type") == "move" and last.has("escaped") and state.active != null:
			out.append(state.end_turn())
		elif last.get("type") == "zargon_phase":
			for monster in state.alive(Unit.Side.MONSTER):
				var events := ZargonAI.take_turn(state, monster)
				if not events.is_empty():
					out.append({"type": "zargon_turn", "unit": monster, "events": events})
				if state.alive(Unit.Side.HERO).is_empty():
					break
			out.append(state.start_round())
		else:
			return out
	return out


# ---------- iniciativa ----------

## Ordem da mesa online: cada herói rola 1d6; empate no maior número rola de novo
## (só os empatados); quem tirar mais começa e os outros seguem em ordem sorteada.
## Devolve [{"hero", "rolls": [valores]}] na ordem dos turnos. Mesma seed, mesma ordem.
static func roll_initiative(hero_ids: Array, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if hero_ids.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rolls := {}
	for id: String in hero_ids:
		rolls[id] = []
	var contenders: Array = hero_ids.duplicate()
	while contenders.size() > 1 or rolls[contenders[0]].is_empty():
		var best := 0
		for id: String in contenders:
			var value := rng.randi_range(1, 6)
			rolls[id].append(value)
			best = maxi(best, value)
		contenders = contenders.filter(func(id: String) -> bool: return rolls[id][-1] == best)
	var first: String = contenders[0]
	var rest: Array = hero_ids.filter(func(id: String) -> bool: return id != first)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = rest[i]
		rest[i] = rest[j]
		rest[j] = swap
	for id: String in [first] + rest:
		out.append({"hero": id, "rolls": rolls[id]})
	return out


# ---------- comandos ----------

## Comando pronto para um alvo de feitiço (unidade ou porta [a, b]).
func spell_command(spell_id: String, target: Variant) -> Dictionary:
	var spec := {}
	if target is Unit:
		spec = {"unit": state.units.find(target)}
	else:
		spec = {"door": [_pair(target[0]), _pair(target[1])]}
	return {"type": "cast", "spell": spell_id, "target": spec}


static func _pair(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


static func cell_arg(cell: Vector2i) -> Array:
	return _pair(cell)


static func _cell(value: Variant) -> Variant:
	if not value is Array or value.size() != 2:
		return null
	return Vector2i(int(value[0]), int(value[1]))


func _unit(value: Variant) -> Unit:
	if value == null:
		return null
	var index := int(value)
	return state.units[index] if index >= 0 and index < state.units.size() else null


func _spell_target(spec: Variant) -> Variant:
	if not spec is Dictionary:
		return null
	if spec.has("unit"):
		return _unit(spec.unit)
	if spec.has("door") and spec.door is Array and spec.door.size() == 2:
		var a: Variant = _cell(spec.door[0])
		var b: Variant = _cell(spec.door[1])
		if a != null and b != null:
			return [a, b]
	return null


# ---------- save / replay ----------

func to_dict() -> Dictionary:
	var out := {"quest_id": quest_id, "seed": seed_value, "heroes": heroes, "commands": commands}
	if not initiative.is_empty():
		out.initiative = initiative
	return out


## Reconstrói a partida reaplicando o log (sem animar). null se o log não fecha.
static func from_dict(data: Dictionary) -> Match:
	var m := Match.create(str(data.get("quest_id", "")), int(data.get("seed", 0)), data.get("heroes", []))
	m.initiative = _ints(data.get("initiative", []))
	m.opening = m.begin()
	for cmd: Dictionary in data.get("commands", []):
		if m.apply(_ints(cmd)).is_empty():
			push_error("Match: comando %s não vale no replay" % [cmd])
			return null
	return m


## O JSON lê número como float: devolve o comando com inteiros.
static func _ints(value: Variant) -> Variant:
	if value is float:
		return int(value)
	if value is Array:
		return value.map(_ints)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _ints(value[key])
		return out
	return value


## Resumo do estado que importa para as regras; dois clientes em dia têm o mesmo hash.
func state_hash() -> String:
	var units := []
	for u in state.units:
		units.append([u.def_id, u.pos, u.body, u.mind, u.gold, u.alerted, u.escaped, u.in_pit,
			u.inventory.map(func(c: Dictionary) -> String: return str(c.get("id", ""))),
			u.spells, u.status.keys(), u.buffs])
	var doors := []
	for key: Vector4i in state.board.doors:
		var door: Dictionary = state.board.doors[key]
		doors.append([key, door.open, door.secret])
	var snapshot := [state.round_number, state.units.find(state.active), state.move_left,
		state.has_moved, state.has_acted, units, doors, state.revealed.size(), state.traps.keys(),
		state.board.blocked.keys(), state.treasure_deck.size(), state.searched_treasure.keys(),
		state.objective_found, state.dice.rng.state]
	return var_to_str(snapshot).sha256_text()
