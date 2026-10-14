class_name ZargonAI
extends RefCounted
## IA simples de Zargon, monstro a monstro (só os alertados agem):
## 1. Se já alcança um herói, ataca sem sair do lugar.
## 2. Senão, procura um quadrado ao alcance do movimento de onde dá para
##    atacar; anda até ele e ataca.
## 3. Senão, anda o máximo possível pelo caminho mais curto até o herói mais
##    próximo (monstros não abrem portas; se não há caminho, fica parado).
## Alvo preferido: menos Corpo, depois menos Defesa (os mais fáceis de matar).
## Antes de tudo: monstro dormindo/sob Tempestade pode perder o turno, e
## conjurador (Chaos Warlock) lança um feitiço se tiver herói à vista.
##
## As ações passam pelo GameState como as dos heróis; a função devolve os
## eventos na ordem, para a apresentação animar.

## Limite da busca "até o herói mais próximo" (o tabuleiro tem 494 quadrados).
const SEARCH_STEPS := 200


static func take_turn(state: GameState, monster: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not monster.is_alive() or not monster.alerted:
		return events
	var lost := state.lose_turn(monster)
	if not lost.is_empty():
		lost["type"] = "turn_lost"
		events.append(lost)
		return events
	state.begin_turn(monster)

	var spell := _pick_spell(state, monster)
	if not spell.is_empty():
		state.spend_action()
		events.append(Magic.cast_as(state, monster, spell.id, spell.target))
		return events

	var target := _best_target(_heroes_hittable_from(state, monster.pos))
	if target != null:
		events.append(state.attack(target))
		return events

	var flooded := state.flood_for(monster, state.move_left)
	var best_cell := Vector2i(-1, -1)
	var best_key: Array = []
	for cell in Pathfinder.destinations(flooded):
		var hero := _best_target(_heroes_hittable_from(state, cell))
		if hero == null:
			continue
		var key := [hero.body, hero.defend, flooded[cell].dist]
		if best_key.is_empty() or _less(key, best_key):
			best_key = key
			best_cell = cell
	if best_cell != Vector2i(-1, -1):
		events.append(state.move_active(best_cell))
		var victim := _best_target(_heroes_hittable_from(state, monster.pos))
		events.append(state.attack(victim))
		return events

	var step := _approach_cell(state, monster)
	if step != monster.pos:
		events.append(state.move_active(step))
	return events


## Ordem de preferência:
## 1. Tempestade de Fogo / Nuvem do Caos com 2+ heróis na área;
## 2. Bola de Fogo no herói mais fraco;
## 3. Invocar, se há herói à vista e nenhum colado;
## 4. Comando, Sono e Tempestade no herói que bate mais forte.
## {"id", "target"} ou {}.
static func _pick_spell(state: GameState, monster: Unit) -> Dictionary:
	if monster.spells.is_empty():
		return {}
	var crowd := Magic.heroes_in_area(state, monster).size()
	for id: String in ["c_firestorm", "c_cloud_of_chaos"]:
		if monster.spells.has(id) and crowd >= 2:
			return {"id": id, "target": monster}
	var visible: Array[Unit] = []
	for hero in state.alive(Unit.Side.HERO):
		if state.can_see(monster.pos, hero.pos):
			visible.append(hero)
	if visible.is_empty():
		return {}
	var spell := _pick_targeted(state, monster, "c_ball_of_flame", false)
	if not spell.is_empty():
		return spell
	if _heroes_hittable_from(state, monster.pos).is_empty():
		for id: String in ["c_summon_undead", "c_summon_orcs"]:
			if monster.spells.has(id):
				return {"id": id, "target": monster}
	for id: String in ["c_command", "c_sleep", "c_tempest"]:
		spell = _pick_targeted(state, monster, id, true)
		if not spell.is_empty():
			return spell
	return {}


## Alvo do feitiço: o mais fraco, ou (strongest) o que bate mais forte.
static func _pick_targeted(state: GameState, monster: Unit, id: String, strongest: bool) -> Dictionary:
	if not monster.spells.has(id):
		return {}
	var heroes: Array[Unit] = []
	for t: Variant in Magic.targets(state, monster, id):
		if t is Unit and t.is_hero():
			heroes.append(t)
	if heroes.is_empty():
		return {}
	var pick: Unit = _best_target(heroes)
	if strongest:
		for h in heroes:
			if h.attack > pick.attack:
				pick = h
	return {"id": id, "target": pick}


## Heróis que o monstro acertaria parado em `cell` (corpo a corpo ortogonal).
static func _heroes_hittable_from(state: GameState, cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	for hero in state.alive(Unit.Side.HERO):
		if Combat.is_orthogonal_neighbor(cell, hero.pos) and not state.board.is_wall(cell, hero.pos):
			out.append(hero)
	return out


static func _best_target(heroes: Array[Unit]) -> Unit:
	var best: Unit = null
	for hero in heroes:
		if best == null or _less([hero.body, hero.defend], [best.body, best.defend]):
			best = hero
	return best


## Quadrado mais avançado, dentro do movimento, no caminho até o herói mais perto.
static func _approach_cell(state: GameState, monster: Unit) -> Vector2i:
	var far := state.flood_for(monster, SEARCH_STEPS)
	var goal := Vector2i(-1, -1)
	for cell: Vector2i in far:
		if not far[cell].stop or _heroes_hittable_from(state, cell).is_empty():
			continue
		if goal == Vector2i(-1, -1) or far[cell].dist < far[goal].dist:
			goal = cell
	if goal == Vector2i(-1, -1):
		return monster.pos
	var path := Pathfinder.path_to(far, goal)
	for i in range(mini(state.move_left, path.size()) - 1, -1, -1):
		if far[path[i]].stop:
			return path[i]
	return monster.pos


## Comparação lexicográfica de listas de números.
static func _less(a: Array, b: Array) -> bool:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()
