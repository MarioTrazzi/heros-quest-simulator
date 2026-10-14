class_name GameState
extends RefCounted
## Estado da partida e o turno da figura ativa. Não conhece nada de 3D:
## as ações devolvem eventos (Dictionary) para a apresentação animar.
##
## Regra do turno: mover e depois agir, ou agir e depois mover — nunca
## mover, agir e mover de novo. O movimento pode ser feito em vários trechos.
## Busca, tesouro, desarme e itens ficam em Exploration.

var board: Board
var dice: Dice
var units: Array[Unit] = []
## Quest em jogo (JSON) e os móveis colocados: {"id", "pos", "size", "rot"}.
var quest: Dictionary = {}
var furniture: Array[Dictionary] = []
var round_number := 0

## Névoa de guerra: quadrados já revelados (Vector2i -> true). Sala é revelada
## inteira; corredor, só o que algum herói viu.
var revealed: Dictionary = {}
var _revealed_zones: Dictionary = {}
## Armadilhas: Vector2i -> {"id": "pit"|"spear"|"falling_block"|"chest", "known": bool, ...}.
var traps: Dictionary = {}
## Tesouro definido pela quest, por sala: zona -> [{"gold", "item", "text"}, ...].
var treasures: Dictionary = {}
## Quem já procurou tesouro em qual sala: "zona:id do herói" -> true.
var searched_treasure: Dictionary = {}
var treasure_deck: Array[Dictionary] = []
var wandering_monster := "orc"
## Objetivo: {"type": "escape" | "kill" (monstros com is_objective) | "kill_all" |
## "escort" (o aliado resgatado sai pela escada; se ele morrer, a quest falha) |
## "find" (tesouro com objective_item), "text"}. A quest acaba bem quando o
## objetivo está cumprido e os heróis vivos saíram pela escada.
var objective: Dictionary = {"type": "escape"}
var objective_found := false
var stairway: Array[Vector2i] = []
## Monstros que despertam quando um herói entra na sala (zona):
## [{"zone", "id", "pos", "override"?, "name"?, "text"?}].
var ambushes: Array[Dictionary] = []
## Prisioneiro a resgatar (objetivo "escort"): {"pos", "id", "name", "attack",
## "defend", "body", "mind", "move_dice", "reward"?, "text"?}. Vira aliado
## quando algum herói vê o quadrado dele.
var captive: Dictionary = {}
var rescuer: Unit
var rescue_reward := 0

var active: Unit
## -1 = herói ainda não rolou o movimento neste turno.
var move_left := 0
var has_moved := false
var has_acted := false
var _moved_before_action := false
## Heróis que ainda vão jogar nesta rodada.
var _queue: Array[Unit] = []


func _init(p_board: Board, seed_value := 0) -> void:
	board = p_board
	dice = Dice.new(seed_value)


func add_unit(unit: Unit, cell: Vector2i) -> void:
	assert(board.is_walkable(cell) and unit_at(cell) == null, "quadrado ocupado: %s" % cell)
	unit.pos = cell
	units.append(unit)


