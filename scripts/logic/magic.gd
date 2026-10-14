class_name Magic
extends RefCounted
## Magia: escolha das escolas, alvos válidos e o efeito de cada feitiço.
##
## - Escolas (Ar, Fogo, Água, Terra; 3 feitiços cada): o Mago escolhe uma,
##   o Elfo outra, e o Mago fica com as duas que sobraram (9 × 3).
## - Lançar é a ação do turno; cada feitiço vale uma vez por quest.
## - O alvo precisa estar à vista (linha de visão; mesma sala sempre vale).
##   O conjurador sempre pode mirar em si mesmo.
## - Sono não pega em morto-vivo (Mente 0 nunca acordaria).
## Os feitiços do Caos usam as mesmas regras, com heróis como alvo, e mais:
## - Tempestade de Fogo: 3 de dano em todos na área do conjurador (menos ele).
## - Nuvem do Caos: paralisa os heróis da área (como o Sono: 6 em 1d6 por Mente solta).
## - Comando: o herói perde os turnos até tirar um 6 (simplificação: Zargon não
##   o controla), mas ainda se defende.
## - Invocar Orcs/Mortos-vivos: 1d6 → 1-2: 2, 3-5: 3, 6: 4 monstros em volta (provisório).
## "Área" = a sala do conjurador, ou o trecho de corredor que ele vê.

const SUMMON_TABLE := [2, 2, 3, 3, 3, 4]

const SCHOOLS: Array[String] = ["air", "fire", "water", "earth"]


static func school_spells(school: String) -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in GameData.module("spells").hero_spells:
		if s.school == school:
			out.append(s.id)
	return out


## Distribui as escolas. Sem Mago ou sem Elfo na quest, quem estiver leva o que der.
static func assign_schools(state: GameState, wizard_school: String, elf_school: String) -> void:
	assert(wizard_school != elf_school, "Mago e Elfo precisam de escolas diferentes")
	var wizard := _hero(state, "wizard")
	var elf := _hero(state, "elf")
	if elf != null:
		elf.spells = school_spells(elf_school)
	if wizard != null:
		wizard.spells.clear()
		for school in SCHOOLS:
			if school != elf_school or elf == null:
				wizard.spells.append_array(school_spells(school))


static func needs_school_choice(state: GameState) -> bool:
	return _hero(state, "wizard") != null or _hero(state, "elf") != null


# ---------- alvos ----------

## Unidades (e, para o Gênio, portas [a, b]) em que o feitiço pode ser lançado.
## need_sight = false ignora a linha de visão (monstro ainda na névoa continua de fora).
static func targets(state: GameState, caster: Unit, spell_id: String, need_sight := true) -> Array:
	var spell := GameData.spell(spell_id)
	var out: Array = []
	if spell.is_empty() or not caster.spells.has(spell_id):
		return out
	for unit in state.units:
		if not unit.is_alive() or unit.escaped:
			continue
		if not (_visible(state, caster, unit) if need_sight else unit.is_hero() or state.revealed.has(unit.pos)):
			continue
		match spell.target:
			"hero":
				if unit.is_hero() and _affects(spell, unit):
					out.append(unit)
			"monster":
				if not unit.is_hero() and _affects(spell, unit):
					out.append(unit)
			"any_visible":
				if unit.side != caster.side and not unit.has_tag("spell_immune"):
					out.append(unit)
	if spell.target == "any_visible":
		out.append_array(_visible_doors(state, caster))
	elif spell.target == "self":
		out.append(caster)
	elif spell.target == "room" and not heroes_in_area(state, caster).is_empty():
		out.append(caster)
	return out


## Heróis na área do conjurador (sala dele, ou o corredor que ele vê).
static func heroes_in_area(state: GameState, caster: Unit) -> Array[Unit]:
	var area := {}
	for cell in Exploration.search_area(state, caster.pos):
		area[cell] = true
	var out: Array[Unit] = []
	for hero in state.alive(Unit.Side.HERO):
		if area.has(hero.pos):
			out.append(hero)
	return out


## Figuras que o feitiço afetaria, mas que o conjurador não vê (a tela marca de vermelho).
static func out_of_sight(state: GameState, caster: Unit, spell_id: String) -> Array:
	var seen := targets(state, caster, spell_id)
	return targets(state, caster, spell_id, false).filter(
		func(t: Variant) -> bool: return t is Unit and not seen.has(t))


static func can_cast(state: GameState, caster: Unit, spell_id: String, target: Variant) -> bool:
	return targets(state, caster, spell_id).has(target)


## Lança no turno do herói ativo (gasta a ação).
static func cast(state: GameState, spell_id: String, target: Variant) -> Dictionary:
	var caster := state.active
	if caster == null or not state.can_act() or not can_cast(state, caster, spell_id, target):
		return {}
	state.spend_action()
	return cast_as(state, caster, spell_id, target)


