class_name Dice
extends RefCounted
## Todas as rolagens da partida saem daqui, com seed: a partida é reproduzível
## e os dados 3D só mostram o resultado já sorteado.
##
## Dado de combate: 3 caveiras, 2 escudos brancos (herói), 1 escudo preto (monstro).

const SKULL := "skull"
const WHITE_SHIELD := "white_shield"
const BLACK_SHIELD := "black_shield"
## Face do d6 -> face do dado de combate.
const COMBAT_FACES: Array[String] = [SKULL, SKULL, SKULL, WHITE_SHIELD, WHITE_SHIELD, BLACK_SHIELD]

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value


func d6() -> int:
	return rng.randi_range(1, 6)


func roll_d6(count: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(d6())
	return out


func roll_combat(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in count:
		out.append(COMBAT_FACES[d6() - 1])
	return out


## Embaralha no lugar (Fisher-Yates), com a seed da partida.
func shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp


static func count_face(faces: Array[String], face: String) -> int:
	return faces.count(face)


static func total(values: Array[int]) -> int:
	var sum := 0
	for v in values:
		sum += v
	return sum
