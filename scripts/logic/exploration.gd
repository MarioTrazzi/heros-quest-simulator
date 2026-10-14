class_name Exploration
extends RefCounted
## Exploração: procurar (tesouro / armadilhas e portas secretas), disparar e
## desarmar armadilhas, baralho de tesouro, monstro errante e uso de itens.
## Funções estáticas sobre o GameState; cada ação devolve um evento
## (Dictionary vazio = ação não vale agora).


# ---------- condições ----------

## Algum monstro à vista impede procurar: na mesma sala, ou visível no corredor.
static func monster_in_view(state: GameState, hero: Unit) -> bool:
	for monster in state.alive(Unit.Side.MONSTER):
		if not state.revealed.has(monster.pos):
			continue
		if state.board.same_room(hero.pos, monster.pos) or state.can_see(hero.pos, monster.pos):
			return true
	return false


## Sala inteira, ou os quadrados de corredor que se veem dali.
static func search_area(state: GameState, cell: Vector2i) -> Array[Vector2i]:
	var board := state.board
	if board.is_room(cell):
		return board.cells_of_zone(board.zone_at(cell))
	var out: Array[Vector2i] = []
	for c in board.cells_of_zone(Board.CORRIDOR):
		if c == cell or LineOfSight.can_see(board, cell, c, func(_x: Vector2i) -> bool: return false):
			out.append(c)
	return out


static func can_search(state: GameState) -> bool:
	var hero := state.active
	return hero != null and hero.is_hero() and not hero.escort and state.can_act() and not monster_in_view(state, hero)


static func can_search_treasure(state: GameState) -> bool:
	return can_search(state) and state.board.is_room(state.active.pos) \
		and not state.searched_treasure.has(_treasure_key(state, state.active))


static func can_disarm(state: GameState, cell: Vector2i) -> bool:
	var hero := state.active
	if hero == null or not hero.is_hero() or hero.escort or not state.can_act():
		return false
	if not state.traps.has(cell) or not state.traps[cell].known:
		return false
	if not Combat.is_orthogonal_neighbor(hero.pos, cell) or state.board.is_wall(hero.pos, cell):
		return false
	return hero.def_id == "dwarf" or hero.has_equipment("tool_kit")


# ---------- procurar ----------

## Revela as armadilhas e portas secretas da área. Lança e baú achados já
## ficam desarmados; fosso e bloco viram marcadores conhecidos.
static func search_traps(state: GameState) -> Dictionary:
	if not can_search(state):
		return {}
	var hero := state.active
	state.spend_action()
	var area := {}
	for cell in search_area(state, hero.pos):
		area[cell] = true
	var found: Array[Dictionary] = []
	for cell: Vector2i in state.traps.keys():
		var trap: Dictionary = state.traps[cell]
		if not area.has(cell) or trap.known:
			continue
		var disarmed: bool = trap.id in ["spear", "chest"]
		if disarmed:
			state.traps.erase(cell)
		else:
			trap.known = true
		found.append({"id": trap.id, "cell": cell, "disarmed": disarmed})
	var doors: Array = []
	for key: Vector4i in state.board.doors:
		var door: Dictionary = state.board.doors[key]
		var a := Vector2i(key.x, key.y)
		var b := Vector2i(key.z, key.w)
		if door.secret and (area.has(a) or area.has(b)):
			door.secret = false
			door.open = true
			doors.append([a, b])
	var ev := {"type": "search_traps", "unit": hero, "traps": found, "doors": doors}
	ev.merge(state.update_visibility())
	return ev


