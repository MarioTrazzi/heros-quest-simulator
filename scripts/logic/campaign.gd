class_name Campaign
extends RefCounted
## Campanha: os heróis entre uma quest e outra, a ordem das quests e o save.
##
## Regras entre quests (UE 1989):
## - Corpo, Mente e feitiços voltam ao máximo a cada quest.
## - Quem sobrevive guarda o ouro e o equipamento (armeria e artefatos).
##   Cartas comuns de tesouro (poções) não passam para a quest seguinte.
## - Herói morto recomeça do zero (novo personagem com o equipamento inicial).
## - Ao completar 3 quests o herói vira Campeão e ganha 500 de ouro (uma vez).

const SAVE_PATH := "user://campaign.json"
const SAVE_VERSION := 2
const CHAMPION_QUESTS := 3
const CHAMPION_BONUS := 500

## {"id", "gold", "equipment": [ids], "quests_done", "champion"} na ordem dos turnos.
var heroes: Array[Dictionary] = []
var quest_order: Array[String] = []
var completed: Array[String] = []
## Quest em andamento (Match.to_dict()), gravada a cada comando; {} = nenhuma.
var in_progress: Dictionary = {}


static func create() -> Campaign:
	var c := Campaign.new()
	for id in QuestLoader.HERO_ORDER:
		c.heroes.append(fresh_hero(id))
	c.quest_order.assign(GameData.module("campaign").quests)
	return c


static func fresh_hero(id: String) -> Dictionary:
	return {"id": id, "gold": 0, "equipment": GameData.hero(id).start_equipment.duplicate(),
		"quests_done": 0, "champion": false}


func hero(id: String) -> Dictionary:
	for h in heroes:
		if h.id == id:
			return h
	return {}


## Primeira quest ainda não cumprida ("" = campanha terminada).
func next_quest() -> String:
	for id in quest_order:
		if not completed.has(id):
			return id
	return ""


## Quests cumpridas podem ser rejogadas; a próxima está liberada.
func is_unlocked(quest_id: String) -> bool:
	return completed.has(quest_id) or quest_id == next_quest()


## Unidade pronta para a quest: ficha cheia, ouro e equipamento da campanha.
func hero_unit(id: String) -> Unit:
	return unit_from_record(hero(id))


static func unit_from_record(rec: Dictionary) -> Unit:
	var unit := Unit.from_hero(GameData.hero(rec.id))
	unit.apply_equipment(rec.equipment.map(GameData.item))
	unit.gold = int(rec.gold)
	return unit


func hero_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for h in heroes:
		out.append(hero_unit(h.id))
	return out


## Anota o resultado da quest. {"result", "fallen": [nomes], "champions": [nomes]}.
func record(state: GameState, quest_id: String) -> Dictionary:
	var result := state.outcome()
	var report := {"result": result, "fallen": [], "champions": []}
	for unit in state.units:
		if not unit.is_hero():
			continue
		var index := heroes.find(hero(unit.def_id))
		if index < 0:
			continue
		if not unit.is_alive():
			heroes[index] = fresh_hero(unit.def_id)
			report.fallen.append(unit.name)
			continue
		var rec := heroes[index]
		rec.gold = unit.gold
		rec.equipment = unit.equipment.map(func(it: Dictionary) -> String: return it.id)
		if result == "victory":
			rec.quests_done = int(rec.quests_done) + 1
			if int(rec.quests_done) >= CHAMPION_QUESTS and not rec.champion:
				rec.champion = true
				rec.gold = int(rec.gold) + CHAMPION_BONUS
				report.champions.append(unit.name)
	if result == "victory" and not completed.has(quest_id):
		completed.append(quest_id)
	in_progress = {}
	return report


# ---------- save ----------

func to_dict() -> Dictionary:
	return {"version": SAVE_VERSION, "heroes": heroes, "quest_order": quest_order, "completed": completed,
		"in_progress": in_progress}


static func from_dict(data: Dictionary) -> Campaign:
	var c := Campaign.new()
	for h: Dictionary in data.get("heroes", []):
		c.heroes.append({"id": h.id, "gold": int(h.gold), "equipment": h.equipment,
			"quests_done": int(h.quests_done), "champion": bool(h.champion)})
	c.quest_order.assign(data.get("quest_order", GameData.module("campaign").quests))
	c.completed.assign(data.get("completed", []))
	var running: Variant = data.get("in_progress", {})
	c.in_progress = running if running is Dictionary else {}
	# Quests novas no jogo entram no fim da lista de um save antigo.
	for id: String in GameData.module("campaign").quests:
		if not c.quest_order.has(id):
			c.quest_order.append(id)
	return c


func save(path := SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Campanha: não consegui gravar %s" % path)
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return true


static func has_save(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## null se não há save ou ele não abre.
static func load_from(path := SAVE_PATH) -> Campaign:
	if not has_save(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Campanha: save inválido em %s" % path)
		return null
	return from_dict(data)
