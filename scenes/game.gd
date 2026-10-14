extends Node3D
## Partida em 3D: heróis jogáveis com o mouse e Zargon jogando sozinho.
## - Quadrado azul: anda até ele (passe o mouse para ver o caminho).
## - Monstro em vermelho: ataca.
## - Quadrado verde: fica atrás de uma porta colada no herói; clique para abrir.
## - Quadrado laranja: armadilha conhecida que o herói pode desarmar.
## - R rola o movimento; T procura tesouro; F procura armadilhas e portas
##   secretas; Espaço/Enter encerra o turno. Poções: botões no painel.
## - Feitiço: escolha no painel, depois clique no alvo marcado de roxo (Esc cancela).
##   No começo da partida, Mago e Elfo escolhem as escolas de magia.
## Monstros só aparecem e agem depois de revelados (névoa + ZargonAI).
##
## Toda regra passa pelo Match (comandos → GameState/Exploration/Magic, e a vez
## de Zargon); aqui só se traduz entrada em comando e se animam os eventos
## devolvidos. Em campanha, a partida é gravada a cada comando e pode ser
## retomada. As funções públicas também são usadas pelo tests/game_smoke.gd.

## Quest quando a cena abre direto (sem passar pelo menu); HQ_QUEST=<id> troca.
const DEFAULT_QUEST := "barak_tor"
const TRAP_NAMES := {"pit": "fosso", "spear": "lança escondida", "falling_block": "bloco que cai", "chest": "baú armado"}
## Efeitos sem dano/cura, para o log: "%s" = alvo.
const SPELL_EFFECTS := {
	"swift_wind": "%s rolará o dobro de dados no próximo movimento.",
	"courage": "%s rola +2 dados no próximo ataque.",
	"tempest": "%s perde o próximo turno.",
	"c_tempest": "%s perde o próximo turno.",
	"sleep": "%s cai no sono.",
	"c_sleep": "%s cai no sono.",
	"veil_of_mist": "%s atravessa monstros no próximo movimento.",
	"pass_through_rock": "%s atravessa paredes no próximo movimento.",
	"rock_skin": "%s ganha +1 dado de defesa até se ferir.",
}

var quest_match: Match
var state: GameState
var board_view: BoardView
var rig: CameraRig
var dice_tray: DiceTray
var hud: Hud
var figures: Dictionary = {}  # Unit -> FigureView
## Animando um evento: entrada travada.
var busy := false
## Online: comandos confirmados pelo servidor esperando a vez de animar ([seq, cmd, hash]).
var _incoming: Array = []
var _pumping := false
var _resyncing := false
## Campanha no começo da quest (online, o resumo do fim sai dela; quem grava é o servidor).
var _campaign_at_start := {}

var _flood: Dictionary = {}
var _hover := Vector2i(-1, -1)
## Feitiço escolhido no painel, esperando o clique no alvo ("" = nenhum).
var _pending_spell := ""
var _cards_shown := {}  # tipo de monstro -> já mostrou a carta nesta partida


func _ready() -> void:
	var seed_value := int(Time.get_unix_time_from_system())
	if OS.has_environment("HQ_SEED"):
		seed_value = int(OS.get_environment("HQ_SEED"))
	var quest_id := Session.quest_id
	if quest_id == "":
		quest_id = OS.get_environment("HQ_QUEST") if OS.has_environment("HQ_QUEST") else DEFAULT_QUEST
	var campaign := Session.campaign
	if campaign != null and campaign.in_progress.get("quest_id", "") == quest_id:
		quest_match = Match.from_dict(campaign.in_progress)
	if quest_match == null and Session.online:
		push_error("Partida online sem quest em andamento")
		Session.go(Session.HUB)
		return
	if quest_match == null:
		quest_match = Match.create(quest_id, seed_value, campaign.heroes if campaign != null else [])
		quest_match.opening = quest_match.begin()
		_autosave()
	var resumed := not quest_match.commands.is_empty()
	if campaign != null:
		_campaign_at_start = campaign.to_dict()
	if Session.online:
		Net.command_applied.connect(_on_applied)
		Net.room_changed.connect(_on_room_changed)
	state = quest_match.state
	_build_world()
	hud = Hud.new()
	add_child(hud)
	hud.setup({
		"roll": roll_movement, "end": end_turn,
		"treasure": search_treasure, "traps": search_traps, "use_item": use_item,
		"select_spell": select_spell, "leave": leave,
	})
	hud.log_line("[b]%s[/b]" % state.quest.name)
	if state.quest.get("intro", "") != "":
		hud.log_line("[i]%s[/i]" % state.quest.intro)
	hud.log_line("[color=#fd6]Objetivo: %s[/color]" % state.objective.get("text", "volte à escada."))
	_refresh_hud()
	if resumed and state.round_number > 0:
		hud.log_line("[color=#fd6]Partida retomada: rodada %d.[/color]" % state.round_number)
		if state.active != null:
			rig.focus(BoardView.cell_center(state.active.pos), true)
			figures[state.active].set_active(true)
		_refresh()
	elif state.quest.get("intro", "") != "":
		hud.show_intro(state.quest.name, state.quest.intro, "Objetivo: %s" % state.objective.get("text", "volte à escada."),
			_begin, _initiative_text())
	else:
		await _begin()