## Cada herói procura tesouro uma vez por sala. Baú com armadilha não achada
## dispara antes; depois vem o tesouro da quest ou uma carta do baralho.
static func search_treasure(state: GameState) -> Dictionary:
	if not can_search_treasure(state):
		return {}
	var hero := state.active
	state.spend_action()
	state.searched_treasure[_treasure_key(state, hero)] = true
	var zone := state.board.zone_at(hero.pos)
	var ev := {"type": "search_treasure", "unit": hero}

	for cell: Vector2i in state.traps.keys():
		var trap: Dictionary = state.traps[cell]
		if trap.id == "chest" and not trap.known and state.board.zone_at(cell) == zone:
			state.traps.erase(cell)
			var damage := int(trap.get("damage", 1))
			hero.take_damage(damage)
			ev["chest_trap"] = {"cell": cell, "damage": damage, "text": trap.get("text", "")}
			ev.merge(state.after_damage(hero))
			if not hero.is_alive():
				ev["killed"] = true
				return ev
			break

	var quest_items: Array = state.treasures.get(zone, [])
	if not quest_items.is_empty():
		var found: Dictionary = quest_items.pop_front()
		ev["card"] = {"id": "quest", "name": found.get("name", "Tesouro"), "text": found.get("text", "")}
		var gold := int(found.get("gold", 0))
		hero.gold += gold
		ev["gold"] = gold
		if found.get("objective_item", false):
			state.objective_found = true
			ev["objective"] = true
		for card: Dictionary in found.get("items", []):
			hero.inventory.append(card)
		if found.has("artifact"):
			var artifact := GameData.item(found.artifact)
			var gear := hero.equipment.duplicate()
			gear.append(artifact)
			hero.apply_equipment(gear)
			ev["artifact"] = artifact
		return ev

	if state.treasure_deck.is_empty():
		ev["card"] = {"id": "nothing", "name": "Nada"}
		return ev
	var card: Dictionary = state.treasure_deck.pop_front()
	ev["card"] = card
	ev.merge(_resolve_card(state, hero, card))
	return ev


## Aplica a carta comprada. Poções e itens ficam com o herói (voltam ao fundo
## do baralho quando usados); o resto volta ao fundo na hora.
static func _resolve_card(state: GameState, hero: Unit, card: Dictionary) -> Dictionary:
	var out := {}
	var keep := false
	if card.has("gold"):
		out["gold"] = int(card.gold)
	elif card.has("gold_roll"):
		out["gold"] = roll_spec(state, card.gold_roll)
	elif card.has("potion") or card.has("item"):
		hero.inventory.append(card)
		keep = true
	elif card.has("trap"):
		var damage := int(card.trap.get("damage", 1))
		hero.take_damage(damage)
		out["trap_damage"] = damage
		if card.trap.get("place_pit", false):
			state.traps[hero.pos] = {"id": "pit", "known": true}
			hero.in_pit = true
			out["pit"] = hero.pos
		out.merge(state.after_damage(hero))
		out["killed"] = not hero.is_alive()
	elif card.get("wandering_monster", false):
		out["wandering"] = spawn_wandering(state, hero)
	hero.gold += int(out.get("gold", 0))
	if not keep:
		state.treasure_deck.append(card)
	return out


## O monstro errante da quest surge colado no herói e ataca na hora.
## {} se não há quadrado livre na sala/corredor.
static func spawn_wandering(state: GameState, hero: Unit) -> Dictionary:
	var cell := _free_neighbor(state, hero.pos)
	if cell == Vector2i(-1, -1):
		for c in search_area(state, hero.pos):
			if state.board.is_walkable(c) and not state.is_occupied(c) and not state.is_known_pit(c):
				cell = c
				break
	if cell == Vector2i(-1, -1):
		return {}
	var monster := GameData.new_monster(state.wandering_monster)
	monster.alerted = true
	state.add_unit(monster, cell)
	state.revealed[cell] = true
	return {"monster": monster, "attack": state.strike(monster, hero)}


# ---------- armadilhas ----------

## Herói pisou numa armadilha escondida em `cell` (vindo de `came_from`).
static func spring_trap(state: GameState, hero: Unit, cell: Vector2i, came_from: Vector2i) -> Dictionary:
	var trap: Dictionary = state.traps[cell]
	var ev := {"id": trap.id, "cell": cell, "damage": 0, "faces": [] as Array[String]}
	match trap.id:
		"pit":
			trap.known = true
			ev.damage = 1
			hero.in_pit = true
		"spear":
			ev.faces = state.dice.roll_combat(1)
			ev.damage = Dice.count_face(ev.faces, Dice.SKULL)
			state.traps.erase(cell)
		"falling_block":
			# O teto desaba no quadrado: o herói recua e ali vira parede.
			ev.faces = state.dice.roll_combat(3)
			ev.damage = Dice.count_face(ev.faces, Dice.SKULL)
			state.traps.erase(cell)
			var dest := came_from if not state.is_occupied(came_from) else _free_neighbor(state, cell)
			if dest != Vector2i(-1, -1):
				hero.pos = dest
				state.board.blocked[cell] = true
				ev["pushed_to"] = dest
		_:
			ev.damage = int(trap.get("damage", 1))
			state.traps.erase(cell)
	hero.take_damage(ev.damage)
	ev.merge(state.after_damage(hero))
	ev["killed"] = not hero.is_alive()
	return ev


