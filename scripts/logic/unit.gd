class_name Unit
extends RefCounted
## Herói ou monstro em jogo. Os stats efetivos (attack/defend/move_dice)
## são recalculados por apply_equipment a partir da base da ficha.

enum Side { HERO, MONSTER }

var def_id := ""
var name := ""
var side := Side.HERO
## Vector2i(-1, -1) = fora do tabuleiro.
var pos := Vector2i(-1, -1)
var tags: Array = []

var attack := 0
var defend := 0
var body := 0
var body_max := 0
var mind := 0
var mind_max := 0
## Heróis rolam move_dice × d6; monstros andam sempre `move` quadrados.
var move := 0
var move_dice := 0
## Arma atual ataca na diagonal / é de projétil (não ataca adjacente).
var diagonal_attack := false
var ranged := false
var equipment: Array = []
## Monstro que já foi visto por um herói: só ele age no turno de Zargon.
var alerted := false
## Alvo do objetivo da quest ("kill").
var is_objective := false
## Aliado escoltado (Sir Ragnar): joga do lado dos heróis, mas só anda — não
## ataca, não procura, não usa item e não entra na campanha.
var escort := false
## Item da quest que o monstro carrega (Estrela do Oeste na mão do zumbi):
## {"name", "text"?, "gold"?, "objective_item"?}. Vai para quem o mata.
var carries: Dictionary = {}
## Herói que saiu pela escada: fora do tabuleiro, a salvo.
var escaped := false
## Herói: ouro e cartas guardadas (poções, água benta).
var gold := 0
var inventory: Array[Dictionary] = []
## Dentro de um fosso: −1 dado no ataque e na defesa até sair.
var in_pit := false
## Bônus de uma vez só: "attack"/"defend" (dados extras), "move_mult", "extra_attacks",
## "through_walls" e "pass_monsters" (próximo movimento).
var buffs: Dictionary = {}
## Estados que duram: "asleep" (não age nem defende), "skip_turns" (perde turnos),
## "rock_skin" (+1 dado de defesa até sofrer dano).
var status: Dictionary = {}
## Feitiços que ainda pode lançar nesta quest (cada um uma vez).
var spells: Array[String] = []

var _base := {}


static func from_hero(def: Dictionary) -> Unit:
	var unit := Unit.new()
	unit.side = Side.HERO
	unit._load(def)
	unit.move_dice = int(def.move_dice)
	unit._base.move_dice = unit.move_dice
	return unit


static func from_monster(def: Dictionary) -> Unit:
	var unit := Unit.new()
	unit.side = Side.MONSTER
	unit._load(def)
	unit.move = int(def.move)
	for id: String in def.get("spells", []):
		unit.spells.append(id)
	return unit


func _load(def: Dictionary) -> void:
	def_id = def.id
	name = def.name
	tags = def.get("tags", [])
	attack = int(def.attack)
	defend = int(def.defend)
	body = int(def.body)
	body_max = body
	mind = int(def.mind)
	mind_max = mind
	_base = {"attack": attack, "defend": defend, "mind": mind}


## Arma: o Ataque passa a ser o da arma. Defesa: bônus somam à base.
func apply_equipment(items: Array) -> void:
	equipment = items
	attack = _base.attack
	defend = _base.defend
	mind_max = _base.mind
	move_dice = _base.get("move_dice", 0)
	diagonal_attack = false
	ranged = false
	for it: Dictionary in items:
		if it.get("slot") == "weapon":
			attack = int(it.attack)
			diagonal_attack = it.get("diagonal", false)
			ranged = it.get("ranged", false)
		defend += int(it.get("defend_bonus", 0))
		mind_max += int(it.get("mind_bonus", 0))
		if it.has("move_dice_override") and side == Side.HERO:
			move_dice = int(it.move_dice_override)
	mind = mini(mind, mind_max)


func has_equipment(id: String) -> bool:
	return equipment.any(func(it: Dictionary) -> bool: return it.get("id") == id)


func add_buff(key: String, amount: int) -> void:
	buffs[key] = int(buffs.get(key, 0)) + amount


## Gasta o bônus: devolve o valor e zera.
func take_buff(key: String) -> int:
	var value := int(buffs.get(key, 0))
	buffs.erase(key)
	return value


func is_hero() -> bool:
	return side == Side.HERO


func is_alive() -> bool:
	return body > 0


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func take_damage(amount: int) -> void:
	body = maxi(0, body - amount)


## Cura sem passar do máximo; devolve quanto curou de fato.
func heal(amount: int) -> int:
	var before := body
	body = mini(body_max, body + amount)
	return body - before
