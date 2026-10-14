class_name Combat
extends RefCounted
## Combate do HeroQuest: o atacante rola Ataque em dados de combate (caveira = acerto),
## o defensor rola Defesa (herói bloqueia com escudo branco, monstro com o preto).


static func is_orthogonal_neighbor(a: Vector2i, b: Vector2i) -> bool:
	var d := (a - b).abs()
	return d.x + d.y == 1


static func is_diagonal_neighbor(a: Vector2i, b: Vector2i) -> bool:
	var d := (a - b).abs()
	return d.x == 1 and d.y == 1


## Corpo a corpo: vizinho ortogonal sem parede no meio, ou diagonal com arma
## que permite (e com visão, para não atacar através da quina de uma parede).
static func can_melee(state: GameState, attacker: Unit, target: Unit) -> bool:
	if attacker.ranged or not _valid_pair(attacker, target):
		return false
	if is_orthogonal_neighbor(attacker.pos, target.pos):
		return not state.board.is_wall(attacker.pos, target.pos)
	if is_diagonal_neighbor(attacker.pos, target.pos):
		return attacker.diagonal_attack and state.can_see(attacker.pos, target.pos)
	return false


## Projétil: alvo visível, sem limite de alcance, mas nunca colado no atirador.
static func can_shoot(state: GameState, attacker: Unit, target: Unit) -> bool:
	if not attacker.ranged or not _valid_pair(attacker, target):
		return false
	var d := (attacker.pos - target.pos).abs()
	return maxi(d.x, d.y) > 1 and state.can_see(attacker.pos, target.pos)


static func can_attack(state: GameState, attacker: Unit, target: Unit) -> bool:
	return can_melee(state, attacker, target) or can_shoot(state, attacker, target)


## Rola o ataque e a defesa e aplica o dano. Devolve o evento para a apresentação.
## immune: os dados rolam, mas o golpe não fere (Rei Bruxo sem a Lâmina Espiritual).
static func resolve(dice: Dice, attacker: Unit, defender: Unit, attack_bonus := 0, defend_bonus := 0, immune := false) -> Dictionary:
	var attack_faces := dice.roll_combat(maxi(0, attacker.attack + attack_bonus))
	var defend_faces := dice.roll_combat(maxi(0, defender.defend + defend_bonus))
	var shield := Dice.WHITE_SHIELD if defender.is_hero() else Dice.BLACK_SHIELD
	var hits := Dice.count_face(attack_faces, Dice.SKULL)
	var blocks := Dice.count_face(defend_faces, shield)
	var damage := 0 if immune else maxi(0, hits - blocks)
	defender.take_damage(damage)
	return {
		"type": "attack",
		"attacker": attacker,
		"defender": defender,
		"attack_faces": attack_faces,
		"defend_faces": defend_faces,
		"hits": hits,
		"blocks": blocks,
		"damage": damage,
		"killed": not defender.is_alive(),
		"immune": immune,
	}


static func _valid_pair(attacker: Unit, target: Unit) -> bool:
	return attacker.is_alive() and not attacker.escort and target.is_alive() and attacker.side != target.side
