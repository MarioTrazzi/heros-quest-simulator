class_name QuestLoader
extends RefCounted
## Monta a partida a partir de uma quest (data/quests/*.json; formato em
## docs/02-arquitetura-godot.md §5). Coordenadas base 0.
##
## Móvel: "rot" 0/2 usa o tamanho do furniture.json, 1/3 gira 90° (troca L×A).
## Armadilha: {"type": "trap", "id": "pit"|"spear"|"falling_block"|"chest", "pos", "damage"?, "text"?}
## (o baú com armadilha fica no quadrado do baú e só dispara ao procurar tesouro).
## Tesouro da quest: {"type": "treasure", "pos" (qualquer quadrado da sala), "gold"?, "name"?, "text"?,
## "objective_item"?}. Monstro com "objective": true é alvo do objetivo "kill".
##
## Quest com "heroscribe": caminho de um XML do HeroScribe; o mapa vem de lá e
## a quest só acrescenta o que o livro diz: "objective", "wandering_monster",
## "letters" ({"A": {"treasure": {...}} | {"monster": {override}, "objective"?} |
## {"carries": {item}} (o monstro da letra leva o item; quem o mata fica com ele) |
## {"awaken": {"id", "at_letter"?, "override"?, "objective"?, "text"?}} (surge quando
## um herói entra na sala) | {"captive": {aliado}} (prisioneiro do objetivo "escort",
## ver GameState.captive) | {"fake_door": true}}, com "at": [x, y] quando o mapa
## não tem a letra) e "objects" extras.

const HERO_ORDER: Array[String] = ["barbarian", "dwarf", "elf", "wizard"]


## `heroes`: unidades da campanha (na ordem dos turnos); vazio = heróis novos.
static func build(source: Dictionary, seed_value := 0, heroes_in: Array[Unit] = []) -> GameState:
	var quest := expand(source)
	var state := GameState.new(GameData.new_board(), seed_value)
	state.quest = quest
	state.wandering_monster = quest.get("wandering_monster", "orc")
	state.objective = quest.get("objective", {"type": "escape"})
	var board := state.board
	for obj: Dictionary in quest.get("objects", []):
		match obj.type:
			"door":
				board.add_door(cell(obj.a), cell(obj.b), obj.get("open", false), false, obj.get("fake", false))
			"dark":
				board.dark[cell(obj.pos)] = true
			"secret_door":
				board.add_door(cell(obj.a), cell(obj.b), false, true)
			"blocked":
				board.blocked[cell(obj.pos)] = true
			"furniture":
				_place_furniture(state, obj)
			"trap":
				var trap: Dictionary = obj.duplicate()
				trap.erase("type")
				trap.erase("pos")
				trap["known"] = false
				state.traps[cell(obj.pos)] = trap
			"treasure":
				var zone := board.zone_at(cell(obj.pos))
				if not state.treasures.has(zone):
					state.treasures[zone] = []
				state.treasures[zone].append(obj)
			"monster":
				pass # depois dos móveis, para o assert de quadrado livre valer
			"captive":
				var spec: Dictionary = obj.duplicate()
				spec.erase("type")
				spec["pos"] = cell(obj.pos)
				state.captive = spec
			"ambush":
				var ambush: Dictionary = obj.duplicate()
				ambush.erase("type")
				ambush["zone"] = board.zone_at(cell(obj.pos))
				ambush["pos"] = cell(obj.spawn)
				state.ambushes.append(ambush)
			_:
				push_warning("QuestLoader: objeto desconhecido %s" % obj.type)
	for obj: Dictionary in quest.get("objects", []):
		if obj.type == "monster":
			var monster := GameData.new_monster(obj.id)
			for key: String in obj.get("override", {}):
				apply_override(monster, key, obj.override[key])
			monster.is_objective = obj.get("objective", false)
			monster.carries = obj.get("carries", {})
			state.add_unit(monster, cell(obj.pos))
	var starts: Array = quest.start
	var heroes: Array = heroes_in if not heroes_in.is_empty() else quest.get("heroes", HERO_ORDER).map(GameData.new_hero)
	assert(starts.size() >= heroes.size(), "quest sem quadrados de início suficientes")
	for i in heroes.size():
		state.add_unit(heroes[i], cell(starts[i]))
	for card: Dictionary in GameData.module("treasure_deck").cards:
		for i in int(card.count):
			state.treasure_deck.append(card)
	state.dice.shuffle(state.treasure_deck)
	return state


