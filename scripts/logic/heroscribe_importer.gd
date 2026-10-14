class_name HeroScribeImporter
extends RefCounted
## Lê um mapa do HeroScribe (XML, http://www.heroscribe.org) e devolve os
## objetos no formato das nossas quests (docs/02-arquitetura-godot.md §5).
##
## Convenções do HeroScribe (conferidas nos exemplos de referencias/heroscribe):
## - Coordenadas base 1 (`left`, `top`); aqui viram base 0.
## - `rotation`: downward (padrão), leftward, upward, rightward. Girado para os
##   lados, a peça troca largura × altura e `left`/`top` é o canto da área girada.
## - Porta (1×2) atravessa a parede: em pé (down/up) liga (x, y)–(x, y+1);
##   deitada (left/right) liga (x, y)–(x+1, y).
## - Porta secreta (1×1) fica no quadrado de dentro; a parede está no lado
##   OPOSTO ao da rotação (rightward → parede à esquerda).
## - `<dark>` = área fora da quest (vira quadrado escuro intransitável).
## - Letras (LetterA…) só marcam onde vale a nota do livro; o texto não vem no XML.
## Só o primeiro tabuleiro é lido (quests de vários tabuleiros ficam de fora).
## Porta secreta que não cai numa parede (erro do mapa) tenta o lado oposto; se
## nenhum servir, é descartada e vai para "warnings".

const MONSTERS := {
	"Goblin": "goblin", "Orc": "orc", "Fimir": "fimir", "ChaosWarrior": "chaos_warrior",
	"Gargoyle": "gargoyle", "Skeleton": "skeleton", "Zombie": "zombie", "Mummy": "mummy",
}
const FURNITURE := {
	"Table": "table", "SorcerersTable": "sorcerers_table", "AlchemistsBench": "alchemists_bench",
	"Tomb": "tomb", "Rack": "rack", "Bookcase": "bookcase", "Cupboard": "cupboard",
	"Fireplace": "fireplace", "WeaponsRack": "weapons_rack", "Throne": "throne",
	"TreasureChest": "treasure_chest", "Stairway": "stairway",
}
const TRAPS := {"PitTrap": "pit", "SpearTrap": "spear", "FallingRock": "falling_block"}
const DOORS := ["Door", "OpenDoor", "DoorIn", "DoorOut", "DoubleArrowDoor", "StoneDoorway"]
const ROTATIONS := {"downward": 0, "leftward": 1, "upward": 2, "rightward": 3}


## {"name", "speech", "objects": [...], "start": [[x, y]...], "letters": {"A": [[x, y]...]},
##  "skipped": ids não suportados, "warnings": textos}. {} se o arquivo não abre.
static func parse(path: String) -> Dictionary:
	var xml := XMLParser.new()
	if xml.open(path) != OK:
		push_error("HeroScribe: não abri %s" % path)
		return {}
	var out := {"name": "", "speech": "", "objects": [], "start": [], "letters": {}, "skipped": [], "warnings": []}
	var boards := 0
	var in_speech := false
	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				if tag == "quest":
					out.name = xml.get_named_attribute_value_safe("name")
				elif tag == "board":
					boards += 1
				elif tag == "speech":
					in_speech = true
				elif boards == 1 and tag == "dark":
					_add_dark(xml, out)
				elif boards == 1 and tag == "object":
					_add_object(xml, out)
			XMLParser.NODE_TEXT:
				if in_speech:
					out.speech += xml.get_node_data().strip_edges()
			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == "speech":
					in_speech = false
	if out.start.is_empty():
		for obj: Dictionary in out.objects:
			if obj.get("id") == "stairway":
				var p: Array = obj.pos
				out.start = [[p[0], p[1]], [p[0] + 1, p[1]], [p[0], p[1] + 1], [p[0] + 1, p[1] + 1]]
				break
	return out


static func _add_dark(xml: XMLParser, out: Dictionary) -> void:
	var left := int(xml.get_named_attribute_value_safe("left")) - 1
	var top := int(xml.get_named_attribute_value_safe("top")) - 1
	var w := int(xml.get_named_attribute_value_safe("width"))
	var h := int(xml.get_named_attribute_value_safe("height"))
	for dy in maxi(1, h):
		for dx in maxi(1, w):
			out.objects.append({"type": "dark", "pos": [left + dx, top + dy]})


static func _add_object(xml: XMLParser, out: Dictionary) -> void:
	var id := xml.get_named_attribute_value_safe("id")
	var x := int(float(xml.get_named_attribute_value_safe("left"))) - 1
	var y := int(float(xml.get_named_attribute_value_safe("top"))) - 1
	var rot: int = ROTATIONS.get(xml.get_named_attribute_value_safe("rotation"), 0)
	var objects: Array = out.objects
	if MONSTERS.has(id):
		objects.append({"type": "monster", "id": MONSTERS[id], "pos": [x, y]})
	elif FURNITURE.has(id):
		objects.append({"type": "furniture", "id": FURNITURE[id], "pos": [x, y], "rot": rot})
	elif id == "TreasureChestTrap":
		objects.append({"type": "furniture", "id": "treasure_chest", "pos": [x, y], "rot": rot})
		objects.append({"type": "trap", "id": "chest", "pos": [x, y]})
	elif TRAPS.has(id):
		objects.append({"type": "trap", "id": TRAPS[id], "pos": [x, y]})
	elif id == "SingleBlockedSquare":
		objects.append({"type": "blocked", "pos": [x, y]})
	elif id == "DoubleBlockedSquare":
		objects.append({"type": "blocked", "pos": [x, y]})
		objects.append({"type": "blocked", "pos": [x, y + 1] if rot % 2 == 1 else [x + 1, y]})
	elif id in DOORS:
		var other := [x, y + 1] if rot % 2 == 0 else [x + 1, y]
		objects.append({"type": "door", "a": [x, y], "b": other, "open": id == "OpenDoor"})
	elif id == "SecretDoor" or id == "SecretDoorAlternate":
		var wall_side: Vector2i = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][rot]
		var here := Vector2i(x, y)
		var board := GameData.new_board()
		for side: Vector2i in [wall_side, -wall_side]:
			var other := here + side
			if board.in_bounds(here) and board.in_bounds(other) and board.zone_at(here) != board.zone_at(other):
				objects.append({"type": "secret_door", "a": [x, y], "b": [other.x, other.y]})
				return
		out.warnings.append("porta secreta em %s não fica numa parede" % here)
	elif id.begins_with("Letter"):
		var letter := id.substr(6)
		if not out.letters.has(letter):
			out.letters[letter] = []
		out.letters[letter].append([x, y])
	elif id in ["Barbarian", "Dwarf", "Elf", "Wizard"]:
		pass # posição sugerida de herói: usamos a escada
	elif not out.skipped.has(id):
		out.skipped.append(id)