## Começo da quest (depois da página do livro): escolha das escolas ou a primeira vez.
func _begin() -> void:
	if not quest_match.initiative.is_empty() and state.round_number == 0:
		await _play_initiative()
		if state.round_number > 0:
			return
	if Magic.needs_school_choice(state):
		if Session.online and not Net.can_control("wizard"):
			hud.log_line("Esperando %s escolher as escolas de magia." % Net.controller_name("wizard"))
		else:
			var ids: Array = state.alive(Unit.Side.HERO).map(func(u: Unit) -> String: return u.def_id)
			hud.ask_schools(ids.has("wizard"), ids.has("elf"), choose_schools)
	else:
		await _play_all(quest_match.opening)


## Iniciativa da mesa online: o 1d6 de cada herói no tabuleiro (o maior em destaque) e a ordem no log.
func _play_initiative() -> void:
	hud.log_line("[color=#fd6]%s[/color]" % _initiative_text())
	var first: Dictionary = quest_match.initiative[0]
	var values: Array = quest_match.initiative.map(func(o: Dictionary) -> int: return int(o.rolls[0]))
	var anchor := BoardView.cell_center(state.units.filter(func(u: Unit) -> bool: return u.def_id == first.hero)[0].pos)
	await dice_tray.roll_d6(anchor, values, int(first.rolls[0]))


## "Iniciativa: Elfo (Bia) tirou 6 e começa; depois Bárbaro (Ana), Anão (Bia)." ("" fora do online)
func _initiative_text() -> String:
	if quest_match.initiative.is_empty():
		return ""
	var names: Array[String] = []
	for o: Dictionary in quest_match.initiative:
		var player := " (%s)" % Net.controller_name(o.hero) if Session.online else ""
		names.append("%s%s" % [GameData.hero(o.hero).name, player])
	var first: Dictionary = quest_match.initiative[0]
	var rolls := " e ".join(first.rolls.map(func(v: int) -> String: return str(v)))
	var text := "Iniciativa: %s tirou %s e começa" % [names[0], rolls]
	if names.size() > 1:
		text += "; depois %s" % ", ".join(names.slice(1))
	return text + "."


## Distribui as escolas e começa a rodada 1 (a tela de escolha chama isto).
func choose_schools(wizard_school: String, elf_school: String) -> void:
	if state.round_number > 0 or busy:
		return
	hud.close_intro()
	hud.close_schools()
	await _submit({"type": "schools", "wizard": wizard_school, "elf": elf_school})


# ---------- ações (também usadas pelo smoke test) ----------

func roll_movement() -> void:
	if _can_input() and state.needs_movement_roll() and state.can_move():
		await _submit({"type": "roll"})


func click_cell(cell: Vector2i) -> void:
	if not _can_input():
		return
	if _pending_spell != "":
		var target: Variant = _spell_target_at(cell)
		if target != null:
			var id := _pending_spell
			_pending_spell = ""
			await _submit(quest_match.spell_command(id, target))
		else:
			for unit: Unit in Magic.out_of_sight(state, state.active, _pending_spell):
				if unit.pos == cell:
					hud.log_line("%s não está à vista: o feitiço precisa de linha de visão." % unit.name)
		return
	var hero := state.active
	for pair: Array in state.closed_doors_next_to(hero.pos):
		if pair[1] == cell:
			await _submit({"type": "open_door", "from": Match.cell_arg(pair[0]), "to": Match.cell_arg(pair[1])})
			return
	if Exploration.can_disarm(state, cell):
		await _submit({"type": "disarm", "cell": Match.cell_arg(cell)})
		return
	var target := state.unit_at(cell)
	if target != null and not target.is_hero():
		await _submit({"type": "attack", "target": state.units.find(target)})
		return
	if _flood.has(cell):
		await _submit({"type": "move", "to": Match.cell_arg(cell)})
	elif state.can_jump(cell):
		await _submit({"type": "jump", "to": Match.cell_arg(cell)})


func search_treasure() -> void:
	if _can_input():
		await _submit({"type": "search_treasure"})


func search_traps() -> void:
	if _can_input():
		await _submit({"type": "search_traps"})


## Escolhe (ou desescolhe) o feitiço; o próximo clique num alvo roxo lança.
func select_spell(id: String) -> void:
	if not _can_input() or not state.can_act():
		return
	_pending_spell = "" if _pending_spell == id else id
	_refresh()


func use_item(index: int) -> void:
	if _can_input():
		await _submit({"type": "use_item", "index": index})


func end_turn() -> void:
	if _can_input():
		_pending_spell = ""
		await _submit({"type": "end_turn"})


## Sai da quest sem anotar nada na campanha (em campanha, ela fica gravada para continuar).
func leave() -> void:
	if busy and not Session.online:
		return
	Session.go(Session.HUB if Session.campaign != null else Session.MENU)


func _can_input() -> bool:
	if busy or state.active == null or not state.active.is_hero():
		return false
	if Session.online:
		return Net.my_heroes().size() > 0 if state.active.escort else Net.can_control(state.active.def_id)
	return true


# ---------- eventos ----------

