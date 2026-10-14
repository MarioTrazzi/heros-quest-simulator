extends Node
## Dados do jogo (data/*.json): heróis, monstros, armeria, feitiços, tesouro,
## artefatos, móveis e a planta do tabuleiro. Somente leitura.
##
## Atenção: o JSON do Godot lê todo número como float — use int() ao indexar.

const DATA_DIR := "res://data/"

var _cache: Dictionary = {}


## Um arquivo inteiro, ex.: module("monsters")["monsters"].
func module(name: String) -> Dictionary:
	if not _cache.has(name):
		var path := DATA_DIR + name + ".json"
		var text := FileAccess.get_file_as_string(path)
		assert(text != "", "GameData: não achei %s" % path)
		_cache[name] = JSON.parse_string(text)
	return _cache[name]


func hero(id: String) -> Dictionary:
	return _find(module("heroes").heroes, id)


func monster(id: String) -> Dictionary:
	return _find(module("monsters").monsters, id)


## Equipamento da armeria ou artefato.
func item(id: String) -> Dictionary:
	var found := _find(module("equipment").items, id)
	return found if not found.is_empty() else _find(module("artifacts").artifacts, id)


func spell(id: String) -> Dictionary:
	var s: Dictionary = module("spells")
	var found := _find(s.hero_spells, id)
	return found if not found.is_empty() else _find(s.chaos_spells, id)


func furniture(id: String) -> Dictionary:
	return _find(module("furniture").furniture, id)


## Quest de data/quests/<id>.json.
func quest(id: String) -> Dictionary:
	return module("quests/" + id)


## Tabuleiro novo (sem portas nem móveis — quem monta é a quest).
func new_board() -> Board:
	return Board.from_data(module("board"))


## Herói com o equipamento inicial já aplicado.
func new_hero(id: String) -> Unit:
	var def := hero(id)
	var unit := Unit.from_hero(def)
	unit.apply_equipment(def.start_equipment.map(item))
	return unit


func new_monster(id: String) -> Unit:
	return Unit.from_monster(monster(id))


func _find(list: Array, id: String) -> Dictionary:
	for entry: Dictionary in list:
		if entry.id == id:
			return entry
	return {}
