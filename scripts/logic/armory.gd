class_name Armory
extends RefCounted
## Armeria entre quests: compra com o ouro do herói (registro da Campanha).
## Uma peça da armeria por espaço (arma, corpo, cabeça, escudo, braços, manto,
## ferramenta): comprar outra do mesmo espaço substitui a antiga, sem devolver
## ouro. Artefatos achados em quests nunca são substituídos.
## Mago: só o que tem wizard_ok (e o Manto, que é só dele). Escudo não combina
## com arma de duas mãos.


static func items() -> Array:
	return GameData.module("equipment").items


## Motivo para não poder comprar, ou "" se pode.
static func why_not(rec: Dictionary, item: Dictionary) -> String:
	var owned: Array = rec.equipment
	if owned.has(item.id):
		return "Já tem"
	if item.get("wizard_only", false) and rec.id != "wizard":
		return "Só o Mago"
	if rec.id == "wizard" and not item.get("wizard_ok", false) and not item.get("wizard_only", false):
		return "O Mago não pode usar"
	var gear: Array = owned.map(GameData.item)
	if item.slot == "shield" and gear.any(func(g: Dictionary) -> bool: return g.get("two_handed", false)):
		return "Arma de duas mãos não deixa usar escudo"
	if item.get("two_handed", false) and gear.any(func(g: Dictionary) -> bool: return g.get("slot") == "shield"):
		return "O escudo não deixa usar arma de duas mãos"
	if int(rec.gold) < int(item.price):
		return "Ouro insuficiente"
	return ""


## Compra; devolve o motivo da recusa ou "".
static func buy(rec: Dictionary, item_id: String) -> String:
	var item := GameData.item(item_id)
	if item.is_empty():
		return "Item desconhecido"
	var reason := why_not(rec, item)
	if reason != "":
		return reason
	rec.gold = int(rec.gold) - int(item.price)
	var kept: Array = []
	for id: String in rec.equipment:
		if GameData.item(id).get("slot") != item.slot or not _is_armory_item(id):
			kept.append(id)
	kept.append(item_id)
	rec.equipment = kept
	return ""


static func _is_armory_item(id: String) -> bool:
	return items().any(func(it: Dictionary) -> bool: return it.id == id)