## Manda o comando ao Match e anima o que ele devolver (nada, se não vale).
## Online o comando vai ao servidor; volta em _on_applied (para todos da sala).
func _submit(cmd: Dictionary) -> void:
	if Session.online:
		Net.send_command(cmd)
		return
	var events := quest_match.apply(cmd)
	if events.is_empty():
		return
	_autosave()
	await _play_all(events)


func _play_all(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	busy = true
	_refresh()
	for event in events:
		await _play(event)
	busy = false
	_refresh()


# ---------- online ----------

func _on_applied(seq: int, cmd: Dictionary, digest: String) -> void:
	_incoming.append([seq, cmd, digest])
	if not _pumping:
		_pump()


## Aplica e anima, em ordem, os comandos que o servidor confirmou.
func _pump() -> void:
	_pumping = true
	while not _incoming.is_empty() and not _resyncing:
		var item: Array = _incoming.pop_front()
		var seq: int = item[0]
		if seq <= quest_match.commands.size():
			continue
		var events: Array[Dictionary] = []
		if seq == quest_match.commands.size() + 1:
			events = quest_match.apply(item[1])
		if events.is_empty() or quest_match.state_hash() != item[2]:
			_resync()
			break
		await _play_all(events)
	_pumping = false


## Fora de sincronia: pede a sala de novo e reabre a partida a partir do log.
func _resync() -> void:
	_resyncing = true
	hud.log_line("[color=#e94]Ressincronizando com o servidor...[/color]")
	Net.request_sync()


func _on_room_changed() -> void:
	if _resyncing:
		Session.go(Session.GAME)
	elif Session.campaign.in_progress.is_empty() and _incoming.is_empty() and not _pumping and state.outcome() == "":
		# Alguém abandonou a quest.
		Session.go(Session.HUB)


## Campanha: grava a partida em andamento (o fim da quest limpa em Session.finish_quest).
func _autosave() -> void:
	if Session.campaign == null or Session.online:
		return
	Session.campaign.in_progress = quest_match.to_dict()
	Session.campaign.save(Session.save_path)


func _play(event: Dictionary) -> void:
	if event.has("escaped") and event.type != "move":
		await _play_escape(event.escaped)
	match event.type:
		"turn_started":
			var unit: Unit = event.unit
			for fig: FigureView in figures.values():
				fig.set_active(fig.unit == unit)
			rig.focus(BoardView.cell_center(unit.pos))
			if event.has("schools"):
				hud.close_intro()
				hud.close_schools()
				var names: Dictionary = GameData.module("spells").schools
				hud.log_line("Escolas: Elfo com %s; Mago com o resto." % names[event.schools.elf])
			_log_skipped(event)
			var player := " (%s)" % Net.controller_name(unit.def_id) if Session.online and not unit.escort else ""
			hud.log_line("Rodada %d — vez do [b]%s[/b]%s." % [event.round, unit.name, player])
		"movement_roll":
			var values: Array = event.values
			await dice_tray.roll_d6(BoardView.cell_center(event.unit.pos), values)
			hud.log_line("%s rola %s = [b]%d[/b] de movimento." % [event.unit.name, " + ".join(values.map(func(v: int) -> String: return str(v))), event.total])
		"move":
			await figures[event.unit].walk(event.path)
			if event.has("trap"):
				await _play_trap(event.unit, event.trap)
			if event.has("ambush"):
				await _play_ambush(event.ambush)
			if event.has("escaped"):
				await _play_escape(event.escaped)
		"jump":
			await _play_jump(event)
		"door_opened":
			Sfx.play("door")
			await board_view.open_door(event.a, event.b)
			hud.log_line("%s abre a porta." % event.unit.name)
		"fake_door":
			await board_view.shake_door(event.a, event.b)
			hud.log_line("%s tenta abrir a porta: é falsa!" % event.unit.name)
		"quest_complete":
			Sfx.play("victory")
			hud.log_line("[color=#fd6][b]Vitória![/b] Os heróis cumpriram a quest.[/color]")
			_finish(true)
		"attack":
			await _play_attack(event)
		"search_traps":
			await _play_search_traps(event)
		"search_treasure":
			await _play_search_treasure(event)
		"disarm":
			await _play_disarm(event)
		"item_used":
			await _play_item(event)
		"spell":
			await _play_spell(event)
		"turn_lost":
			_log_skipped({"skipped": [event]})
		"zargon_phase":
			_log_skipped(event)
			_start_zargon()
		"zargon_turn":
			await _play_zargon_turn(event)
		"heroes_defeated":
			Sfx.play("defeat")
			if state.objective.get("type") == "escort" and state.units.any(func(u: Unit) -> bool: return u.escort and not u.is_alive()):
				hud.log_line("[color=#c66]O prisioneiro morreu. A quest falhou.[/color]")
			else:
				hud.log_line("[color=#c66]Todos os heróis caíram. Zargon venceu.[/color]")
			_finish(false)
	if event.has("revealed"):
		await _play_reveal(event)


## Tira a névoa, faz surgir os monstros revelados e avisa no log.
func _play_reveal(event: Dictionary) -> void:
	if event.has("rescue"):
		await _play_rescue(event.rescue)
	board_view.reveal(event.revealed, state.revealed)
	for unit: Unit in figures:
		var fig: FigureView = figures[unit]
		if not fig.visible and state.revealed.has(unit.pos):
			fig.appear()
	var alerted: Array = event.get("alerted", [])
	if not alerted.is_empty():
		var names: Array = alerted.map(func(u: Unit) -> String: return u.name)
		hud.log_line("[color=#e94]Avistado: %s![/color]" % ", ".join(names))
		# Carta do monstro na primeira vez que o tipo aparece na quest.
		for unit: Unit in alerted:
			if not _cards_shown.has(unit.def_id):
				_cards_shown[unit.def_id] = true
				var def := GameData.monster(unit.def_id).duplicate()
				def.name = unit.name
				hud.show_card(unit.name, "", def, "monster")
				break
		await get_tree().create_timer(0.3).timeout


func _play_jump(event: Dictionary) -> void:
	var hero: Unit = event.unit
	var faces: Array[String] = event.faces
	await dice_tray.roll_combat(BoardView.cell_center(event.pit), faces, [] as Array[String], true)
	if event.success:
		hud.log_line("%s salta o fosso!" % hero.name)
		await figures[hero].hop_to(event.target)
	else:
		hud.log_line("[color=#e94]%s escorrega e cai no fosso: 1 de dano.[/color]" % hero.name)
		var path: Array[Vector2i] = [event.pit]
		await figures[hero].walk(path)
		await _play_damage(hero, event.damage, event)


## Prisioneiro achado: ele vira aliado, o alarme soa e todas as portas abrem.
func _play_rescue(rescue: Dictionary) -> void:
	var ally: Unit = rescue.ally
	var fig := _add_figure(ally)
	fig.visible = false
	rig.focus(BoardView.cell_center(ally.pos))
	await fig.appear()
	Sfx.play("trap")
	rig.shake(0.08)
	hud.show_card(ally.name, rescue.text)
	hud.log_line("[color=#fd6][b]%s encontrou %s![/b][/color] %s" % [rescue.rescuer.name, ally.name, rescue.text])
	for pair: Array in rescue.doors:
		board_view.open_door(pair[0], pair[1])
	Sfx.play("door")
	await get_tree().create_timer(0.5).timeout


## Monstro que desperta quando um herói entra na sala (Rei Bruxo).
func _play_ambush(ambush: Dictionary) -> void:
	var monster: Unit = ambush.monster
	var fig := _add_figure(monster)
	fig.visible = false
	rig.focus(BoardView.cell_center(monster.pos))
	Sfx.play("trap")
	await fig.appear()
	if ambush.text != "":
		hud.show_card(monster.name, ambush.text)
	hud.log_line("[color=#e94][b]%s desperta![/b] %s[/color]" % [monster.name, ambush.text])
	await get_tree().create_timer(0.6).timeout


## Item da quest que o monstro carregava (Estrela do Oeste).
func _log_carried(dead: Unit, carried: Dictionary) -> void:
	var item: Dictionary = carried.item
	if carried.to == null:
		hud.log_line("%s deixa cair: [b]%s[/b]. Procurem tesouro na sala para achá-lo." % [dead.name, item.name])
		return
	var hero: Unit = carried.to
	hud.show_card(item.name, item.get("text", ""))
	hud.log_line("%s pega [b]%s[/b]. %s" % [hero.name, item.name, item.get("text", "")])
	if int(item.get("gold", 0)) > 0:
		Sfx.play("coin")
	if item.get("objective_item", false):
		hud.log_line("[color=#fd6][b]Objetivo cumprido![/b] Voltem à escada.[/color]")


## Fim da quest: anota na campanha (se houver) e mostra o resumo.
func _finish(victory: bool) -> void:
	var report := Session.finish_quest(state, _campaign_at_start)
	var lines: Array[String] = []
	for unit in state.units:
		if unit.is_hero() and unit.is_alive():
			lines.append("%s: %d de ouro" % [unit.name, unit.gold])
	for name: String in report.get("fallen", []):
		lines.append("%s caiu e recomeça do zero." % name)
	for name: String in report.get("champions", []):
		lines.append("%s virou Campeão: +%d de ouro!" % [name, Campaign.CHAMPION_BONUS])
	var to_hub := Session.campaign != null
	hud.show_game_over(victory, "\n".join(lines), "Voltar à campanha" if to_hub else "Menu",
		func() -> void: Session.go(Session.HUB if to_hub else Session.MENU))


## Herói chega à escada com o objetivo cumprido e desce (sai do tabuleiro).
## Em "move" isso vem depois da caminhada.
func _play_escape(unit: Unit) -> void:
	var fig: FigureView = figures.get(unit)
	if fig == null:
		return
	hud.log_line("[color=#fd6]%s desce a escada e sai da masmorra.[/color]" % unit.name)
	if unit.escort and state.is_objective_done():
		hud.log_line("[color=#fd6][b]%s está a salvo![/b] Agora voltem todos à escada.[/color]" % unit.name)
	if state.rescuer != null and unit.escort and state.rescue_reward > 0 and state.rescuer.is_alive():
		Sfx.play("coin")
		hud.log_line("%s recebe %d moedas de ouro pelo resgate." % [state.rescuer.name, state.rescue_reward])
	figures.erase(unit)
	await fig.leave()


func _start_zargon() -> void:
	for fig: FigureView in figures.values():
		fig.set_active(false)
	hud.log_line("[color=#c66]Vez de Zargon.[/color]")
	_refresh_hud()


## Um monstro joga (o Match já decidiu); a câmera acompanha.
func _play_zargon_turn(turn: Dictionary) -> void:
	var monster: Unit = turn.unit
	var fig: FigureView = figures.get(monster)
	if fig != null:
		fig.set_active(true)
		var events: Array = turn.events
		var first: Dictionary = events[0]
		rig.focus(BoardView.cell_center(first.get("from", monster.pos)))
	for ev: Dictionary in turn.events:
		await _play(ev)
	if is_instance_valid(fig):
		fig.set_active(false)
	_refresh_hud()


func _play_attack(event: Dictionary) -> void:
	var attacker: Unit = event.attacker
	var defender: Unit = event.defender
	var shield := "escudos brancos" if defender.is_hero() else "escudos pretos"
	await figures[attacker].lunge(BoardView.cell_center(defender.pos))
	var mid: Vector3 = (figures[attacker].position + figures[defender].position) / 2.0
	await dice_tray.roll_combat(mid, event.attack_faces, event.defend_faces, defender.is_hero())
	hud.log_line("%s ataca %s: %d caveira(s) × %d %s → [b]%d de dano[/b]." % [
		attacker.name, defender.name, event.hits, event.blocks, shield, event.damage])
	if event.get("immune", false) and figures.has(defender):
		Sfx.play("block")
		figures[defender].float_text("Imune", Color(0.75, 0.6, 1.0))
		hud.log_line("[color=#b9f]%s não é ferido: só a Lâmina Espiritual pode feri-lo.[/color]" % defender.name)
	elif event.damage == 0 and figures.has(defender):
		Sfx.play("block")
		figures[defender].float_text("Errou" if event.hits == 0 else "Defendeu", Color(0.85, 0.85, 0.9))
	await _play_damage(defender, event.damage, event)


## Dano já aplicado pela regra: pisca, salva com poção ou derruba a figura.
func _play_damage(unit: Unit, damage: int, event: Dictionary) -> void:
	var fig: FigureView = figures.get(unit)
	if fig == null:
		return
	# Monstro atingido: a ficha dele aparece com o Corpo de antes do golpe e o
	# risco do dano é traçado junto com o número que sobe da figura.
	if not unit.is_hero():
		hud.show_monster(unit, _status_text(unit), mini(unit.body + damage, unit.body_max))
	if damage > 0:
		Sfx.play("hit")
		fig.float_text("-%d" % damage, Color(1.0, 0.3, 0.25))
		if not unit.is_hero():
			hud.show_monster(unit, _status_text(unit))
		if damage >= 2:
			rig.shake()
		await fig.flash_hit()
	if event.has("saved_by_potion"):
		hud.log_line("[color=#6c6]%s bebe a Poção de Cura no último instante (+%d)![/color]" % [unit.name, event.saved_by_potion])
		Sfx.play("heal")
		fig.float_text("+%d" % event.saved_by_potion, Color(0.4, 1.0, 0.5))
		await fig.flash_heal()
	if not unit.is_alive():
		hud.log_line("[color=#c66]%s %s![/color]" % [unit.name, "caiu" if unit.is_hero() else "morreu"])
		if unit.is_objective and state.is_objective_done():
			hud.log_line("[color=#fd6][b]Objetivo cumprido![/b] Voltem à escada.[/color]")
		if event.has("carried"):
			_log_carried(unit, event.carried)
		if event.has("loot"):
			var loot: Dictionary = event.loot
			if loot.to != null:
				hud.log_line("%s recolhe os pertences de %s (%d de ouro, %d item(ns))." % [loot.to.name, unit.name, loot.gold, loot.items])
			elif loot.gold > 0 or loot.items > 0:
				hud.log_line("Ninguém por perto: os monstros ficam com os pertences de %s." % unit.name)
		figures.erase(unit)
		Sfx.play("death")
		await fig.die()


func _play_trap(unit: Unit, trap: Dictionary) -> void:
	hud.log_line("[color=#e94]%s dispara uma armadilha: %s![/color]" % [unit.name, TRAP_NAMES.get(trap.id, trap.id)])
	Sfx.play("trap")
	rig.shake(0.08)
	var faces: Array[String] = trap.faces
	if not faces.is_empty():
		await dice_tray.roll_combat(BoardView.cell_center(trap.cell), faces, [] as Array[String], true)
	match trap.id:
		"pit":
			board_view.show_trap(trap.cell, "pit")
		"falling_block":
			await board_view.drop_block(trap.cell)
			if trap.has("pushed_to"):
				var back: Array[Vector2i] = [trap.pushed_to]
				await figures[unit].walk(back)
	hud.log_line("%s sofre [b]%d de dano[/b]." % [unit.name, trap.damage])
	await _play_damage(unit, trap.damage, trap)


func _play_search_traps(event: Dictionary) -> void:
	var hero: Unit = event.unit
	if event.traps.is_empty() and event.doors.is_empty():
		hud.log_line("%s procura armadilhas e portas secretas: nada." % hero.name)
		return
	for found: Dictionary in event.traps:
		if found.disarmed:
			hud.log_line("%s acha e desarma uma armadilha: %s." % [hero.name, TRAP_NAMES.get(found.id, found.id)])
		else:
			hud.log_line("%s acha uma armadilha: %s." % [hero.name, TRAP_NAMES.get(found.id, found.id)])
			board_view.show_trap(found.cell, found.id)
	for pair: Array in event.doors:
		hud.log_line("[color=#6cf]%s acha uma porta secreta![/color]" % hero.name)
		await board_view.reveal_secret_door(pair[0], pair[1])


func _play_search_treasure(event: Dictionary) -> void:
	var hero: Unit = event.unit
	if event.has("chest_trap"):
		var chest: Dictionary = event.chest_trap
		hud.show_card("Armadilha!", chest.text if chest.text != "" else "O baú estava armado.")
		hud.log_line("[color=#e94]O baú tinha armadilha: %d de dano.[/color]" % chest.damage)
		await _play_damage(hero, chest.damage, event)
		if not hero.is_alive():
			return
	var card: Dictionary = event.card
	if event.has("artifact"):
		var artifact: Dictionary = event.artifact
		hud.show_card(artifact.name, artifact.get("text", ""), artifact, "artifact")
		hud.log_line("%s acha o artefato [b]%s[/b]! %s" % [hero.name, artifact.name, artifact.get("text", "")])
	else:
		hud.show_card(card.name, _card_text(card, event), card)
	hud.log_line("%s procura tesouro: [b]%s[/b]. %s" % [hero.name, card.name, _card_text(card, event)])
	if event.get("gold", 0) > 0:
		Sfx.play("coin")
	if event.get("objective", false):
		hud.log_line("[color=#fd6][b]Objetivo cumprido![/b] Voltem à escada.[/color]")
	# Se ainda vem algo (armadilha, monstro errante), espera a carta virar e
	# sair do meio da tela.
	var follow_up: bool = event.has("trap_damage") or not event.get("wandering", {}).is_empty()
	await get_tree().create_timer(1.0 + Hud.CARD_GLANCE if follow_up else 0.6).timeout
	if event.has("trap_damage"):
		if event.has("pit"):
			board_view.show_trap(event.pit, "pit")
		await _play_damage(hero, event.trap_damage, event)
	if event.has("wandering") and not event.wandering.is_empty():
		var monster: Unit = event.wandering.monster
		var fig := _add_figure(monster)
		await fig.appear()
		await _play_attack(event.wandering.attack)


func _play_disarm(event: Dictionary) -> void:
	var hero: Unit = event.unit
	var faces: Array[String] = event.faces
	if not faces.is_empty():
		await dice_tray.roll_combat(BoardView.cell_center(event.cell), faces, [] as Array[String], true)
	if event.success:
		board_view.remove_trap(event.cell)
		hud.log_line("%s desarma a armadilha." % hero.name)
	else:
		hud.log_line("[color=#e94]%s falha e dispara a armadilha: 1 de dano.[/color]" % hero.name)
		await _play_damage(hero, event.damage, event)


func _play_item(event: Dictionary) -> void:
	var hero: Unit = event.unit
	if event.has("destroyed"):
		var target: Unit = event.destroyed
		hud.log_line("%s joga Água Benta em %s!" % [hero.name, target.name])
		await _play_damage(target, 1, {})
		return
	hud.log_line("%s usa %s." % [hero.name, event.card.name])
	if event.get("healed", 0) > 0:
		hud.log_line("[color=#6c6]+%d de Corpo.[/color]" % event.healed)
		await figures[hero].flash_heal()


func _play_spell(event: Dictionary) -> void:
	var caster: Unit = event.caster
	var spell: Dictionary = event.spell
	var target: Variant = event.target
	var target_pos: Vector3
	var target_name := ""
	if target is Array:
		target_pos = (BoardView.cell_center(target[0]) + BoardView.cell_center(target[1])) / 2.0
		target_name = "uma porta"
	else:
		var unit: Unit = target
		target_pos = figures[unit].position if figures.has(unit) else BoardView.cell_center(unit.pos)
		target_name = "si mesmo" if unit == caster else unit.name
	hud.log_line("%s lança [b]%s[/b] em %s." % [caster.name, spell.name_pt, target_name])
	hud.show_card(spell.name_pt, spell.get("text", ""), spell, GameCard.spell_kind(spell))
	Sfx.play("spell")
	# A carta se mostra no meio e vai para o canto; o feitiço sai depois.
	await get_tree().create_timer(Hud.CARD_GLANCE).timeout
	await _cast_orb(figures[caster].position, target_pos, Hud.SCHOOL_COLORS.get(spell.school, Color.WHITE))
	if event.has("door"):
		await board_view.open_door(event.door[0], event.door[1])
		hud.log_line("O Gênio escancara a porta.")
	elif event.has("attack"):
		var attack: Dictionary = event.attack
		await dice_tray.roll_combat(target_pos, attack.attack_faces, attack.defend_faces, attack.defender.is_hero())
		hud.log_line("O Gênio ataca %s: %d caveira(s) × %d escudo(s) → [b]%d de dano[/b]." % [
			attack.defender.name, attack.hits, attack.blocks, attack.damage])
		await _play_damage(attack.defender, attack.damage, attack)
	elif event.has("damage"):
		var resist: Array = event.resist
		var base := int(spell.effect.damage)
		if not resist.is_empty():
			# Quem rola é o alvo: cada 5 ou 6 tira 1 do dano do feitiço.
			hud.log_line("%s rola para resistir: %s → %d − %d = [b]%d de dano[/b]." % [target_name,
				", ".join(resist.map(func(v: int) -> String: return str(v))), base, base - event.damage, event.damage])
			await dice_tray.roll_d6(target_pos, resist, 5)
		else:
			hud.log_line("%s sofre [b]%d de dano[/b]." % [target_name, event.damage])
		if event.damage == 0 and figures.has(target):
			Sfx.play("block")
			figures[target].float_text("Resistiu", Color(0.85, 0.85, 0.9))
		await _play_damage(target, event.damage, event)
	elif event.has("healed"):
		hud.log_line("[color=#6c6]%s recupera %d de Corpo.[/color]" % [target.name, event.healed])
		Sfx.play("heal")
		figures[target].float_text("+%d" % event.healed, Color(0.4, 1.0, 0.5))
		await figures[target].flash_heal()
	elif event.has("hits"):
		for hit: Dictionary in event.hits:
			var unit: Unit = hit.unit
			if hit.damage > 0:
				hud.log_line("%s sofre [b]%d de dano[/b]." % [unit.name, hit.damage])
				await _play_damage(unit, hit.damage, hit)
			else:
				hud.log_line("%s fica paralisado." % unit.name)
	elif event.has("summoned"):
		var summoned: Array = event.summoned
		hud.log_line("[color=#c6f]%d monstro(s) surgem do nada![/color]" % summoned.size())
		for monster: Unit in summoned:
			_add_figure(monster).appear()
		await get_tree().create_timer(0.35).timeout
	elif SPELL_EFFECTS.has(spell.id):
		hud.log_line(SPELL_EFFECTS[spell.id] % target.name)


## Esfera brilhante que voa do conjurador até o alvo e estoura.
func _cast_orb(from: Vector3, to: Vector3, color: Color) -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb.material_override = mat
	orb.position = from + Vector3(0, 0.9, 0)
	add_child(orb)
	var tween := create_tween()
	tween.tween_property(orb, "position", to + Vector3(0, 0.7, 0), maxf(0.15, from.distance_to(to) * 0.06))
	tween.tween_property(orb, "scale", Vector3.ONE * 3.0, 0.2)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.2)
	await tween.finished
	orb.queue_free()