## Aplica o feitiço (sem checar turno; a IA de Zargon usa direto).
static func cast_as(state: GameState, caster: Unit, spell_id: String, target: Variant) -> Dictionary:
	var spell := GameData.spell(spell_id)
	var effect: Dictionary = spell.effect
	caster.spells.erase(spell_id)
	var ev := {"type": "spell", "caster": caster, "spell": spell, "target": target}

	if target is Array:
		# Gênio abre a porta e mostra o que há atrás.
		state.board.open_door(target[0], target[1])
		ev["door"] = target
		ev.merge(state.update_visibility())
		return ev
	var unit: Unit = target
	if spell.target == "room":
		_cast_on_area(state, caster, effect, ev)
		return ev
	if effect.has("summon"):
		ev["summoned"] = _summon(state, caster, effect.summon)
		return ev
	if spell_id == "genie":
		var genie := Unit.new()
		genie.name = "Gênio"
		genie.side = caster.side
		genie.attack = int(effect.choice[1].attack_dice)
		genie.pos = caster.pos
		ev["attack"] = state.strike(genie, unit)
	elif effect.has("damage"):
		var damage := int(effect.damage)
		var rolls: Array[int] = []
		if effect.has("resist_roll"):
			rolls = state.dice.roll_d6(int(effect.resist_roll.dice))
			damage -= rolls.filter(func(v: int) -> bool: return v >= 5).size()
		damage = maxi(0, damage)
		unit.take_damage(damage)
		if damage > 0:
			unit.status.erase("rock_skin")
		ev["resist"] = rolls
		ev["damage"] = damage
		ev.merge(state.after_damage(unit, caster))
		ev["killed"] = not unit.is_alive()
	elif effect.has("heal"):
		ev["healed"] = unit.heal(int(effect.heal))
	elif effect.has("skip_turns"):
		unit.status["skip_turns"] = int(unit.status.get("skip_turns", 0)) + int(effect.skip_turns)
	elif effect.get("status") == "asleep":
		unit.status["asleep"] = true
	elif effect.get("status") == "controlled":
		unit.status["commanded"] = true
	elif effect.has("next_move_dice_mult"):
		unit.add_buff("move_mult", int(effect.next_move_dice_mult))
	elif effect.has("next_attack_bonus_dice"):
		unit.add_buff("attack", int(effect.next_attack_bonus_dice))
	elif effect.get("next_move_pass_monsters", false):
		unit.add_buff("pass_monsters", 1)
	elif effect.get("next_move_through_walls", false):
		unit.add_buff("through_walls", 1)
	elif effect.has("defend_bonus_dice"):
		unit.status["rock_skin"] = true
	return ev


# ---------- feitiços de área e invocação ----------

## Tempestade de Fogo (dano em todos da área, menos o conjurador) ou Nuvem do
## Caos (paralisa os heróis). ev["hits"] = [{"unit", "damage", ...}].
static func _cast_on_area(state: GameState, caster: Unit, effect: Dictionary, ev: Dictionary) -> void:
	var hits: Array[Dictionary] = []
	if effect.has("damage"):
		var area := {}
		for cell in Exploration.search_area(state, caster.pos):
			area[cell] = true
		for unit in state.units:
			if unit == caster or not unit.is_alive() or unit.escaped or not area.has(unit.pos):
				continue
			var damage := int(effect.damage)
			unit.take_damage(damage)
			unit.status.erase("rock_skin")
			var hit := {"unit": unit, "damage": damage}
			hit.merge(state.after_damage(unit, caster))
			hit["killed"] = not unit.is_alive()
			hits.append(hit)
	else:
		for hero in heroes_in_area(state, caster):
			hero.status["asleep"] = true
			hero.status["paralyzed"] = true
			hits.append({"unit": hero, "damage": 0})
	ev["hits"] = hits


## Monstros invocados nos quadrados livres mais perto do conjurador.
static func _summon(state: GameState, caster: Unit, kind: String) -> Array[Unit]:
	var count: int = SUMMON_TABLE[state.dice.d6() - 1]
	var ids: Array[String] = ["skeleton", "zombie"]
	if kind == "orc":
		ids = ["orc"]
	var near := Pathfinder.flood(state.board, caster.pos, 6, func(_c: Vector2i) -> int: return Pathfinder.PASS_ONLY)
	var cells: Array = near.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return near[a].dist < near[b].dist)
	var out: Array[Unit] = []
	for cell: Vector2i in cells:
		if out.size() >= count:
			break
		if cell == caster.pos or state.is_occupied(cell) or state.is_known_pit(cell) or not state.board.is_walkable(cell):
			continue
		var monster := GameData.new_monster(ids[out.size() % ids.size()])
		monster.alerted = true
		state.add_unit(monster, cell)
		state.revealed[cell] = true
		out.append(monster)
	return out


# ---------- auxiliares ----------

static func _visible(state: GameState, caster: Unit, unit: Unit) -> bool:
	if unit == caster:
		return true
	if not unit.is_hero() and not state.revealed.has(unit.pos):
		return false
	return state.can_see(caster.pos, unit.pos)


static func _affects(spell: Dictionary, unit: Unit) -> bool:
	if unit.has_tag("spell_immune"):
		return false
	if spell.effect.get("status") == "asleep":
		return unit.mind > 0 and not unit.has_tag("undead") and not unit.status.get("asleep", false)
	if spell.effect.get("status") == "controlled":
		return not unit.status.get("commanded", false) and not unit.status.get("asleep", false)
	return true


## Portas fechadas cujo lado de cá o conjurador enxerga.
static func _visible_doors(state: GameState, caster: Unit) -> Array:
	var out: Array = []
	for key: Vector4i in state.board.doors:
		var door: Dictionary = state.board.doors[key]
		if door.open or door.secret or door.get("fake", false):
			continue
		var a := Vector2i(key.x, key.y)
		var b := Vector2i(key.z, key.w)
		for side: Vector2i in [a, b]:
			if state.revealed.has(side) and (side == caster.pos or LineOfSight.can_see(state.board, caster.pos, side, state.is_occupied)):
				out.append([a, b])
				break
	return out


static func _hero(state: GameState, id: String) -> Unit:
	for unit in state.alive(Unit.Side.HERO):
		if unit.def_id == id:
			return unit
	return null
