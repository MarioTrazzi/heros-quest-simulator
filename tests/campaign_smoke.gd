extends Node
## Smoke do fluxo de campanha, sem mexer no save do jogador:
##   godot --headless --path . res://tests/campaign_smoke.tscn
## menu → nova campanha → armeria → quest (vitória forçada) → campanha salva.
## Sai com código ≠ 0 se falhar.

const SAVE := "user://smoke_campaign.json"
const MAX_WAIT_MS := 20000

var _failures := 0


func _ready() -> void:
	Session.preview = false  # os testes contam com a névoa e o bloqueio das quests
	Engine.time_scale = 4.0
	OS.set_environment("HQ_SEED", "3")
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Session.save_path = SAVE
	Session.host = self

	Session.go(Session.MENU)
	await _frames(2)
	var menu := Session.current_screen()
	_check(menu != null and menu.has_method("new_campaign"), "menu abre")
	menu.new_campaign()
	await _frames(2)
	var hub := Session.current_screen()
	_check(hub.has_method("buy") and Campaign.has_save(SAVE), "nova campanha grava e abre a tela da campanha")

	var campaign: Campaign = Session.campaign
	campaign.hero("barbarian").gold = 200
	_check(hub.buy("barbarian", "helmet") == "" and campaign.hero("barbarian").gold == 80, "compra o elmo na armeria")
	_check(hub.buy("wizard", "broadsword") != "", "armeria recusa o que o Mago não usa")
	_check(Campaign.load_from(SAVE).hero("barbarian").equipment.has("helmet"), "compra fica gravada")

	hub.play("barak_tor")
	await _frames(2)
	_check(Session.current_screen() == hub or Session.quest_id != "barak_tor", "quest bloqueada não abre")
	hub.play("sandbox")
	await _frames(2)
	var game := Session.current_screen()
	_check(game.has_method("choose_schools"), "quest abre")
	await game.choose_schools("fire", "water")
	await _idle(game)
	var state: GameState = game.state
	var barbarian: Unit = state.alive(Unit.Side.HERO)[0]
	_check(barbarian.defend == 3 and barbarian.has_equipment("helmet"), "herói entra com o elmo comprado")

	# Pausa no meio: joga um pouco, sai, e a quest continua igual.
	await game.roll_movement()
	await _idle(game)
	for i in 4:
		await game.end_turn()
		await _idle(game)
	var hash_before: String = game.quest_match.state_hash()
	var round_before := state.round_number
	_check(Campaign.load_from(SAVE).in_progress.get("quest_id") == "sandbox", "partida em andamento gravada")
	game.leave()
	await _frames(2)
	hub = Session.current_screen()
	_check(hub.buy("barbarian", "shield") != "", "armeria fechada com quest em andamento")
	hub.play("sandbox")
	await _frames(2)
	game = Session.current_screen()
	await _idle(game)
	state = game.state
	_check(game.quest_match.state_hash() == hash_before and state.round_number == round_before, "quest continua de onde parou")
	_check(game.figures.size() == state.units.filter(func(u: Unit) -> bool: return u.is_alive() and not u.escaped).size(), "miniaturas das figuras vivas")
	barbarian = state.alive(Unit.Side.HERO)[0]

	# Vitória forçada: Feiticeiro morto, todos saem pela escada, dando 75 de ouro ao Bárbaro.
	for u in state.units:
		if u.is_objective:
			u.body = 0
	barbarian.gold += 75
	for h in state.alive(Unit.Side.HERO):
		h.escaped = true
	await game.end_turn()
	await _idle(game)
	_check(campaign.completed.has("sandbox") and campaign.next_quest() == "the_trial", "vitória anotada na campanha")
	var saved := Campaign.load_from(SAVE)
	_check(saved.completed.has("sandbox") and saved.hero("barbarian").gold == 155, "campanha gravada com o ouro (%d)" % saved.hero("barbarian").gold)
	_check(game.hud._game_over.visible, "painel de vitória aparece")
	_check(saved.in_progress.is_empty(), "fim da quest limpa a partida em andamento")

	game.hud._game_over_button.pressed.emit()
	await _frames(2)
	hub = Session.current_screen()
	_check(hub.has_method("buy"), "volta para a tela da campanha")

	Session.host = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Sfx.stop_all()
	await get_tree().create_timer(0.1, true, false, true).timeout
	print("CAMPANHA %s (%d falhas)" % ["OK" if _failures == 0 else "FALHOU", _failures])
	get_tree().quit(1 if _failures else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _idle(game: Node) -> void:
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MS
	while game.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(not game.busy, "animação travada")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("✗ ", what)