## Heróis/monstros que perderam a vez (Tempestade ou sono).
func _log_skipped(event: Dictionary) -> void:
	for lost: Dictionary in event.get("skipped", []):
		var unit: Unit = lost.unit
		var rolls: Array = lost.get("rolls", [])
		var rolled := ", ".join(rolls.map(func(v: int) -> String: return str(v)))
		match lost.reason:
			"asleep":
				hud.log_line("%s dorme e perde a vez (rolou %s, precisava de um 6)." % [unit.name, rolled])
			"paralyzed":
				hud.log_line("%s segue paralisado pela Nuvem do Caos (rolou %s)." % [unit.name, rolled])
			"commanded":
				hud.log_line("%s está sob o Comando de Zargon e perde a vez (rolou %s)." % [unit.name, rolled])
			_:
				hud.log_line("%s está preso na Tempestade e perde a vez." % unit.name)


## Alvo do feitiço pendente no quadrado clicado (Unit ou porta [a, b]), ou null.
func _spell_target_at(cell: Vector2i) -> Variant:
	for target: Variant in Magic.targets(state, state.active, _pending_spell):
		if target is Unit and target.pos == cell:
			return target
		if target is Array and _door_mark_cell(target) == cell:
			return target
	return null


## Para mirar numa porta, marca-se o quadrado do outro lado (o escondido).
func _door_mark_cell(pair: Array) -> Vector2i:
	return pair[1] if state.revealed.has(pair[0]) else pair[0]


