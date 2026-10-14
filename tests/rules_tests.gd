extends Node
## Testes das regras, headless:
##   godot --headless --path . res://tests/rules_tests.tscn
## Sai com código ≠ 0 se algo falhar.
##
## Coordenadas conferem com o mapa ASCII de docs/01-regras-heroquest.md §17:
## linha 0 e coluna 0 são corredor; a sala A ocupa x 1..4, y 1..3; a sala D
## x 1..4, y 4..8; a sala central K x 10..15, y 7..11.

var _failures := 0
var _checks := 0


func _ready() -> void:
	# Erro de script aborta só a função (e o Godot segue): por isso cada teste
	# devolve true no fim, e quem não devolver conta como falha.
	for test: Callable in [
		_test_data,
		_test_board,
		_test_pathfinder,
		_test_line_of_sight,
		_test_dice,
		_test_units,
		_test_combat,
		_test_turn,
		_test_quest,
		_test_rounds,
		_test_alerts,
		_test_ai,
		_test_visibility,
		_test_search,
		_test_traps,
		_test_treasure_cards,
		_test_magic,
		_test_chaos_magic,
		_test_heroscribe,
		_test_objective,
		_test_campaign,
		_test_armory,
		_test_jump_and_loot,
		_test_more_chaos,
		_test_barak_tor_rules,
		_test_escort,
		_test_match_replay,
		_test_match_rejects_invalid,
		_test_campaign_in_progress,
		_test_initiative,
	]:
		if test.call() != true:
			_failures += 1
			printerr("✗ %s abortou (erro de script)" % test.get_method())
	print("REGRAS %s (%d verificações, %d falhas)" % ["OK" if _failures == 0 else "FALHOU", _checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("✗ ", what)


func _no_one(_cell: Vector2i) -> int:
	return Pathfinder.FREE


func _nobody_there(_cell: Vector2i) -> bool:
	return false


# ---------- dados ----------

func _test_data() -> bool:
	for id in ["barbarian", "dwarf", "elf", "wizard"]:
		var def := GameData.hero(id)
		_check(not def.is_empty(), "herói %s existe" % id)
		for item_id: String in def.start_equipment:
			_check(not GameData.item(item_id).is_empty(), "equipamento inicial %s existe" % item_id)
	for m: Dictionary in GameData.module("monsters").monsters:
		_check(int(m.body) > 0 and int(m.move) > 0, "monstro %s com corpo e movimento" % m.id)
	var deck := 0
	for card: Dictionary in GameData.module("treasure_deck").cards:
		deck += int(card.count)
	_check(deck == 24, "baralho de tesouro tem 24 cartas (%d)" % deck)
	_check(GameData.module("spells").hero_spells.size() == 12, "12 feitiços de herói")
	return true


# ---------- tabuleiro ----------

func _test_board() -> bool:
	var b := GameData.new_board()
	_check(b.width == 26 and b.height == 19, "tabuleiro 26×19")
	_check(b.room_ids().size() == 22, "22 salas (%d)" % b.room_ids().size())
	_check(b.cells_of_zone(11).size() == 30, "sala central 6×5")
	_check(not b.is_room(Vector2i(0, 0)) and b.is_room(Vector2i(1, 1)), "corredor × sala")
	_check(not b.is_wall(Vector2i(0, 0), Vector2i(1, 0)), "corredor-corredor sem parede")
	_check(not b.is_wall(Vector2i(1, 1), Vector2i(2, 1)), "dentro da sala sem parede")
	_check(b.is_wall(Vector2i(0, 1), Vector2i(1, 1)), "corredor-sala tem parede")
	_check(b.is_wall(Vector2i(4, 1), Vector2i(5, 1)), "sala-sala tem parede (A|B)")
	_check(b.is_wall(Vector2i(0, 0), Vector2i(-1, 0)), "borda do tabuleiro é parede")
	b.add_door(Vector2i(0, 1), Vector2i(1, 1))
	_check(b.is_wall(Vector2i(1, 1), Vector2i(0, 1)), "porta fechada ainda bloqueia")
	b.open_door(Vector2i(1, 1), Vector2i(0, 1))
	_check(not b.is_wall(Vector2i(0, 1), Vector2i(1, 1)), "porta aberta (ordem inversa) fura a parede")
	b.place_furniture("table", Vector2i(2, 2), Vector2i(3, 2))
	_check(not b.is_walkable(Vector2i(4, 3)) and b.is_walkable(Vector2i(1, 3)), "mesa 3×2 bloqueia só a área dela")
	_check(not b.is_opaque(Vector2i(4, 3)), "móvel não bloqueia a visão")
	return true


# ---------- movimento ----------

func _test_pathfinder() -> bool:
	var b := GameData.new_board()
	var start := Vector2i(0, 0)
	var dest := Pathfinder.destinations(Pathfinder.flood(b, start, 3, _no_one))
	_check(dest.size() == 6, "canto: 3 passos alcançam 6 quadrados de corredor (%d)" % dest.size())
	_check(dest.all(func(c: Vector2i) -> bool: return not b.is_room(c)), "sem porta não entra em sala")

	b.add_door(Vector2i(1, 0), Vector2i(1, 1))
	_check(Pathfinder.destinations(Pathfinder.flood(b, start, 3, _no_one)).size() == 6, "porta fechada não deixa passar")
	b.open_door(Vector2i(1, 0), Vector2i(1, 1))
	var flooded := Pathfinder.flood(b, start, 3, _no_one)
	_check(Pathfinder.destinations(flooded).size() == 9, "porta aberta: +3 quadrados da sala")
	var path := Pathfinder.path_to(flooded, Vector2i(2, 1))
	_check(Array(path) == [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], "caminho passa pela porta: %s" % [path])
	_check(Pathfinder.path_to(flooded, Vector2i(3, 2)).is_empty(), "fora do alcance: sem caminho")

	var ally := func(c: Vector2i) -> int: return Pathfinder.PASS_ONLY if c == Vector2i(1, 0) else Pathfinder.FREE
	var through := Pathfinder.flood(b, start, 2, ally)
	_check(not through[Vector2i(1, 0)].stop, "não para em cima do aliado")
	_check(through.has(Vector2i(2, 0)) and through[Vector2i(2, 0)].stop, "atravessa o aliado")

	var enemy := func(c: Vector2i) -> int: return Pathfinder.BLOCKED if c == Vector2i(1, 0) else Pathfinder.FREE
	_check(not Pathfinder.flood(b, start, 2, enemy).has(Vector2i(2, 0)), "inimigo bloqueia a passagem")

	b.blocked[Vector2i(0, 1)] = true
	_check(not Pathfinder.flood(b, start, 3, _no_one).has(Vector2i(0, 2)), "quadrado bloqueado corta o corredor")
	return true


# ---------- linha de visão ----------

func _test_line_of_sight() -> bool:
	var b := GameData.new_board()
	var someone_at := func(cell: Vector2i) -> Callable:
		return func(c: Vector2i) -> bool: return c == cell

	_check(LineOfSight.can_see(b, Vector2i(10, 7), Vector2i(15, 11), someone_at.call(Vector2i(12, 9))), "mesma sala: sempre vê")
	_check(LineOfSight.can_see(b, Vector2i(0, 0), Vector2i(25, 0), _nobody_there), "corredor reto livre")
	_check(not LineOfSight.can_see(b, Vector2i(0, 0), Vector2i(25, 0), someone_at.call(Vector2i(5, 0))), "figura no meio bloqueia")
	_check(LineOfSight.can_see(b, Vector2i(0, 0), Vector2i(0, 18), _nobody_there), "coluna 0 inteira")
	_check(not LineOfSight.can_see(b, Vector2i(0, 5), Vector2i(2, 5), _nobody_there), "parede entre corredor e sala")
	b.add_door(Vector2i(0, 5), Vector2i(1, 5))
	_check(not LineOfSight.can_see(b, Vector2i(0, 5), Vector2i(3, 5), _nobody_there), "porta fechada bloqueia")
	b.open_door(Vector2i(0, 5), Vector2i(1, 5))
	_check(LineOfSight.can_see(b, Vector2i(0, 5), Vector2i(3, 5), _nobody_there), "porta aberta deixa ver")
	_check(LineOfSight.can_see(b, Vector2i(3, 5), Vector2i(0, 5), _nobody_there), "visão é simétrica")
	_check(not LineOfSight.can_see(b, Vector2i(0, 4), Vector2i(3, 6), _nobody_there), "diagonal pela porta raspa a parede")
	# Reta que passa exatamente na quina da sala A: regra estrita bloqueia.
	_check(LineOfSight.can_see(b, Vector2i(1, 0), Vector2i(0, 1), _nobody_there) == not LineOfSight.CORNER_STRICT, "quina segue CORNER_STRICT")
	b.blocked[Vector2i(10, 0)] = true
	_check(not LineOfSight.can_see(b, Vector2i(0, 0), Vector2i(20, 0), _nobody_there), "entulho bloqueia a visão")
	return true


# ---------- dados ----------

func _test_dice() -> bool:
	_check(Dice.new(42).roll_combat(20) == Dice.new(42).roll_combat(20), "mesma seed, mesmas faces")
	var dice := Dice.new(7)
	var n := 60000
	var faces := dice.roll_combat(n)
	var skull := Dice.count_face(faces, Dice.SKULL) / float(n)
	var white := Dice.count_face(faces, Dice.WHITE_SHIELD) / float(n)
	var black := Dice.count_face(faces, Dice.BLACK_SHIELD) / float(n)
	_check(absf(skull - 0.5) < 0.01, "caveira ~1/2 (%.3f)" % skull)
	_check(absf(white - 1.0 / 3.0) < 0.01, "escudo branco ~1/3 (%.3f)" % white)
	_check(absf(black - 1.0 / 6.0) < 0.01, "escudo preto ~1/6 (%.3f)" % black)
	var moves := dice.roll_d6(2)
	_check(moves.size() == 2 and moves.all(func(v: int) -> bool: return v >= 1 and v <= 6), "2d6 de movimento")
	return true


# ---------- fichas ----------

func _test_units() -> bool:
	var barbarian := GameData.new_hero("barbarian")
	_check(barbarian.attack == 3 and barbarian.defend == 2 and barbarian.body == 8, "bárbaro 3/2/8")
	var wizard := GameData.new_hero("wizard")
	_check(wizard.attack == 1 and wizard.body == 4 and wizard.mind == 6, "mago com adaga 1/·/4/6")
	var dwarf := GameData.new_hero("dwarf")
	dwarf.apply_equipment([GameData.item("shortsword"), GameData.item("plate_armour"), GameData.item("helmet")])
	_check(dwarf.defend == 5 and dwarf.move_dice == 1, "placas + elmo: defesa 5, 1 dado de movimento")
	dwarf.apply_equipment([GameData.item("battle_axe"), GameData.item("talisman_of_lore")])
	_check(dwarf.attack == 4 and dwarf.defend == 2 and dwarf.move_dice == 2 and dwarf.mind_max == 4, "trocar equipamento recalcula tudo")
	var orc := GameData.new_monster("orc")
	_check(orc.move == 8 and orc.attack == 3 and orc.defend == 2 and not orc.is_hero(), "orc 8/3/2")
	_check(GameData.new_monster("skeleton").has_tag("undead"), "esqueleto é morto-vivo")
	barbarian.take_damage(3)
	_check(barbarian.heal(10) == 3 and barbarian.body == 8, "cura não passa do máximo")
	return true


# ---------- combate ----------

func _test_combat() -> bool:
	var state := GameState.new(GameData.new_board(), 1)
	var barbarian := GameData.new_hero("barbarian")
	var orc := GameData.new_monster("orc")
	state.add_unit(barbarian, Vector2i(5, 0))
	state.add_unit(orc, Vector2i(6, 0))
	_check(Combat.can_melee(state, barbarian, orc), "ataca vizinho ortogonal")
	_check(not Combat.can_melee(state, barbarian, barbarian), "não ataca a si mesmo")
	orc.pos = Vector2i(6, 1)
	_check(not Combat.can_melee(state, barbarian, orc), "espada larga não ataca na diagonal")

	# Mago com bastão ataca na diagonal dentro da sala.
	var wizard := GameData.new_hero("wizard")
	wizard.apply_equipment([GameData.item("staff")])
	var mummy := GameData.new_monster("mummy")
	state.add_unit(wizard, Vector2i(11, 8))
	state.add_unit(mummy, Vector2i(12, 9))
	_check(Combat.can_melee(state, wizard, mummy), "bastão ataca na diagonal")
	mummy.pos = Vector2i(10, 6)
	wizard.pos = Vector2i(10, 7)
	_check(not Combat.can_melee(state, wizard, mummy), "não ataca através da parede")

	var elf := GameData.new_hero("elf")
	elf.apply_equipment([GameData.item("crossbow")])
	var goblin := GameData.new_monster("goblin")
	state.add_unit(elf, Vector2i(0, 9))
	state.add_unit(goblin, Vector2i(1, 9))
	_check(not Combat.can_attack(state, elf, goblin), "besta não atira em vizinho")
	goblin.pos = Vector2i(8, 9)
	_check(Combat.can_shoot(state, elf, goblin), "besta atira de longe com visão")
	goblin.pos = Vector2i(2, 13)
	_check(not Combat.can_shoot(state, elf, goblin), "besta precisa de visão")

	# Cada evento é consistente e a média bate com a conta exata.
	var dice := Dice.new(99)
	var trials := 20000
	var total := 0
	var consistent := true
	for i in trials:
		var a := GameData.new_hero("barbarian")
		var d := GameData.new_monster("gargoyle")
		var ev := Combat.resolve(dice, a, d)
		consistent = consistent and ev.damage == maxi(0, ev.hits - ev.blocks) and d.body == maxi(0, 3 - ev.damage)
		consistent = consistent and ev.attack_faces.size() == 3 and ev.defend_faces.size() == 5
		consistent = consistent and ev.blocks == Dice.count_face(ev.defend_faces, Dice.BLACK_SHIELD)
		total += ev.damage
	_check(consistent, "dano = caveiras − escudos pretos, aplicado no Corpo")
	var expected := _expected_damage(3, 0.5, 5, 1.0 / 6.0)
	var mean := total / float(trials)
	_check(absf(mean - expected) < 0.03, "bárbaro × gárgula: média %.3f ≈ %.3f" % [mean, expected])

	var hero_def := Combat.resolve(Dice.new(5), GameData.new_monster("chaos_warrior"), GameData.new_hero("dwarf"))
	_check(hero_def.blocks == Dice.count_face(hero_def.defend_faces, Dice.WHITE_SHIELD), "herói bloqueia com escudo branco")
	return true


## E[max(0, caveiras − escudos)] com as duas binomiais.
func _expected_damage(attack: int, p_hit: float, defend: int, p_block: float) -> float:
	var e := 0.0
	for h in attack + 1:
		for s in defend + 1:
			e += _binom(attack, h, p_hit) * _binom(defend, s, p_block) * maxi(0, h - s)
	return e


func _binom(n: int, k: int, p: float) -> float:
	var c := 1.0
	for i in k:
		c = c * (n - i) / (i + 1)
	return c * pow(p, k) * pow(1.0 - p, n - k)


# ---------- turno ----------

func _test_turn() -> bool:
	var state := GameState.new(GameData.new_board(), 3)
	var barbarian := GameData.new_hero("barbarian")
	var orc := GameData.new_monster("orc")
	state.add_unit(barbarian, Vector2i(0, 0))
	state.add_unit(orc, Vector2i(3, 0))

	# Mover → agir → não move mais.
	state.begin_turn(barbarian)
	_check(state.needs_movement_roll() and state.move_active(Vector2i(1, 0)).is_empty(), "herói precisa rolar antes de andar")
	var roll := state.roll_movement()
	_check(roll.total >= 2 and roll.total <= 12, "2d6 de movimento (%d)" % roll.total)
	_check(state.move_active(Vector2i(4, 0)).is_empty(), "não atravessa o orc")
	# 2 passos: o mínimo de 2d6, então vale para qualquer rolagem.
	var ev := state.move_active(Vector2i(2, 0))
	_check(ev.get("path", []).size() == 2 and barbarian.pos == Vector2i(2, 0), "anda 2 até o orc")
	_check(state.move_left == roll.total - 2, "gasta o movimento")
	_check(not state.attack(orc).is_empty(), "ataca depois de andar")
	_check(not state.can_move(), "mover → agir → não move de novo")
	_check(state.attack(orc).is_empty(), "uma ação por turno")

	# Agir → mover vale.
	state.begin_turn(barbarian)
	if orc.is_alive():
		_check(not state.attack(orc).is_empty(), "ataca antes de andar")
	else:
		state.has_acted = true
	_check(state.can_move(), "agir → mover é permitido")
	state.roll_movement()
	_check(not state.move_active(Vector2i(1, 0)).is_empty(), "anda depois de agir")

	# Monstro: movimento fixo, sem rolagem.
	var goblin := GameData.new_monster("goblin")
	state.add_unit(goblin, Vector2i(0, 9))
	state.begin_turn(goblin)
	_check(not state.needs_movement_roll() and state.move_left == 10, "goblin anda 10 sem rolar")
	_check(not state.move_active(Vector2i(0, 18)).is_empty(), "goblin anda 9")
	_check(state.move_active(Vector2i(10, 18)).is_empty(), "não passa do movimento restante")

	# Porta é ação livre.
	state.board.add_door(Vector2i(1, 0), Vector2i(1, 1))
	state.begin_turn(barbarian)
	_check(not state.open_door(Vector2i(1, 0), Vector2i(1, 1)).is_empty(), "herói abre a porta ao lado")
	_check(state.can_act(), "abrir porta não gasta a ação")
	_check(state.open_door(Vector2i(1, 0), Vector2i(1, 1)).is_empty(), "porta já aberta")
	return true


# ---------- quest ----------

func _test_quest() -> bool:
	var state := QuestLoader.build(GameData.quest("sandbox"), 1)
	var heroes := state.alive(Unit.Side.HERO)
	_check(heroes.map(func(u: Unit) -> String: return u.def_id) == ["barbarian", "dwarf", "elf", "wizard"], "4 heróis na ordem")
	_check(heroes[0].pos == Vector2i(10, 7), "heróis na escada")
	_check(state.board.is_walkable(Vector2i(10, 7)), "escada não bloqueia")
	_check(state.alive(Unit.Side.MONSTER).size() == 8, "8 monstros")
	_check(state.unit_at(Vector2i(3, 7)).name == "Guardião", "override de nome")
	_check(state.board.furniture.get(Vector2i(8, 5)) == "table", "mesa 3×2 em (6,4) cobre (8,5)")
	_check(state.board.furniture.get(Vector2i(3, 6)) == "tomb", "túmulo 2×3 em (2,4) cobre (3,6)")
	_check(state.board.blocked.has(Vector2i(20, 0)), "bloco no corredor")
	var secret := state.board.door_between(Vector2i(4, 5), Vector2i(5, 5))
	_check(secret.secret and state.board.is_wall(Vector2i(4, 5), Vector2i(5, 5)), "porta secreta é parede")
	_check(state.closed_doors_next_to(Vector2i(12, 7)) == [[Vector2i(12, 7), Vector2i(12, 6)]], "porta ao lado do quadrado")
	_check(state.closed_doors_next_to(Vector2i(4, 5)).is_empty(), "porta secreta não aparece")

	var rotated := QuestLoader.build({"start": [[0, 0]], "heroes": ["elf"],
		"objects": [{"type": "furniture", "id": "bookcase", "pos": [1, 1], "rot": 1}]})
	_check(rotated.board.furniture.has(Vector2i(1, 3)) and not rotated.board.furniture.has(Vector2i(2, 1)), "rot 1 gira o móvel")
	return true


func _test_rounds() -> bool:
	var state := QuestLoader.build(GameData.quest("sandbox"), 1)
	var ev := state.start_round()
	_check(ev.type == "turn_started" and state.active.def_id == "barbarian" and state.round_number == 1, "rodada 1 começa no Bárbaro")
	state.alive(Unit.Side.HERO)[2].take_damage(99)
	var seen: Array = []
	ev = state.end_turn()
	while ev.type == "turn_started":
		seen.append(state.active.def_id)
		ev = state.end_turn()
	_check(seen == ["dwarf", "wizard"], "herói morto é pulado (%s)" % [seen])
	_check(ev.type == "zargon_phase" and state.active == null, "depois dos heróis vem Zargon")
	ev = state.start_round()
	_check(state.round_number == 2 and state.active.def_id == "barbarian", "nova rodada")
	for hero in state.alive(Unit.Side.HERO):
		hero.take_damage(99)
	_check(state.start_round().type == "heroes_defeated", "sem heróis vivos")
	return true


# ---------- alerta e IA de Zargon ----------

## Partida vazia (só tabuleiro) com as figuras dadas: [[unit, cell], ...].
func _arena(placements: Array, seed_value := 1) -> GameState:
	var state := GameState.new(GameData.new_board(), seed_value)
	for p: Array in placements:
		state.add_unit(p[0], p[1])
	return state


func _test_alerts() -> bool:
	var state := QuestLoader.build(GameData.quest("sandbox"), 1)
	state.start_round()
	var corridor_goblin := state.unit_at(Vector2i(13, 1))
	var room_goblin := state.unit_at(Vector2i(10, 3))
	_check(not corridor_goblin.alerted and not room_goblin.alerted, "começa sem ninguém alertado (portas fechadas)")
	state.active.pos = Vector2i(12, 7)
	var ev := state.open_door(Vector2i(12, 7), Vector2i(12, 6))
	_check(ev.alerted.has(corridor_goblin) and corridor_goblin.alerted, "abrir a porta revela o goblin do corredor")
	_check(not room_goblin.alerted, "goblin atrás de outra porta segue dormindo")
	return true


func _test_ai() -> bool:
	# 1. Já colado: ataca o herói mais fraco sem andar.
	var orc := GameData.new_monster("orc")
	var wizard := GameData.new_hero("wizard")
	var barbarian := GameData.new_hero("barbarian")
	var state := _arena([[orc, Vector2i(5, 0)], [wizard, Vector2i(6, 0)], [barbarian, Vector2i(4, 0)]])
	orc.alerted = true
	var events := ZargonAI.take_turn(state, orc)
	_check(events.size() == 1 and events[0].type == "attack" and events[0].defender == wizard, "ataca o mais fraco (Mago)")
	_check(orc.pos == Vector2i(5, 0), "não sai do lugar para atacar")

	# 2. Longe mas ao alcance: anda até colar e ataca.
	var goblin := GameData.new_monster("goblin")
	var elf := GameData.new_hero("elf")
	state = _arena([[goblin, Vector2i(0, 0)], [elf, Vector2i(8, 0)]])
	goblin.alerted = true
	events = ZargonAI.take_turn(state, goblin)
	_check(events.size() == 2 and events[0].type == "move" and events[1].type == "attack", "anda e ataca")
	_check(goblin.pos == Vector2i(7, 0), "para colado no Elfo (%s)" % goblin.pos)

	# 3. Fora de alcance: avança o máximo pelo caminho mais curto.
	var mummy := GameData.new_monster("mummy")
	var dwarf := GameData.new_hero("dwarf")
	state = _arena([[mummy, Vector2i(0, 0)], [dwarf, Vector2i(20, 0)]])
	mummy.alerted = true
	events = ZargonAI.take_turn(state, mummy)
	_check(events.size() == 1 and mummy.pos == Vector2i(4, 0), "múmia anda 4 na direção do Anão (%s)" % mummy.pos)

	# 4. Não alertado: fica parado.
	var skeleton := GameData.new_monster("skeleton")
	state = _arena([[skeleton, Vector2i(0, 0)], [GameData.new_hero("elf"), Vector2i(3, 0)]])
	_check(ZargonAI.take_turn(state, skeleton).is_empty() and skeleton.pos == Vector2i(0, 0), "monstro dormindo não age")

	# 5. Porta fechada: monstro não abre; sem caminho, fica parado.
	var orc2 := GameData.new_monster("orc")
	state = _arena([[orc2, Vector2i(0, 0)], [GameData.new_hero("elf"), Vector2i(2, 2)]])
	state.board.add_door(Vector2i(2, 0), Vector2i(2, 1))
	orc2.alerted = true
	_check(ZargonAI.take_turn(state, orc2).is_empty() and orc2.pos == Vector2i(0, 0), "não abre porta")
	state.board.open_door(Vector2i(2, 0), Vector2i(2, 1))
	events = ZargonAI.take_turn(state, orc2)
	_check(not events.is_empty() and events[-1].type == "attack", "porta aberta: entra e ataca")

	# 6. Atravessa outro monstro, mas não herói.
	var g1 := GameData.new_monster("goblin")
	var g2 := GameData.new_monster("goblin")
	var hero := GameData.new_hero("barbarian")
	state = _arena([[g1, Vector2i(0, 0)], [g2, Vector2i(1, 0)], [hero, Vector2i(5, 0)]])
	g1.alerted = true
	ZargonAI.take_turn(state, g1)
	_check(g1.pos == Vector2i(4, 0), "passa pelo goblin aliado (%s)" % g1.pos)

	# 7. Morte de herói pela IA acaba a rodada em derrota.
	var gargoyle := GameData.new_monster("gargoyle")
	var victim := GameData.new_hero("wizard")
	state = _arena([[gargoyle, Vector2i(0, 0)], [victim, Vector2i(1, 0)]], 5)
	gargoyle.alerted = true
	var guard := 0
	while victim.is_alive() and guard < 50:
		ZargonAI.take_turn(state, gargoyle)
		guard += 1
	_check(not victim.is_alive(), "gárgula mata o Mago")
	_check(state.start_round().type == "heroes_defeated", "sem heróis: derrota")
	return true


# ---------- exploração (fase 3) ----------

## Quest mínima: heróis em `starts` e os objetos dados.
func _quest(starts: Array, heroes: Array, objects: Array, seed_value := 1) -> GameState:
	var state := QuestLoader.build({"start": starts, "heroes": heroes, "objects": objects}, seed_value)
	state.start_round()
	return state


func _card(id: String) -> Dictionary:
	for c: Dictionary in GameData.module("treasure_deck").cards:
		if c.id == id:
			return c
	return {}


func _test_visibility() -> bool:
	var state := QuestLoader.build(GameData.quest("sandbox"), 1)
	state.start_round()
	_check(state.revealed.size() == 30, "no começo só a sala central (%d)" % state.revealed.size())
	_check(not state.revealed.has(Vector2i(12, 6)), "porta fechada esconde o corredor")
	state.active.pos = Vector2i(12, 7)
	var ev := state.open_door(Vector2i(12, 7), Vector2i(12, 6))
	_check(state.revealed.has(Vector2i(12, 6)) and state.revealed.has(Vector2i(13, 1)), "porta aberta revela o corredor")
	_check(not state.revealed.has(Vector2i(10, 3)), "sala C (porta fechada) continua escondida")
	_check(ev.revealed.size() > 0 and ev.alerted.size() == 1, "evento traz o revelado e o goblin alertado")
	return true


func _test_search() -> bool:
	var state := _quest([[2, 2]], ["dwarf"], [
		{"type": "furniture", "id": "treasure_chest", "pos": [1, 1]},
		{"type": "trap", "id": "chest", "pos": [1, 1], "damage": 2},
		{"type": "treasure", "pos": [1, 1], "gold": 120},
		{"type": "trap", "id": "pit", "pos": [3, 3]},
		{"type": "secret_door", "a": [4, 2], "b": [5, 2]},
	])
	var dwarf := state.active
	_check(Exploration.can_search_treasure(state), "pode procurar tesouro na sala")
	var ev := Exploration.search_treasure(state)
	_check(ev.has("chest_trap") and dwarf.body == 5, "baú com armadilha dispara (2 de dano)")
	_check(ev.gold == 120 and dwarf.gold == 120, "acha o tesouro da quest")
	state.begin_turn(dwarf)
	_check(not Exploration.can_search_treasure(state), "só uma busca de tesouro por sala")

	ev = Exploration.search_traps(state)
	_check(ev.traps.size() == 1 and state.traps[Vector2i(3, 3)].known, "acha o fosso")
	_check(ev.doors.size() == 1 and not state.board.is_wall(Vector2i(4, 2), Vector2i(5, 2)), "acha e abre a porta secreta")
	_check(state.revealed.has(Vector2i(6, 2)), "porta secreta revela a sala vizinha")

	state.begin_turn(dwarf)
	_check(not Exploration.can_disarm(state, Vector2i(3, 3)), "longe demais para desarmar")
	dwarf.pos = Vector2i(3, 2)
	ev = Exploration.disarm(state, Vector2i(3, 3))
	_check(ev.success and not state.traps.has(Vector2i(3, 3)), "Anão desarma sem rolar")

	var elf_state := _quest([[2, 2]], ["elf"], [{"type": "trap", "id": "pit", "pos": [3, 2]}])
	elf_state.traps[Vector2i(3, 2)].known = true
	_check(not Exploration.can_disarm(elf_state, Vector2i(3, 2)), "Elfo sem kit não desarma")
	elf_state.active.apply_equipment([GameData.item("shortsword"), GameData.item("tool_kit")])
	_check(Exploration.can_disarm(elf_state, Vector2i(3, 2)), "com Kit de Ferramentas pode")

	var busy := _quest([[2, 2]], ["barbarian"], [{"type": "monster", "id": "goblin", "pos": [4, 3]}])
	_check(not Exploration.can_search(busy), "monstro na sala impede procurar")
	return true


func _test_traps() -> bool:
	var state := _quest([[0, 0]], ["barbarian"], [{"type": "trap", "id": "spear", "pos": [3, 0]}])
	var hero := state.active
	state.move_left = 6
	var ev := state.move_active(Vector2i(6, 0))
	_check(hero.pos == Vector2i(3, 0) and ev.trap.id == "spear", "lança: para em cima da armadilha")
	_check(ev.trap.damage == Dice.count_face(ev.trap.faces, Dice.SKULL), "lança: dano = caveira")
	_check(not state.traps.has(Vector2i(3, 0)) and not state.can_move() and not state.can_act(), "lança some e o turno acaba")

	state = _quest([[0, 0]], ["barbarian"], [{"type": "trap", "id": "pit", "pos": [3, 0]}])
	hero = state.active
	state.move_left = 6
	state.move_active(Vector2i(6, 0))
	_check(hero.in_pit and hero.body == 7 and state.traps[Vector2i(3, 0)].known, "fosso: 1 de dano e herói dentro")
	var orc := GameData.new_monster("orc")
	state.add_unit(orc, Vector2i(4, 0))
	state.begin_turn(hero)
	ev = state.attack(orc)
	_check(ev.attack_faces.size() == hero.attack - 1, "no fosso rola 1 dado a menos")
	state.begin_turn(hero)
	state.move_left = 2
	state.move_active(Vector2i(2, 0))
	_check(not hero.in_pit, "sair do fosso tira a penalidade")
	_check(not state.flood_for(hero, 6).has(Vector2i(3, 0)), "fosso conhecido bloqueia o caminho")

	state = _quest([[0, 0]], ["dwarf"], [{"type": "trap", "id": "falling_block", "pos": [3, 0]}])
	hero = state.active
	state.move_left = 6
	ev = state.move_active(Vector2i(6, 0))
	_check(hero.pos == Vector2i(2, 0) and ev.trap.pushed_to == Vector2i(2, 0), "bloco: herói recua")
	_check(state.board.blocked.has(Vector2i(3, 0)) and ev.trap.faces.size() == 3, "bloco vira parede; 3 dados de dano")

	state = _quest([[0, 0]], ["elf"], [{"type": "trap", "id": "pit", "pos": [2, 0]}, {"type": "monster", "id": "goblin", "pos": [3, 0]}])
	var goblin := state.unit_at(Vector2i(3, 0))
	goblin.alerted = true
	state.begin_turn(goblin)
	state.move_active(Vector2i(1, 0))
	_check(goblin.pos == Vector2i(1, 0) and not state.traps[Vector2i(2, 0)].known, "monstro não dispara armadilha")
	return true


func _test_treasure_cards() -> bool:
	var state := _quest([[2, 2]], ["barbarian"], [])
	_check(state.treasure_deck.size() == 24, "baralho com 24 cartas")
	var hero := state.active
	state.treasure_deck.push_front(_card("gold_50"))
	var ev := Exploration.search_treasure(state)
	_check(ev.card.id == "gold_50" and hero.gold == 50 and state.treasure_deck[-1].id == "gold_50", "ouro: soma e a carta volta ao fundo")

	state = _quest([[2, 2]], ["barbarian"], [])
	hero = state.active
	var before := state.treasure_deck.size()
	state.treasure_deck.push_front(_card("potion_strength"))
	Exploration.search_treasure(state)
	_check(hero.inventory.size() == 1 and state.treasure_deck.size() == before, "poção fica com o herói")
	ev = Exploration.use_item(state, 0)
	_check(ev.type == "item_used" and hero.inventory.is_empty() and state.treasure_deck[-1].id == "potion_strength", "beber devolve a carta ao fundo")
	var orc := GameData.new_monster("orc")
	state.add_unit(orc, Vector2i(3, 2))
	state.begin_turn(hero)
	ev = state.attack(orc)
	_check(ev.attack_faces.size() == hero.attack + 2, "Poção de Força: +2 dados no ataque")

	state = _quest([[2, 2]], ["wizard"], [])
	hero = state.active
	state.treasure_deck.push_front(_card("wandering_monster"))
	ev = Exploration.search_treasure(state)
	var wandering: Dictionary = ev.wandering
	_check(wandering.monster.def_id == "orc" and Combat.is_orthogonal_neighbor(wandering.monster.pos, hero.pos), "monstro errante surge colado")
	_check(wandering.attack.defender == hero and wandering.monster.alerted, "e ataca na hora")

	state = _quest([[2, 2]], ["wizard"], [])
	hero = state.active
	hero.inventory.append(_card("potion_healing"))
	var gargoyle := GameData.new_monster("gargoyle")
	state.add_unit(gargoyle, Vector2i(3, 2))
	var saved := false
	for i in 40:
		ev = state.strike(gargoyle, hero)
		if ev.has("saved_by_potion"):
			saved = true
			break
	_check(saved and hero.is_alive() and hero.inventory.is_empty(), "poção de cura salva da morte")

	state = _quest([[2, 2]], ["elf"], [{"type": "monster", "id": "skeleton", "pos": [3, 2]}])
	hero = state.active
	hero.inventory.append(_card("holy_water"))
	ev = Exploration.use_item(state, 0)
	_check(ev.destroyed.def_id == "skeleton" and not ev.destroyed.is_alive() and not state.can_act(), "Água Benta destrói o esqueleto (gasta a ação)")
	return true


# ---------- magia (fase 4) ----------

func _test_magic() -> bool:
	# Figuras tapam a visão: só Bárbaro e Mago ficam no corredor de baixo.
	var state := _quest([[1, 9], [0, 11], [0, 12], [4, 9]], ["barbarian", "dwarf", "elf", "wizard"], [])
	var heroes := state.alive(Unit.Side.HERO)
	var barbarian := heroes[0]
	var elf := heroes[2]
	var wizard := heroes[3]
	Magic.assign_schools(state, "fire", "water")
	_check(wizard.spells.size() == 9 and elf.spells.size() == 3, "Mago com 9 feitiços, Elfo com 3")
	_check(elf.spells.has("sleep") and not wizard.spells.has("sleep") and wizard.spells.has("genie"), "Elfo fica com a Água; Mago com o resto")
	var all := wizard.spells + elf.spells
	_check(all.size() == 12 and _all_distinct(all), "as 12 cartas, sem repetir")

	# Dano com resistência: Bola de Fogo = 2 − (5s e 6s em 2d6).
	var orc := GameData.new_monster("orc")
	orc.body = 5
	orc.body_max = 5
	state.add_unit(orc, Vector2i(8, 9))
	state.revealed[orc.pos] = true
	state.begin_turn(wizard)
	var ev := Magic.cast(state, "ball_of_flame", orc)
	var saved := (ev.resist as Array).filter(func(v: int) -> bool: return v >= 5).size()
	_check(ev.damage == maxi(0, 2 - saved) and orc.body == 5 - ev.damage, "Bola de Fogo: 2 − resistências (%s)" % [ev.resist])
	_check(not wizard.spells.has("ball_of_flame") and not state.can_act(), "feitiço some e gasta a ação")
	state.begin_turn(wizard)
	_check(Magic.cast(state, "ball_of_flame", orc).is_empty(), "não lança o mesmo feitiço duas vezes")

	# Precisa de visão: monstro atrás da parede não é alvo.
	var hidden := GameData.new_monster("goblin")
	state.add_unit(hidden, Vector2i(2, 11))
	state.revealed[hidden.pos] = true
	_check(not Magic.targets(state, wizard, "fire_of_wrath").has(hidden), "sem visão, sem alvo")
	_check(Magic.out_of_sight(state, wizard, "fire_of_wrath").has(hidden), "fora da vista: a tela marca de vermelho")
	_check(not Magic.out_of_sight(state, wizard, "fire_of_wrath").has(orc), "à vista não entra na lista de fora")
	state.revealed.erase(hidden.pos)
	_check(not Magic.out_of_sight(state, wizard, "fire_of_wrath").has(hidden), "monstro na névoa não é marcado")
	state.revealed[hidden.pos] = true

	# Cura e buffs em aliados.
	barbarian.take_damage(5)
	state.begin_turn(wizard)
	ev = Magic.cast(state, "heal_body", barbarian)
	_check(ev.healed == 4 and barbarian.body == 7, "Curar Corpo: +4")
	state.begin_turn(wizard)
	Magic.cast(state, "courage", barbarian)
	state.begin_turn(barbarian)
	orc.pos = Vector2i(0, 9)
	ev = state.attack(orc) if Combat.can_attack(state, barbarian, orc) else {}
	orc.pos = Vector2i(8, 9)
	_check(not ev.is_empty() and ev.attack_faces.size() == barbarian.attack + 2, "Coragem: +2 dados no próximo ataque")
	state.begin_turn(wizard)
	Magic.cast(state, "swift_wind", barbarian)
	state.begin_turn(barbarian)
	_check(state.roll_movement().values.size() == 4, "Vento Veloz: 4 dados de movimento")

	# Pele de Pedra: +1 dado na defesa até levar dano.
	state.begin_turn(wizard)
	Magic.cast(state, "rock_skin", wizard)
	var gargoyle := GameData.new_monster("gargoyle")
	state.add_unit(gargoyle, Vector2i(5, 9))
	var hit := state.strike(gargoyle, wizard)
	_check(hit.defend_faces.size() == 3, "Pele de Pedra: 3 dados de defesa")
	if hit.damage > 0:
		_check(not wizard.status.has("rock_skin"), "dano quebra a Pele de Pedra")
	gargoyle.body = 0

	# Atravessar Rocha: o próximo movimento ignora paredes.
	state.begin_turn(wizard)
	Magic.cast(state, "pass_through_rock", wizard)
	_check(state.flood_for(wizard, 2).has(Vector2i(4, 10)), "Atravessar Rocha entra na sala sem porta")
	state.move_left = 2
	state.has_acted = false
	state.move_active(Vector2i(4, 10))
	_check(wizard.pos == Vector2i(4, 10) and not wizard.buffs.has("through_walls"), "anda pela parede e o efeito acaba")

	# Sono (Elfo) e Tempestade (Mago) nos monstros.
	state = _quest([[1, 9], [2, 9], [3, 9], [4, 9]], ["barbarian", "dwarf", "elf", "wizard"],
		[{"type": "monster", "id": "orc", "pos": [7, 9]}, {"type": "monster", "id": "skeleton", "pos": [8, 9]}])
	Magic.assign_schools(state, "air", "water")
	heroes = state.alive(Unit.Side.HERO)
	elf = heroes[2]
	wizard = heroes[3]
	var orc2 := state.unit_at(Vector2i(7, 9))
	var skeleton := state.unit_at(Vector2i(8, 9))
	for h in heroes:
		h.pos = Vector2i(0, 10 + heroes.find(h))
	elf.pos = Vector2i(5, 9)
	state.begin_turn(elf)
	_check(not Magic.targets(state, elf, "sleep").has(skeleton), "Sono não pega em morto-vivo")
	Magic.cast(state, "sleep", orc2)
	_check(orc2.status.asleep, "orc dorme")
	var strike := state.strike(heroes[0], orc2)
	_check(strike.defend_faces.is_empty(), "dormindo não defende")
	elf.pos = Vector2i(0, 15)
	wizard.pos = Vector2i(5, 9)
	state.begin_turn(wizard)
	Magic.cast(state, "tempest", skeleton)
	skeleton.alerted = true
	var events := ZargonAI.take_turn(state, skeleton)
	_check(events.size() == 1 and events[0].type == "turn_lost" and events[0].reason == "tempest", "Tempestade: monstro perde o turno")
	events = ZargonAI.take_turn(state, skeleton)
	_check(events.is_empty() or events[0].type != "turn_lost", "e joga no turno seguinte")

	# Gênio: 5 dados contra o monstro, ou abre uma porta à vista.
	state = _quest([[1, 9], [2, 9], [3, 9], [4, 9]], ["barbarian", "dwarf", "elf", "wizard"],
		[{"type": "monster", "id": "orc", "pos": [7, 9]}, {"type": "door", "a": [6, 9], "b": [6, 8]}])
	Magic.assign_schools(state, "fire", "water")
	wizard = state.alive(Unit.Side.HERO)[3]
	state.begin_turn(wizard)
	var genie_targets := Magic.targets(state, wizard, "genie")
	_check(genie_targets.has([Vector2i(6, 8), Vector2i(6, 9)]), "Gênio enxerga a porta (%s)" % [genie_targets])
	ev = Magic.cast(state, "genie", state.unit_at(Vector2i(7, 9)))
	_check(ev.attack.attack_faces.size() == 5, "Gênio ataca com 5 dados")
	return true


## 12 ids sem repetir (as 4 escolas inteiras).
func _all_distinct(ids: Array) -> bool:
	var seen := {}
	for id: String in ids:
		seen[id] = true
	return seen.size() == 12


func _test_chaos_magic() -> bool:
	var state := _quest([[1, 9]], ["barbarian"], [{"type": "monster", "id": "chaos_warlock", "pos": [6, 9]}])
	var hero := state.active
	var warlock := state.unit_at(Vector2i(6, 9))
	_check(warlock.spells.size() == 3 and warlock.alerted, "feiticeiro com 3 feitiços do Caos")
	var events := ZargonAI.take_turn(state, warlock)
	_check(events.size() == 1 and events[0].type == "spell" and events[0].spell.id == "c_ball_of_flame", "começa com Bola de Fogo")
	_check(hero.body == 8 - events[0].damage, "herói sofre o dano")
	events = ZargonAI.take_turn(state, warlock)
	_check(events[0].spell.id == "c_sleep" and hero.status.get("asleep", false), "depois põe o herói para dormir")
	var woke := false
	var lost := 0
	for i in 30:
		var ev := state.lose_turn(hero)
		if ev.is_empty():
			woke = true
			break
		lost += 1
		_check(ev.reason == "asleep" and ev.rolls.size() == hero.mind, "rola 1d6 por ponto de Mente")
	_check(woke and not hero.status.has("asleep"), "acorda com um 6 (depois de %d turnos)" % lost)
	return true


# ---------- quests do HeroScribe e objetivo (fase 5) ----------

func _test_heroscribe() -> bool:
	var board := GameData.new_board()
	var files: Array[String] = ["barak_tor_eu", "everyones_a_suspect", "enter_the_crypt"]
	for f in DirAccess.get_files_at("res://referencias/heroscribe/hqbase_eu"):
		if f.ends_with(".xml"):
			files.append("hqbase_eu/" + f.get_basename())
	for file in files:
		var path := "res://referencias/heroscribe/%s.xml" % file
		var q := HeroScribeImporter.parse(path)
		_check(not q.is_empty() and q.start.size() == 4, "%s: lido, com escada" % file)
		# enter_the_crypt tem uma porta secreta no meio da sala (erro do mapa).
		_check(q.warnings.size() == (1 if file == "enter_the_crypt" else 0), "%s: avisos %s" % [file, q.warnings])
		var xml := FileAccess.get_file_as_string(path)
		var expected := 0
		for id: String in HeroScribeImporter.MONSTERS:
			expected += xml.count('id="%s"' % id)
		var monsters: Array = q.objects.filter(func(o: Dictionary) -> bool: return o.type == "monster")
		_check(monsters.size() == expected, "%s: %d monstros" % [file, monsters.size()])
		for o: Dictionary in q.objects:
			if o.type in ["door", "secret_door"]:
				var a := QuestLoader.cell(o.a)
				var b := QuestLoader.cell(o.b)
				_check(board.in_bounds(a) and board.in_bounds(b) and board.zone_at(a) != board.zone_at(b),
					"%s: %s em %s–%s fica numa parede" % [file, o.type, a, b])
			elif o.type == "furniture":
				var def := GameData.furniture(o.id)
				var size := Vector2i(int(def.size[0]), int(def.size[1]))
				if int(o.rot) % 2 == 1:
					size = Vector2i(size.y, size.x)
				var top_left := QuestLoader.cell(o.pos)
				var zone := board.zone_at(top_left)
				var fits := true
				for dy in size.y:
					for dx in size.x:
						var c := top_left + Vector2i(dx, dy)
						fits = fits and board.in_bounds(c) and board.zone_at(c) == zone
				_check(fits, "%s: %s em %s cabe numa sala só" % [file, o.id, top_left])

	# The Trial: chefe sem letra no mapa ("at"), guardião com 4 dados e baús por letra.
	var trial := QuestLoader.build(GameData.quest("the_trial"), 1)
	var verag: Array = trial.units.filter(func(u: Unit) -> bool: return u.is_objective)
	_check(verag.size() == 1 and verag[0].def_id == "gargoyle" and verag[0].name == "Verag", "The Trial: Verag é o alvo")
	_check(trial.units.any(func(u: Unit) -> bool: return u.def_id == "mummy" and u.attack == 4), "The Trial: guardião ataca com 4")
	_check(trial.furniture.size() == 16 and trial.treasures.size() == 3, "The Trial: 16 móveis e 3 baús da quest")
	_check(trial.objective.type == "kill" and not trial.is_objective_done(), "The Trial: objetivo matar Verag")

	var state := QuestLoader.build(GameData.quest("barak_tor"), 1)
	_check(state.alive(Unit.Side.HERO).size() == 4 and state.stairway.has(state.alive(Unit.Side.HERO)[0].pos), "Barak Tor: heróis na escada")
	_check(state.alive(Unit.Side.MONSTER).size() == 12, "Barak Tor: 12 monstros")
	_check(state.board.dark.size() == 206, "Barak Tor: área escura")
	_check(state.board.doors.values().filter(func(d: Dictionary) -> bool: return d.fake).size() == 2, "Barak Tor: 2 portas falsas (letra A)")
	_check(state.objective.type == "find" and not state.is_objective_done(), "Barak Tor: objetivo de achar a Estrela")
	return true


## Item carregado sem ninguém por perto, Rei Bruxo (imune) e o despertar na sala da tumba.
func _test_barak_tor_rules() -> bool:
	var state := QuestLoader.build(GameData.quest("barak_tor"), 1)
	state.start_round()
	var hero := state.alive(Unit.Side.HERO)[0]
	var zombie: Unit = state.units.filter(func(u: Unit) -> bool: return not u.carries.is_empty())[0]
	zombie.body = 0
	var out := state.after_damage(zombie)
	var zone := state.board.zone_at(zombie.pos)
	_check(out.carried.to == null and state.treasures[zone][0].get("objective_item", false), "sem herói na sala, a Estrela vira tesouro da sala")

	# Despertar: entrar na sala da tumba (letra D) traz o Rei Bruxo no X.
	_check(state.ambushes.size() == 1 and state.units.all(func(u: Unit) -> bool: return u.def_id != "witch_lord"), "Rei Bruxo começa adormecido")
	hero.pos = Vector2i(2, 13)
	var ambush := state._spring_ambush(hero)
	var lord: Unit = ambush.get("monster")
	_check(lord != null and lord.def_id == "witch_lord" and lord.pos == Vector2i(1, 10) and lord.alerted, "Rei Bruxo desperta no X")
	_check(state._spring_ambush(hero).is_empty(), "desperta uma vez só")

	# Imune a armas comuns e a magia; a Lâmina Espiritual fere.
	for i in 5:
		var ev := state.strike(hero, lord, 6)
		_check(ev.immune and ev.damage == 0 and lord.is_alive(), "sem a Lâmina o golpe não fere")
	var wizard: Unit = state.units.filter(func(u: Unit) -> bool: return u.def_id == "wizard")[0]
	wizard.pos = Vector2i(3, 12)
	wizard.spells.assign(["fire_of_wrath", "genie"])
	for spell in wizard.spells:
		_check(not Magic.targets(state, wizard, spell).has(lord), "%s não pega no Rei Bruxo" % spell)
	hero.apply_equipment([GameData.item("spirit_blade")])
	_check(not state.strike(hero, lord).immune, "com a Lâmina Espiritual ele pode ser ferido")
	return true


## Resgate de Sir Ragnar: prisioneiro vira aliado, alarme, escolta e derrota se ele morrer.
func _test_escort() -> bool:
	var state := QuestLoader.build(GameData.quest("rescue_sir_ragnar"), 1)
	state.start_round()
	_check(not state.captive.is_empty() and state.units.all(func(u: Unit) -> bool: return not u.escort), "Ragnar começa preso (fora do tabuleiro)")
	_check(state.furniture.size() == 6 and state.treasures.size() == 2 and state.traps.has(Vector2i(2, 13)), "Ragnar: móveis, 2 baús e o baú com armadilha")
	var hero := state.active
	var x: Vector2i = state.captive.pos
	hero.pos = x + Vector2i(1, 0)
	var ev := state.update_visibility()
	var ally: Unit = ev.get("rescue", {}).get("ally")
	_check(ally != null and ally.escort and ally.pos == x and state.units.find(ally) == state.units.find(hero) + 1, "achar Ragnar: aliado logo depois de quem o achou")
	_check(state.alive(Unit.Side.MONSTER).all(func(m: Unit) -> bool: return m.alerted), "alarme: todos os monstros alertados")
	_check(state.board.doors.values().all(func(d: Dictionary) -> bool: return d.open or d.secret or d.fake), "alarme: portas abertas")
	_check(state.revealed.size() == state.board.width * state.board.height - state.board.dark.size(), "alarme: mapa todo à vista")

	# Ragnar só anda: não ataca nem procura.
	var orc := GameData.new_monster("orc")
	state.add_unit(orc, x + Vector2i(0, 1) if state.board.is_walkable(x + Vector2i(0, 1)) and not state.is_occupied(x + Vector2i(0, 1)) else x + Vector2i(-1, 0))
	state.begin_turn(ally)
	_check(not Combat.can_attack(state, ally, orc) and not Exploration.can_search(state), "Ragnar não ataca nem procura")
	_check(state.needs_movement_roll() and ally.move_dice == 1, "Ragnar anda 1 dado")
	_check(Combat.can_attack(state, orc, ally), "monstros podem atacar Ragnar")

	# Sai pela escada mesmo antes do objetivo; quem o achou ganha 200.
	var gold := hero.gold
	ally.pos = state.stairway[0]
	var out := state.try_escape(ally)
	_check(out.get("escaped") == ally and state.is_objective_done() and hero.gold == gold + 200, "Ragnar a salvo: objetivo cumprido e recompensa")
	_check(state.outcome() == "", "a quest só acaba quando os heróis saem")

	# Se ele morrer, a quest falha na hora.
	state = QuestLoader.build(GameData.quest("rescue_sir_ragnar"), 1)
	state.start_round()
	state.active.pos = state.captive.pos + Vector2i(1, 0)
	ally = state.update_visibility().rescue.ally
	ally.body = 0
	_check(state.outcome() == "defeat" and state.end_turn().type == "heroes_defeated", "Ragnar morto: derrota")

	# Poção da quest não entra no baralho de tesouro ao ser usada.
	var deck_size := state.treasure_deck.size()
	var h := state.alive(Unit.Side.HERO)[0]
	state.begin_turn(h)
	h.inventory.append({"id": "potion_healing_quest", "name": "Poção de Cura", "potion": {"heal": 4}, "quest_item": true})
	Exploration.use_item(state, h.inventory.size() - 1)
	_check(state.treasure_deck.size() == deck_size, "poção da quest não vai para o baralho")
	return true


func _test_objective() -> bool:
	var state := QuestLoader.build(GameData.quest("barak_tor"), 1)
	state.start_round()
	var heroes := state.alive(Unit.Side.HERO)
	var hero := heroes[0]
	# Letra B: o zumbi carrega a Estrela; quem o mata fica com ela (e os 200 de ouro).
	var carriers: Array = state.units.filter(func(u: Unit) -> bool: return not u.carries.is_empty())
	_check(carriers.size() == 1 and carriers[0].def_id == "zombie", "Barak Tor: um zumbi carrega a Estrela")
	var zombie: Unit = carriers[0]
	zombie.body = 0
	var gold := hero.gold
	var out := state.after_damage(zombie, hero)
	_check(out.carried.to == hero and hero.gold == gold + 200 and state.is_objective_done(), "matar o zumbi da letra B dá a Estrela")
	var ev: Dictionary

	# Só um herói sobra; ele chega na escada e sai: vitória.
	for h in heroes:
		if h != hero:
			h.body = 0
	hero.pos = Vector2i(3, 14)
	state.begin_turn(hero)
	state.move_left = 1
	ev = state.move_active(Vector2i(2, 14))
	_check(ev.get("escaped") == hero and hero.escaped and state.alive(Unit.Side.HERO).is_empty(), "herói sai pela escada")
	_check(state.outcome() == "victory" and state.end_turn().type == "quest_complete", "vitória")

	# Sem o objetivo, a escada não tira ninguém.
	state = QuestLoader.build(GameData.quest("sandbox"), 1)
	state.start_round()
	var barbarian := state.active
	_check(state.try_escape(barbarian).is_empty(), "sem objetivo cumprido não sai")
	var warlock: Unit = state.units.filter(func(u: Unit) -> bool: return u.is_objective)[0]
	warlock.body = 0
	_check(state.is_objective_done(), "matar o Feiticeiro cumpre o objetivo da sandbox")
	for h in state.alive(Unit.Side.HERO):
		h.body = 0
	_check(state.start_round().type == "heroes_defeated", "todos mortos e ninguém saiu: derrota")

	# Porta falsa: tentar abrir só revela que é falsa.
	state = _quest([[2, 0]], ["elf"], [{"type": "door", "a": [2, 0], "b": [2, 1], "fake": true}])
	ev = state.open_door(Vector2i(2, 0), Vector2i(2, 1))
	_check(ev.type == "fake_door" and state.board.is_wall(Vector2i(2, 0), Vector2i(2, 1)), "porta falsa não abre")
	_check(state.closed_doors_next_to(Vector2i(2, 0)).is_empty(), "e deixa de aparecer como porta")
	return true


# ---------- campanha e armeria (fase 6) ----------

func _test_campaign() -> bool:
	var c := Campaign.create()
	_check(c.heroes.size() == 4 and c.next_quest() == "sandbox", "campanha nova: 4 heróis, começa no treino")
	_check(not c.is_unlocked("barak_tor"), "quest seguinte bloqueada")
	c.hero("barbarian").gold = 300
	c.hero("barbarian").equipment = ["broadsword", "helmet"]
	var units := c.hero_units()
	_check(units[0].gold == 300 and units[0].defend == 3, "unidade traz ouro e equipamento da campanha")

	# Vitória: sobreviventes guardam o ouro; o morto recomeça do zero.
	var state := QuestLoader.build(GameData.quest("sandbox"), 1, c.hero_units())
	var heroes := state.alive(Unit.Side.HERO)
	heroes[0].gold = 450
	heroes[1].body = 0
	heroes[3].inventory.append({"id": "potion_healing", "name": "Poção de Cura", "potion": {"heal": "1d6"}})
	for h in heroes:
		if h.is_alive():
			h.escaped = true
	for u in state.units:
		if u.is_objective:
			u.body = 0
	var report := c.record(state, "sandbox")
	_check(report.result == "victory" and c.completed.has("sandbox") and c.next_quest() == "the_trial", "vitória libera a próxima quest")
	_check(c.hero("barbarian").gold == 450 and c.hero("barbarian").quests_done == 1, "sobrevivente guarda o ouro")
	_check(report.fallen.size() == 1 and c.hero("dwarf").quests_done == 0 and c.hero("dwarf").equipment == ["shortsword"], "Anão morto recomeça do zero")
	_check(not c.to_dict().heroes[3].has("inventory"), "poções não passam de quest")

	# Campeão: 3 quests completas dão 500 de ouro uma vez.
	c.hero("elf").quests_done = 2
	var gold_before := int(c.hero("elf").gold)
	state = QuestLoader.build(GameData.quest("sandbox"), 2, c.hero_units())
	for h in state.alive(Unit.Side.HERO):
		h.escaped = true
	for u in state.units:
		if u.is_objective:
			u.body = 0
	report = c.record(state, "sandbox")
	_check(report.champions.has("Elfo") and c.hero("elf").gold == gold_before + 500 and c.hero("elf").champion, "Campeão ganha 500")

	# Save e load.
	var path := "user://test_campaign.json"
	_check(c.save(path) and Campaign.has_save(path), "grava a campanha")
	var loaded := Campaign.load_from(path)
	_check(loaded != null and loaded.to_dict() == c.to_dict(), "carrega igual ao que gravou")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(Campaign.load_from("user://nao_existe.json") == null, "sem save, sem campanha")
	return true


func _test_armory() -> bool:
	var barbarian := Campaign.fresh_hero("barbarian")
	barbarian.gold = 1000
	_check(Armory.buy(barbarian, "battle_axe") == "" and barbarian.gold == 600, "compra o Machado de Batalha")
	_check(barbarian.equipment == ["battle_axe"], "arma nova substitui a antiga")
	_check(Armory.buy(barbarian, "shield") != "", "duas mãos não deixa usar escudo")
	_check(Armory.buy(barbarian, "battle_axe") == "Já tem", "não compra o que já tem")
	_check(Armory.buy(barbarian, "plate_armour") == "Ouro insuficiente", "sem ouro, sem compra")
	_check(Armory.buy(barbarian, "chain_mail") == "" and Armory.buy(barbarian, "helmet") == "", "compra armadura e elmo")
	barbarian.gold = 1000
	_check(Armory.buy(barbarian, "plate_armour") == "" and not barbarian.equipment.has("chain_mail"), "placas substituem a cota de malha")

	var wizard := Campaign.fresh_hero("wizard")
	wizard.gold = 1000
	_check(Armory.buy(wizard, "broadsword") == "O Mago não pode usar", "Mago não usa espada larga")
	_check(Armory.buy(wizard, "cloak_of_protection") == "", "Manto de Proteção é do Mago")
	var elf := Campaign.fresh_hero("elf")
	elf.gold = 1000
	_check(Armory.buy(elf, "cloak_of_protection") == "Só o Mago", "Elfo não usa o Manto")

	elf.equipment.append("spirit_blade")
	Armory.buy(elf, "broadsword")
	_check(elf.equipment.has("spirit_blade"), "artefato não é trocado pela armeria")
	return true


# ---------- polimento (fase 7) ----------

func _test_jump_and_loot() -> bool:
	# Pulo: tenta com várias seeds até ver passar e cair.
	var saw_success := false
	var saw_fall := false
	for seed_value in range(1, 40):
		var state := _quest([[0, 0]], ["barbarian"], [{"type": "trap", "id": "pit", "pos": [1, 0]}], seed_value)
		state.traps[Vector2i(1, 0)].known = true
		var hero := state.active
		state.move_left = 3
		_check(not state.can_jump(Vector2i(3, 0)) and state.can_jump(Vector2i(2, 0)), "só pula para logo depois do fosso")
		var ev := state.jump_pit(Vector2i(2, 0))
		if ev.success:
			saw_success = true
			_check(hero.pos == Vector2i(2, 0) and state.move_left == 1 and not hero.in_pit, "pulo: passa e gasta 2")
		else:
			saw_fall = true
			_check(hero.pos == Vector2i(1, 0) and hero.in_pit and hero.body == 7 and not state.can_move(), "pulo: cai no fosso e o turno acaba")
		if saw_success and saw_fall:
			break
	_check(saw_success and saw_fall, "pulo tem os dois resultados")
	var short := _quest([[0, 0]], ["barbarian"], [{"type": "trap", "id": "pit", "pos": [1, 0]}])
	short.traps[Vector2i(1, 0)].known = true
	short.move_left = 1
	_check(not short.can_jump(Vector2i(2, 0)), "sem 2 de movimento não pula")

	# Espólio: herói que morre na sala passa ouro e poções ao aliado da sala.
	var state := _quest([[2, 2], [3, 2], [0, 0]], ["elf", "dwarf", "wizard"], [])
	var heroes := state.alive(Unit.Side.HERO)
	var elf := heroes[0]
	var dwarf := heroes[1]
	var wizard := heroes[2]
	elf.gold = 90
	elf.inventory.append(_card("potion_strength"))
	elf.take_damage(99)
	var loot: Dictionary = state.after_damage(elf).loot
	_check(loot.to == dwarf and dwarf.gold == 90 and dwarf.inventory.size() == 1 and elf.gold == 0, "aliado na sala fica com o espólio")
	wizard.gold = 40
	wizard.take_damage(99)
	loot = state.after_damage(wizard).loot
	_check(loot.to == null and wizard.gold == 0 and dwarf.gold == 90, "no corredor, sozinho: os monstros ficam com tudo")
	return true


func _test_more_chaos() -> bool:
	# Tempestade de Fogo: 3 em todos na sala, inclusive monstros, menos o conjurador.
	var state := _quest([[1, 1], [2, 1]], ["barbarian", "dwarf"], [
		{"type": "monster", "id": "chaos_warlock", "pos": [4, 3], "override": {"spells": ["c_firestorm"]}},
		{"type": "monster", "id": "goblin", "pos": [1, 3]}])
	var warlock := state.unit_at(Vector2i(4, 3))
	var goblin := state.unit_at(Vector2i(1, 3))
	var events := ZargonAI.take_turn(state, warlock)
	_check(events[0].spell.id == "c_firestorm" and events[0].hits.size() == 3, "Tempestade de Fogo pega os 3 da sala")
	_check(state.alive(Unit.Side.HERO)[0].body == 5 and not goblin.is_alive() and warlock.body == 3, "3 de dano, conjurador ileso")

	# Nuvem do Caos: paralisa os heróis da sala; perdem a vez até tirar 6.
	state = _quest([[1, 1], [2, 1]], ["barbarian", "dwarf"], [
		{"type": "monster", "id": "chaos_warlock", "pos": [4, 3], "override": {"spells": ["c_cloud_of_chaos"]}}])
	warlock = state.unit_at(Vector2i(4, 3))
	ZargonAI.take_turn(state, warlock)
	var barbarian := state.alive(Unit.Side.HERO)[0]
	_check(barbarian.status.get("asleep", false) and barbarian.status.get("paralyzed", false), "Nuvem do Caos paralisa")
	var lost := state.lose_turn(barbarian)
	_check(lost.is_empty() or lost.reason == "paralyzed", "paralisado perde a vez")

	# Comando: perde turnos, mas ainda defende.
	state = _quest([[1, 1]], ["wizard"], [
		{"type": "monster", "id": "chaos_warlock", "pos": [4, 3], "override": {"spells": ["c_command"]}}])
	warlock = state.unit_at(Vector2i(4, 3))
	var wizard := state.active
	ZargonAI.take_turn(state, warlock)
	_check(wizard.status.get("commanded", false), "Comando prende o Mago")
	var hit := state.strike(warlock, wizard)
	_check(hit.defend_faces.size() == wizard.defend, "sob Comando ainda defende")

	# Invocar: monstros novos em volta do conjurador, já alertados.
	state = _quest([[1, 1]], ["elf"], [
		{"type": "monster", "id": "chaos_warlock", "pos": [4, 3], "override": {"spells": ["c_summon_undead"]}}])
	warlock = state.unit_at(Vector2i(4, 3))
	events = ZargonAI.take_turn(state, warlock)
	var summoned: Array = events[0].summoned
	_check(summoned.size() >= 2 and summoned.size() <= 4, "invoca de 2 a 4 (%d)" % summoned.size())
	_check(summoned.all(func(m: Unit) -> bool: return m.alerted and m.has_tag("undead")), "mortos-vivos alertados")
	return true


# ---------- partida por comandos (Match) ----------

## Joga turnos com escolhas que só dependem do estado: rola, anda para o quadrado
## alcançável mais distante, ataca quem estiver colado, procura e passa a vez.
func _autoplay(m: Match, commands: int) -> int:
	var zargon_turns := 0
	var guard := 0
	while m.commands.size() < commands and guard < commands * 4:
		guard += 1
		var state := m.state
		if state.active == null:
			break
		var events: Array[Dictionary] = []
		if state.needs_movement_roll() and state.can_move():
			events = m.apply({"type": "roll"})
		elif state.can_move() and state.move_left > 0 and state.flood_for(state.active, state.move_left).size() > 1:
			var best := state.active.pos
			for cell: Vector2i in state.flood_for(state.active, state.move_left):
				if cell.x + cell.y * 2 > best.x + best.y * 2 or (cell.x + cell.y * 2 == best.x + best.y * 2 and cell.x > best.x):
					best = cell
			events = m.apply({"type": "move", "to": Match.cell_arg(best)})
			if events.is_empty():
				events = m.apply({"type": "end_turn"})
			else:
				for monster in state.alive(Unit.Side.MONSTER):
					if Combat.can_attack(state, state.active, monster) if state.active != null else false:
						m.apply({"type": "attack", "target": state.units.find(monster)})
						break
				if state.active != null and Exploration.can_search_treasure(state):
					m.apply({"type": "search_treasure"})
		else:
			events = m.apply({"type": "end_turn"})
		for ev in events:
			if ev.type == "zargon_turn":
				zargon_turns += 1
	return zargon_turns


func _test_match_replay() -> bool:
	var c := Campaign.create()
	c.hero("barbarian").gold = 120
	var m := Match.create("sandbox", 21, c.heroes)
	_check(m.begin().is_empty() and m.state.round_number == 0, "Match espera a escolha das escolas")
	var first := m.apply({"type": "schools", "wizard": "fire", "elf": "water"})
	_check(first.size() == 1 and first[0].type == "turn_started" and m.state.round_number == 1, "escolas começam a rodada 1")
	_check(m.state.alive(Unit.Side.HERO)[0].gold == 120, "heróis vêm da campanha")
	var zargon := _autoplay(m, 60)
	_check(m.commands.size() >= 30, "partida jogada por comandos (%d)" % m.commands.size())
	_check(m.state.round_number >= 3, "rodadas passam pelo Match (rodada %d)" % m.state.round_number)
	_check(zargon > 0, "Zargon joga dentro do Match (%d turnos de monstro)" % zargon)
	# Ida e volta pelo JSON (números viram float) e replay chegam ao mesmo estado.
	var data: Variant = JSON.parse_string(JSON.stringify(m.to_dict()))
	var copy := Match.from_dict(data)
	_check(copy != null and copy.state_hash() == m.state_hash(), "replay do log chega ao mesmo estado")
	_check(copy != null and copy.commands.size() == m.commands.size(), "replay refaz todos os comandos")
	if copy != null:
		var a := m.apply({"type": "end_turn"})
		var b := copy.apply({"type": "end_turn"})
		_check(a.size() == b.size() and m.state_hash() == copy.state_hash(), "as duas cópias seguem juntas")
	return true


func _test_match_rejects_invalid() -> bool:
	var m := Match.create("sandbox", 3)
	m.begin()
	_check(m.apply({"type": "roll"}).is_empty(), "nada vale antes das escolas")
	_check(m.apply({"type": "schools", "wizard": "fire", "elf": "fire"}).is_empty(), "escolas repetidas recusadas")
	m.apply({"type": "schools", "wizard": "fire", "elf": "water"})
	_check(m.apply({"type": "schools", "wizard": "air", "elf": "earth"}).is_empty(), "escolas só uma vez")
	_check(m.apply({"type": "move", "to": [12, 7]}).is_empty(), "andar sem rolar é recusado")
	_check(m.apply({"type": "attack", "target": 999}).is_empty(), "alvo inexistente é recusado")
	_check(m.apply({"type": "move", "to": "x"}).is_empty() and m.apply({"type": "bogus"}).is_empty(), "comando malformado é recusado")
	var before := m.commands.size()
	m.apply({"type": "roll"})
	_check(m.apply({"type": "roll"}).is_empty(), "rolar duas vezes é recusado")
	_check(m.commands.size() == before + 1, "só o comando válido entra no log")
	return true


func _test_campaign_in_progress() -> bool:
	var c := Campaign.create()
	var m := Match.create("sandbox", 8, c.heroes)
	m.begin()
	m.apply({"type": "schools", "wizard": "air", "elf": "earth"})
	m.apply({"type": "roll"})
	c.in_progress = m.to_dict()
	var path := "user://test_in_progress.json"
	c.save(path)
	var loaded := Campaign.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check(loaded.in_progress.get("quest_id") == "sandbox", "quest em andamento vai no save")
	var resumed := Match.from_dict(loaded.in_progress)
	_check(resumed != null and resumed.state_hash() == m.state_hash(), "retoma do save no mesmo ponto")
	var old := Campaign.from_dict({"heroes": c.to_dict().heroes, "completed": []})
	_check(old.in_progress.is_empty(), "save antigo (versão 1) abre sem quest em andamento")
	c.record(m.state, "sandbox")
	_check(c.in_progress.is_empty(), "fim da quest limpa a partida em andamento")
	return true


func _test_initiative() -> bool:
	var ids := ["barbarian", "dwarf", "elf", "wizard"]
	var firsts := {}
	for seed_value in 60:
		var order := Match.roll_initiative(ids, seed_value)
		_check(order.size() == 4 and order.map(func(o: Dictionary) -> String: return o.hero).all(ids.has), "iniciativa traz cada herói uma vez")
		var winner: Dictionary = order[0]
		# Quem começa venceu a última rolagem de desempate: ninguém tirou mais nela.
		var last: int = winner.rolls[-1]
		var round_i: int = winner.rolls.size() - 1
		for o: Dictionary in order.slice(1):
			_check(o.rolls.size() <= round_i or int(o.rolls[round_i]) < last, "quem começa tirou o maior (seed %d)" % seed_value)
		firsts[winner.hero] = true
	_check(firsts.size() == 4, "qualquer herói pode começar")
	_check(Match.roll_initiative(ids, 7) == Match.roll_initiative(ids, 7), "mesma seed, mesma ordem")
	_check(Match.roll_initiative(["elf"], 1).size() == 1 and Match.roll_initiative([], 1).is_empty(), "um herói ou nenhum")
	# A ordem vira a ordem dos turnos e vai no save.
	var c := Campaign.create()
	var order := Match.roll_initiative(["elf", "barbarian"], 3)
	var m := Match.create("sandbox", 3, order.map(func(o: Dictionary) -> Dictionary: return c.hero(o.hero)))
	m.initiative = order
	m.begin()
	m.apply({"type": "schools", "wizard": "air", "elf": "earth"})
	_check(m.state.active.def_id == order[0].hero and m.state.alive(Unit.Side.HERO).size() == 2, "só os heróis escolhidos, na ordem da iniciativa")
	var copy := Match.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	_check(copy != null and copy.initiative == order and copy.state_hash() == m.state_hash(), "iniciativa vai no save")
	return true