func unit_at(cell: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and not u.escaped and u.pos == cell:
			return u
	return null


func is_occupied(cell: Vector2i) -> bool:
	return unit_at(cell) != null


## Figuras vivas no tabuleiro (quem saiu pela escada não conta).
func alive(side: Unit.Side) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and not u.escaped and u.side == side:
			out.append(u)
	return out


func can_see(from: Vector2i, to: Vector2i) -> bool:
	return LineOfSight.can_see(board, from, to, is_occupied)


## Para quem `mover` está andando: aliado se atravessa, inimigo bloqueia
## (com Véu de Névoa, atravessa também); fosso conhecido bloqueia todo mundo.
func occupancy_for(mover: Unit) -> Callable:
	var through_enemies := mover.buffs.has("pass_monsters")
	return func(cell: Vector2i) -> int:
		if is_known_pit(cell):
			return Pathfinder.BLOCKED
		var other := unit_at(cell)
		if other == null:
			return Pathfinder.FREE
		if other.side == mover.side or through_enemies:
			return Pathfinder.PASS_ONLY
		return Pathfinder.BLOCKED


func flood_for(unit: Unit, steps: int) -> Dictionary:
	return Pathfinder.flood(board, unit.pos, steps, occupancy_for(unit), unit.buffs.has("through_walls"))


func is_known_pit(cell: Vector2i) -> bool:
	return traps.has(cell) and traps[cell].known and traps[cell].id == "pit"


## Portas fechadas (e já conhecidas) coladas no quadrado: [[a, b], ...].
## Porta falsa aparece até alguém tentar abrir.
func closed_doors_next_to(cell: Vector2i) -> Array:
	var out: Array = []
	for dir in Board.DIRS:
		var door := board.door_between(cell, cell + dir)
		if not door.is_empty() and not door.open and not door.secret and not door.get("fake_known", false):
			out.append([cell, cell + dir])
	return out


# ---------- visibilidade ----------

## Revela o que os heróis veem e acorda os monstros que ficaram à vista.
## {"revealed": quadrados novos, "alerted": monstros que acordaram agora}.
func update_visibility() -> Dictionary:
	var fresh: Array[Vector2i] = []
	for hero in alive(Unit.Side.HERO):
		if board.is_room(hero.pos):
			_reveal_zone(board.zone_at(hero.pos), fresh)
		else:
			_reveal_cell(hero.pos, fresh)
		for y in board.height:
			for x in board.width:
				var cell := Vector2i(x, y)
				if revealed.has(cell) or not LineOfSight.can_see(board, hero.pos, cell, _nobody):
					continue
				if board.is_room(cell):
					_reveal_zone(board.zone_at(cell), fresh)
				else:
					_reveal_cell(cell, fresh)
	var woke: Array[Unit] = []
	var out := {"revealed": fresh, "alerted": woke}
	if not captive.is_empty() and revealed.has(captive.pos):
		out["rescue"] = _rescue(fresh)
	for monster in alive(Unit.Side.MONSTER):
		if not monster.alerted and revealed.has(monster.pos):
			monster.alerted = true
			woke.append(monster)
	return out


## Achou o prisioneiro: ele vira aliado (joga logo depois de quem o achou) e
## soa o alarme — o mapa todo aparece, todas as portas abrem e todo monstro
## fica alertado. {"ally", "rescuer", "doors": [[a, b]...], "text"}.
func _rescue(fresh: Array[Vector2i]) -> Dictionary:
	var spec := captive
	captive = {}
	rescuer = active if active != null and active.is_hero() else alive(Unit.Side.HERO)[0]
	var ally := Unit.from_hero(spec)
	ally.escort = true
	ally.pos = spec.pos
	rescue_reward = int(spec.get("reward", 0))
	units.insert(units.find(rescuer) + 1, ally)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			if not board.dark.has(cell):
				_reveal_cell(cell, fresh)
	var opened: Array = []
	for key: Vector4i in board.doors:
		var door: Dictionary = board.doors[key]
		if not door.open and not door.secret and not door.fake:
			door.open = true
			opened.append([Vector2i(key.x, key.y), Vector2i(key.z, key.w)])
	return {"ally": ally, "rescuer": rescuer, "doors": opened, "text": spec.get("text", "")}


func _reveal_zone(zone: int, fresh: Array[Vector2i]) -> void:
	if _revealed_zones.has(zone):
		return
	_revealed_zones[zone] = true
	for cell in board.cells_of_zone(zone):
		_reveal_cell(cell, fresh)


func _reveal_cell(cell: Vector2i, fresh: Array[Vector2i]) -> void:
	if not revealed.has(cell):
		revealed[cell] = true
		fresh.append(cell)


## Para revelar, figuras não tapam a visão (só paredes e portas fechadas).
func _nobody(_cell: Vector2i) -> bool:
	return false


# ---------- objetivo e fim da quest ----------

func is_objective_done() -> bool:
	match objective.get("type", "escape"):
		"kill":
			return not units.any(func(u: Unit) -> bool: return u.is_objective and u.is_alive())
		"kill_all":
			return alive(Unit.Side.MONSTER).is_empty()
		"find":
			return objective_found
		"escort":
			return units.any(func(u: Unit) -> bool: return u.escort and u.escaped)
	return true


func _escort_dead() -> bool:
	return units.any(func(u: Unit) -> bool: return u.escort and not u.is_alive())


## Herói na escada com o objetivo cumprido sai do tabuleiro (a salvo).
func try_escape(unit: Unit) -> Dictionary:
	if unit == null or not unit.is_hero() or unit.escaped or not stairway.has(unit.pos):
		return {}
	if not unit.escort and not is_objective_done():
		return {}
	unit.escaped = true
	unit.pos = Vector2i(-1, -1)
	var out := {"escaped": unit}
	# A recompensa do resgate vai para quem achou o prisioneiro.
	if unit.escort and rescuer != null and rescuer.is_alive() and rescue_reward > 0:
		rescuer.gold += rescue_reward
		out["reward"] = {"to": rescuer, "gold": rescue_reward}
	return out


## "victory", "defeat" ou "" (ainda em jogo). Só acaba quando não sobra herói
## no tabuleiro: vitória se alguém saiu com o objetivo cumprido.
## O aliado escoltado não segura a quest sozinho: conta só quem é herói de verdade.
func outcome() -> String:
	if objective.get("type") == "escort" and _escort_dead():
		return "defeat"
	if alive(Unit.Side.HERO).any(func(u: Unit) -> bool: return not u.escort):
		return ""
	var escaped := units.any(func(u: Unit) -> bool: return u.escaped and not u.escort)
	return "victory" if escaped and is_objective_done() else "defeat"


func _end_event(result: String) -> Dictionary:
	return {"type": "quest_complete" if result == "victory" else "heroes_defeated"}


# ---------- rodada ----------

## Heróis jogam na ordem em que entraram (Bárbaro, Anão, Elfo, Mago);
## depois vem a fase de Zargon, e o controlador chama start_round de novo.
func start_round() -> Dictionary:
	round_number += 1
	_queue = alive(Unit.Side.HERO)
	active = null
	if outcome() != "":
		return _end_event(outcome())
	var ev := end_turn()
	if round_number == 1:
		ev.merge(update_visibility())
	return ev


## Herói sob Tempestade perde o turno; dormindo, rola 1d6 por ponto de Mente
## e só acorda com um 6. Os pulados vão em "skipped" no evento seguinte.
## Quem andou neste turno e terminou na escada (com o objetivo cumprido) sai.
func end_turn() -> Dictionary:
	var escaped := try_escape(active) if has_moved else {}
	var result := outcome()
	if result != "":
		active = null
		var ev := _end_event(result)
		ev.merge(escaped)
		return ev
	var skipped: Array[Dictionary] = []
	while not _queue.is_empty():
		var next: Unit = _queue.pop_front()
		if not next.is_alive():
			continue
		var lost := lose_turn(next)
		if not lost.is_empty():
			skipped.append(lost)
			continue
		begin_turn(next)
		var started := {"type": "turn_started", "unit": active, "round": round_number, "skipped": skipped}
		started.merge(escaped)
		return started
	active = null
	var zargon := {"type": "zargon_phase", "round": round_number, "skipped": skipped}
	zargon.merge(escaped)
	return zargon


## Turno perdido por Tempestade ou sono: {"unit", "reason", "rolls"?} ou {} se joga.
## Quem acorda joga normalmente ({"woke": true} não conta como perdido).
func lose_turn(unit: Unit) -> Dictionary:
	if int(unit.status.get("skip_turns", 0)) > 0:
		unit.status.skip_turns -= 1
		if unit.status.skip_turns == 0:
			unit.status.erase("skip_turns")
		return {"unit": unit, "reason": "tempest"}
	for key: String in ["asleep", "commanded"]:
		if unit.status.get(key, false):
			var rolls := dice.roll_d6(maxi(0, unit.mind))
			if rolls.has(6):
				unit.status.erase(key)
				unit.status.erase("paralyzed")
				return {}
			var reason := "paralyzed" if unit.status.get("paralyzed", false) else key
			return {"unit": unit, "reason": reason, "rolls": rolls}
	return {}


# ---------- turno ----------

func begin_turn(unit: Unit) -> void:
	assert(unit.is_alive())
	active = unit
	has_moved = false
	has_acted = false
	_moved_before_action = false
	move_left = -1 if unit.is_hero() else unit.move


func needs_movement_roll() -> bool:
	return move_left < 0


## Poção de Velocidade dobra os dados.
func roll_movement() -> Dictionary:
	assert(needs_movement_roll(), "movimento já rolado neste turno")
	var mult := maxi(1, active.take_buff("move_mult"))
	var values := dice.roll_d6(active.move_dice * mult)
	move_left = Dice.total(values)
	return {"type": "movement_roll", "unit": active, "values": values, "total": move_left}


func can_move() -> bool:
	if has_acted and _moved_before_action:
		return false
	return needs_movement_roll() or move_left > 0


## Move a figura ativa até target. Evento vazio se o destino não vale.
## Herói que pisa numa armadilha escondida para ali e dispara: o turno acaba.
func move_active(target: Vector2i) -> Dictionary:
	if not can_move() or needs_movement_roll():
		return {}
	var path := Pathfinder.path_to(flood_for(active, move_left), target)
	if path.is_empty():
		return {}
	var from := active.pos
	var sprung := -1
	if active.is_hero():
		for i in path.size():
			if traps.has(path[i]) and not traps[path[i]].known:
				sprung = i
				break
	if sprung >= 0:
		path = path.slice(0, sprung + 1)
	active.pos = path[-1]
	active.in_pit = false
	active.take_buff("through_walls")
	active.take_buff("pass_monsters")
	move_left -= path.size()
	has_moved = true
	var ev := {"type": "move", "unit": active, "from": from, "path": path}
	if sprung >= 0:
		var came_from: Vector2i = path[-2] if path.size() > 1 else from
		ev["trap"] = Exploration.spring_trap(self, active, path[-1], came_from)
		move_left = 0
		has_acted = true
		_moved_before_action = true
	ev.merge(update_visibility())
	if active.is_hero():
		var ambush := _spring_ambush(active)
		if not ambush.is_empty():
			ev["ambush"] = ambush
	var escaped := try_escape(active)
	if not escaped.is_empty():
		ev.merge(escaped)
		move_left = 0
		has_acted = true
	return ev


func can_act() -> bool:
	return not has_acted


# ---------- pular fosso ----------

## Pular um fosso conhecido (regra de 2021): o herói está colado no fosso, mira
## o quadrado logo depois dele em linha reta e tem 2+ de movimento.
func can_jump(target: Vector2i) -> bool:
	if active == null or not active.is_hero() or not can_move() or needs_movement_roll() or move_left < 2:
		return false
	var delta := target - active.pos
	if absi(delta.x) + absi(delta.y) != 2 or (delta.x != 0 and delta.y != 0):
		return false
	var pit := active.pos + delta / 2
	return is_known_pit(pit) and not board.is_wall(active.pos, pit) and not board.is_wall(pit, target) \
		and board.is_walkable(target) and not is_occupied(target) and not is_known_pit(target)


## 1 dado de combate: escudo passa (gasta 2 de movimento); caveira cai no
## fosso (1 de dano) e o turno acaba.
func jump_pit(target: Vector2i) -> Dictionary:
	if not can_jump(target):
		return {}
	var from := active.pos
	var pit := from + (target - from) / 2
	var faces := dice.roll_combat(1)
	var ev := {"type": "jump", "unit": active, "from": from, "pit": pit, "target": target, "faces": faces}
	has_moved = true
	if faces[0] != Dice.SKULL:
		active.pos = target
		active.in_pit = false
		move_left -= 2
		ev["success"] = true
	else:
		active.pos = pit
		active.in_pit = true
		active.take_damage(1)
		move_left = 0
		has_acted = true
		_moved_before_action = true
		ev["success"] = false
		ev["damage"] = 1
		ev.merge(after_damage(active))
		ev["killed"] = not active.is_alive()
	ev.merge(update_visibility())
	return ev


## Ataque do turno. Heroic Brew deixa atacar de novo no mesmo turno.
func attack(target: Unit) -> Dictionary:
	if not can_act() or not Combat.can_attack(self, active, target):
		return {}
	spend_action()
	var ev := strike(active, target)
	if active.take_buff("extra_attacks") > 0:
		has_acted = false
	return ev


## Golpe sem checar turno (ataque normal, monstro errante, Gênio), com os
## bônus de poção/Coragem, Pele de Pedra, a penalidade do fosso (−1 dado) e o
## sono (quem dorme não defende).
func strike(attacker: Unit, target: Unit, extra_attack := 0) -> Dictionary:
	var attack_bonus := extra_attack + attacker.take_buff("attack") - (1 if attacker.in_pit else 0)
	var defend_bonus := target.take_buff("defend") - (1 if target.in_pit else 0)
	if target.status.has("rock_skin"):
		defend_bonus += 1
	if target.status.get("asleep", false):
		defend_bonus = -999
	var immune := target.has_tag("spirit_blade_only") and not attacker.has_equipment("spirit_blade")
	var ev := Combat.resolve(dice, attacker, target, attack_bonus, defend_bonus, immune)
	if ev.damage > 0:
		target.status.erase("rock_skin")
	ev.merge(after_damage(target, attacker))
	ev.killed = not target.is_alive()
	return ev


## Depois de qualquer dano: poção salva da morte; herói que morre mesmo assim
## deixa ouro e poções para um aliado na mesma sala (senão os monstros ficam
## com tudo); monstro que carregava item da quest o entrega a `by` (ou a um
## herói na sala; sem ninguém, o item fica como tesouro da sala).
## {"saved_by_potion"?, "loot"?, "carried"?}.
func after_damage(unit: Unit, by: Unit = null) -> Dictionary:
	var out := save_from_death(unit)
	if unit.is_hero() and not unit.is_alive():
		out["loot"] = _drop_loot(unit)
	elif not unit.is_alive() and not unit.carries.is_empty():
		out["carried"] = _drop_carried(unit, by)
	return out


## {"to": herói ou null, "item"}.
func _drop_carried(dead: Unit, by: Unit) -> Dictionary:
	var item := dead.carries
	dead.carries = {}
	var to: Unit = by if by != null and by.is_hero() and by.is_alive() else null
	if to == null:
		for hero in alive(Unit.Side.HERO):
			if board.same_room(hero.pos, dead.pos):
				to = hero
				break
	if to == null:
		var zone := board.zone_at(dead.pos)
		if not treasures.has(zone):
			treasures[zone] = []
		treasures[zone].push_front(item)
	else:
		to.gold += int(item.get("gold", 0))
		if item.get("objective_item", false):
			objective_found = true
	return {"to": to, "item": item}


## Herói entrou numa sala com monstro adormecido: ele surge (alertado) no
## quadrado marcado ou no livre mais perto. {"monster", "text"} ou {}.
func _spring_ambush(hero: Unit) -> Dictionary:
	if not board.is_room(hero.pos):
		return {}
	var zone := board.zone_at(hero.pos)
	for i in ambushes.size():
		var ambush := ambushes[i]
		if int(ambush.zone) != zone:
			continue
		ambushes.remove_at(i)
		var cell: Vector2i = ambush.pos
		if is_occupied(cell) or not board.is_walkable(cell):
			cell = Vector2i(-1, -1)
			for c in board.cells_of_zone(zone):
				if board.is_walkable(c) and not is_occupied(c) and not is_known_pit(c):
					cell = c
					break
		if cell == Vector2i(-1, -1):
			return {}
		var monster := GameData.new_monster(ambush.id)
		for key: String in ambush.get("override", {}):
			QuestLoader.apply_override(monster, key, ambush.override[key])
		monster.is_objective = ambush.get("objective", false)
		monster.alerted = true
		add_unit(monster, cell)
		revealed[cell] = true
		return {"monster": monster, "text": ambush.get("text", "")}
	return {}


func _drop_loot(dead: Unit) -> Dictionary:
	var heir: Unit = null
	for hero in alive(Unit.Side.HERO):
		if board.same_room(hero.pos, dead.pos):
			heir = hero
			break
	var loot := {"to": heir, "gold": dead.gold, "items": dead.inventory.size()}
	if heir != null:
		heir.gold += dead.gold
		heir.inventory.append_array(dead.inventory)
	dead.gold = 0
	dead.inventory.clear()
	return loot


## Herói que chega a 0 de Corpo bebe a poção de cura na hora, se tiver.
## {"saved_by_potion": cura} ou {}.
func save_from_death(unit: Unit) -> Dictionary:
	if not unit.is_hero() or unit.is_alive():
		return {}
	for i in unit.inventory.size():
		var potion: Dictionary = unit.inventory[i].get("potion", {})
		if potion.has("heal"):
			if not unit.inventory[i].get("quest_item", false):
				treasure_deck.append(unit.inventory[i])
			unit.inventory.remove_at(i)
			var amount := Exploration.heal_amount(self, potion.heal)
			unit.heal(amount)
			return {"saved_by_potion": amount}
	return {}


## Abrir porta é livre: basta estar ao lado dela.
func open_door(from: Vector2i, to: Vector2i) -> Dictionary:
	if active == null or active.pos != from or not active.is_hero():
		return {}
	var door := board.door_between(from, to)
	if door.is_empty() or door.open or door.secret:
		return {}
	if door.get("fake", false):
		door["fake_known"] = true
		return {"type": "fake_door", "unit": active, "a": from, "b": to}
	board.open_door(from, to)
	var ev := {"type": "door_opened", "unit": active, "a": from, "b": to}
	ev.merge(update_visibility())
	return ev


func spend_action() -> void:
	has_acted = true
	_moved_before_action = has_moved