func _status_text(unit: Unit) -> String:
	var parts: Array[String] = []
	if unit.status.get("paralyzed", false):
		parts.append("paralisado")
	elif unit.status.get("asleep", false):
		parts.append("dormindo")
	if unit.status.get("commanded", false):
		parts.append("sob comando")
	if unit.status.has("skip_turns"):
		parts.append("tempestade")
	if unit.status.has("rock_skin"):
		parts.append("pele de pedra")
	if unit.buffs.has("through_walls"):
		parts.append("atravessa paredes")
	if unit.buffs.has("pass_monsters"):
		parts.append("véu de névoa")
	if unit.buffs.has("move_mult"):
		parts.append("vento veloz")
	if unit.buffs.has("attack"):
		parts.append("+%d ataque" % unit.buffs.attack)
	if unit.buffs.has("defend"):
		parts.append("+%d defesa" % unit.buffs.defend)
	if unit.in_pit:
		parts.append("no fosso")
	return ", ".join(parts)


## Texto curto da carta de tesouro.
func _card_text(card: Dictionary, event: Dictionary) -> String:
	if card.get("text", "") != "":
		return card.text
	if event.has("gold") and event.gold > 0:
		return "%d moedas de ouro." % event.gold
	if card.has("potion"):
		return "Guardada no inventário."
	if card.has("item"):
		return "Destrói um morto-vivo colado em você."
	if card.has("trap"):
		return "Armadilha! %d de dano." % int(card.trap.damage)
	if card.get("wandering_monster", false):
		return "Um monstro errante ataca!"
	return "Nada aqui."