## Quest com mapa do HeroScribe: importa e aplica as notas por letra.
static func expand(quest: Dictionary) -> Dictionary:
	if not quest.has("heroscribe"):
		return quest
	var imported := HeroScribeImporter.parse(quest.heroscribe)
	assert(not imported.is_empty(), "não consegui ler %s" % quest.heroscribe)
	if not imported.skipped.is_empty():
		push_warning("HeroScribe: peças ignoradas %s" % [imported.skipped])
	for warning: String in imported.warnings:
		push_warning("HeroScribe: " + warning)
	var full := quest.duplicate()
	var objects: Array = imported.objects.duplicate(true)
	var letters: Dictionary = quest.get("letters", {})
	for letter: String in letters:
		var spec: Dictionary = letters[letter]
		# "at" (base 0) vale para quem não tem letra no mapa (ex.: o chefe de The Trial).
		var cells: Array = [spec.at] if spec.has("at") else imported.letters.get(letter, [])
		if cells.is_empty():
			push_warning("HeroScribe: letra %s não está no mapa" % letter)
		for at: Array in cells:
			var spot := cell(at)
			if spec.has("captive"):
				var captive: Dictionary = spec.captive.duplicate()
				captive["type"] = "captive"
				captive["pos"] = at
				objects.append(captive)
			if spec.has("awaken"):
				# Monstro que surge quando um herói entra na sala desta letra;
				# "at_letter" diz onde ele aparece (senão, no próprio quadrado).
				var awaken: Dictionary = spec.awaken.duplicate()
				var spawn: Array = imported.letters.get(awaken.get("at_letter", ""), [at])[0]
				awaken.erase("at_letter")
				awaken["type"] = "ambush"
				awaken["pos"] = at
				awaken["spawn"] = spawn
				objects.append(awaken)
			if spec.has("treasure"):
				var treasure: Dictionary = spec.treasure.duplicate()
				treasure["type"] = "treasure"
				treasure["pos"] = at
				objects.append(treasure)
			for obj: Dictionary in objects:
				if spec.get("fake_door", false) and obj.type == "door" \
						and (cell(obj.a) == spot or cell(obj.b) == spot):
					obj["fake"] = true
				if (spec.has("monster") or spec.has("carries")) and obj.type == "monster" and _near(cell(obj.pos), spot):
					obj["override"] = spec.get("monster", {})
					obj["objective"] = spec.get("objective", false)
					if spec.has("carries"):
						obj["carries"] = spec.carries
	objects.append_array(quest.get("objects", []))
	full.objects = objects
	if not full.has("start"):
		full.start = imported.start
	if not full.has("name"):
		full.name = imported.name
	if not full.has("intro"):
		full.intro = imported.speech
	return full


## Letra no quadrado do monstro ou colada nele.
static func _near(a: Vector2i, b: Vector2i) -> bool:
	return a == b or Combat.is_orthogonal_neighbor(a, b)


static func cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


static func _place_furniture(state: GameState, obj: Dictionary) -> void:
	var def := GameData.furniture(obj.id)
	assert(not def.is_empty(), "móvel desconhecido: %s" % obj.id)
	var rot := int(obj.get("rot", 0))
	var size := Vector2i(int(def.size[0]), int(def.size[1]))
	if rot % 2 == 1:
		size = Vector2i(size.y, size.x)
	var pos := cell(obj.pos)
	if def.blocks_move:
		state.board.place_furniture(obj.id, pos, size)
	elif obj.id == "stairway":
		for dy in size.y:
			for dx in size.x:
				state.stairway.append(pos + Vector2i(dx, dy))
	state.furniture.append({"id": obj.id, "pos": pos, "size": size, "rot": rot})


## Chefes nomeados reaproveitam a miniatura com stats próprios.
static func apply_override(unit: Unit, key: String, value: Variant) -> void:
	match key:
		"name":
			unit.name = value
		"body":
			unit.body = int(value)
			unit.body_max = unit.body
		"mind":
			unit.mind = int(value)
			unit.mind_max = unit.mind
		"attack", "defend", "move":
			unit.set(key, int(value))
		"spells":
			unit.spells.assign(value)
		_:
			push_warning("QuestLoader: override desconhecido %s" % key)