## Anão desarma sempre; com Kit de Ferramentas rola 1 dado: escudo desarma,
## caveira dispara (1 de dano) e a armadilha continua lá.
static func disarm(state: GameState, cell: Vector2i) -> Dictionary:
	if not can_disarm(state, cell):
		return {}
	var hero := state.active
	state.spend_action()
	var trap: Dictionary = state.traps[cell]
	var ev := {"type": "disarm", "unit": hero, "cell": cell, "id": trap.id, "faces": [] as Array[String], "damage": 0}
	var success := true
	if hero.def_id != "dwarf":
		ev.faces = state.dice.roll_combat(1)
		success = ev.faces[0] != Dice.SKULL
	ev["success"] = success
	if success:
		state.traps.erase(cell)
	else:
		ev.damage = 1
		hero.take_damage(1)
		ev.merge(state.after_damage(hero))
	ev["killed"] = not hero.is_alive()
	return ev


# ---------- itens ----------

## Poções são livres (fora do turno de ação); Água Benta gasta a ação e
## destrói um morto-vivo colado no herói.
static func use_item(state: GameState, index: int) -> Dictionary:
	var hero := state.active
	if hero == null or not hero.is_hero() or hero.escort or index < 0 or index >= hero.inventory.size():
		return {}
	var card: Dictionary = hero.inventory[index]
	var ev := {"type": "item_used", "unit": hero, "card": card}
	if card.has("item"):
		var target := _adjacent_with_tag(state, hero, card.item.get("kill_adjacent_tag", ""))
		if target == null or not state.can_act():
			return {}
		state.spend_action()
		target.body = 0
		ev["destroyed"] = target
	else:
		var potion: Dictionary = card.potion
		if potion.has("heal"):
			ev["healed"] = hero.heal(heal_amount(state, potion.heal))
		if potion.has("next_attack_bonus_dice"):
			hero.add_buff("attack", int(potion.next_attack_bonus_dice))
		if potion.has("next_defend_bonus_dice"):
			hero.add_buff("defend", int(potion.next_defend_bonus_dice))
		if potion.has("next_move_dice_mult"):
			hero.add_buff("move_mult", int(potion.next_move_dice_mult))
		if potion.has("extra_attacks"):
			hero.add_buff("extra_attacks", int(potion.extra_attacks))
	hero.inventory.remove_at(index)
	if not card.get("quest_item", false):  # item da quest não é carta do baralho
		state.treasure_deck.append(card)
	return ev


## Cura: número fixo ou "Nd6".
static func heal_amount(state: GameState, spec: Variant) -> int:
	return roll_spec(state, spec)


## "1d6", "2d6*10" ou um número.
static func roll_spec(state: GameState, spec: Variant) -> int:
	if spec is String and "d" in spec:
		var parts: PackedStringArray = spec.split("*")
		var count := int(parts[0].split("d")[0])
		var total := Dice.total(state.dice.roll_d6(maxi(1, count)))
		return total * (int(parts[1]) if parts.size() > 1 else 1)
	return int(spec)


# ---------- auxiliares ----------

static func _treasure_key(state: GameState, hero: Unit) -> String:
	return "%d:%s" % [state.board.zone_at(hero.pos), hero.def_id]


static func _free_neighbor(state: GameState, cell: Vector2i) -> Vector2i:
	for dir in Board.DIRS:
		var n := cell + dir
		if state.board.can_step(cell, n) and not state.is_occupied(n) and not state.is_known_pit(n):
			return n
	return Vector2i(-1, -1)


static func _adjacent_with_tag(state: GameState, hero: Unit, tag: String) -> Unit:
	for monster in state.alive(Unit.Side.MONSTER):
		if monster.has_tag(tag) and Combat.is_orthogonal_neighbor(hero.pos, monster.pos) \
				and not state.board.is_wall(hero.pos, monster.pos):
			return monster
	return null