# ---------- entrada ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_under(event.position)
		if cell != _hover:
			_hover = cell
			_refresh_marks()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_under(event.position)
		if state.board.in_bounds(cell):
			_inspect(cell)
			click_cell(cell)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				roll_movement()
			KEY_T:
				search_treasure()
			KEY_F:
				search_traps()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_ESCAPE:
				_pending_spell = ""
				hud.hide_monster()
				_refresh()


## Clique num monstro à vista abre a ficha dele (a qualquer hora, até na vez
## de outro jogador); se dá para atacar, o click_cell ataca em seguida.
func _inspect(cell: Vector2i) -> void:
	var unit := state.unit_at(cell)
	if unit != null and not unit.is_hero() and state.revealed.has(cell):
		hud.show_monster(unit, _status_text(unit))


func _cell_under(screen_pos: Vector2) -> Vector2i:
	var point: Variant = rig.floor_point(screen_pos)
	if point == null:
		return Vector2i(-1, -1)
	return Vector2i(floori(point.x), floori(point.z))


# ---------- tela ----------

func _refresh() -> void:
	_refresh_marks()
	_refresh_hud()


func _refresh_hud() -> void:
	# Online, na vez do herói de outro jogador, os botões ficam apagados.
	hud.refresh(state, busy or (Session.online and not _can_input()), _pending_spell)
	# Fora da animação, a ficha do monstro acompanha o estado (sono etc.); some
	# se a partida foi refeita (sync) e ele não existe mais.
	var shown := hud.shown_monster()
	if shown != null and not state.units.has(shown):
		hud.hide_monster()
	elif shown != null and not busy:
		hud.show_monster(shown, _status_text(shown))
	for unit: Unit in figures:
		figures[unit].show_status(_status_text(unit))


func _refresh_marks() -> void:
	var marks := {}
	_flood = {}
	var hero := state.active
	if not busy and _can_input() and _pending_spell != "":
		for unit: Unit in Magic.out_of_sight(state, hero, _pending_spell):
			marks[unit.pos] = "spell_out"
		for target: Variant in Magic.targets(state, hero, _pending_spell):
			marks[target.pos if target is Unit else _door_mark_cell(target)] = "spell"
	elif not busy and _can_input():
		if state.can_move() and not state.needs_movement_roll():
			_flood = state.flood_for(hero, state.move_left)
			for cell in Pathfinder.destinations(_flood):
				marks[cell] = "reach"
			for cell in Pathfinder.path_to(_flood, _hover):
				marks[cell] = "path"
		if state.can_act():
			for monster in state.alive(Unit.Side.MONSTER):
				if state.revealed.has(monster.pos) and Combat.can_attack(state, hero, monster):
					marks[monster.pos] = "target"
			for dir in Board.DIRS:
				if Exploration.can_disarm(state, hero.pos + dir):
					marks[hero.pos + dir] = "disarm"
		for dir in Board.DIRS:
			if state.can_jump(hero.pos + dir * 2) and not _flood.has(hero.pos + dir * 2):
				marks[hero.pos + dir * 2] = "jump"
		for pair: Array in state.closed_doors_next_to(hero.pos):
			marks[pair[1]] = "door"
	board_view.set_marks(marks)


# ---------- construção ----------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.01, 0.015)
	# Masmorra escura: pouca luz ambiente fria; quem ilumina são as tochas dos
	# heróis (FigureView) e a lareira.
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.32, 0.35, 0.48)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.ssao_enabled = true
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_color = Color(0.55, 0.62, 0.85)
	sun.light_energy = 0.22
	sun.shadow_enabled = true
	add_child(sun)

	board_view = BoardView.new()
	add_child(board_view)
	board_view.build(state)
	for cell: Vector2i in state.traps:
		if state.traps[cell].known:
			board_view.show_trap(cell, state.traps[cell].id)
	for unit in state.units:
		if unit.is_alive() and not unit.escaped:
			_add_figure(unit)

	rig = CameraRig.new()
	rig.bounds = Rect2(0, 0, state.board.width, state.board.height)
	add_child(rig)
	dice_tray = DiceTray.new()
	dice_tray.camera = rig.camera
	dice_tray.scene_root = self
	dice_tray.bounds = Rect2(0, 0, state.board.width, state.board.height)
	add_child(dice_tray)
	rig.focus(Vector3(state.board.width / 2.0, 0, state.board.height / 2.0), true)


## Monstros nascem escondidos até o quadrado ser revelado.
func _add_figure(unit: Unit) -> FigureView:
	var fig := FigureView.new()
	add_child(fig)
	fig.setup(unit)
	fig.visible = unit.is_hero() or state.revealed.has(unit.pos) or (Session.preview and not Session.online)
	figures[unit] = fig
	return fig
