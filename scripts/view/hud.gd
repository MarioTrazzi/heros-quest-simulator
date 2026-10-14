class_name Hud
extends CanvasLayer
## Interface 2D da partida: botões de ação (embaixo, no centro), ficha do
## herói da vez e grupo (alto à direita), objetivo (alto à esquerda),
## log pequeno (embaixo à direita), carta de tesouro (aparece no alto) e o
## aviso de fim da quest. Só mostra; quem age é o
## game.gd, pelos Callables passados em setup().

## Cor de cada escola (botões e o brilho do feitiço no tabuleiro).
## Largura das cartas da mão e o espaço que a mão pode ocupar.
const HAND_CARD := 84
const HAND_WIDTH := 450
## Carta grande (tesouro, feitiço, monstro): tempo no centro antes de ir para
## o canto, e o tamanho que fica lá.
const CARD_GLANCE := 0.7
const CARD_ASIDE_SCALE := 0.55

const SCHOOL_COLORS := {
	"air": Color(0.85, 0.90, 1.0),
	"fire": Color(1.0, 0.45, 0.15),
	"water": Color(0.25, 0.55, 1.0),
	"earth": Color(0.55, 0.40, 0.20),
	"chaos": Color(0.65, 0.20, 0.85),
}

var _title: Label
var _objective: Label
var _sheet: HeroSheet
var _monster_sheet: HeroSheet
var _monster: Unit
var _stats: Label
var _roll: Button
var _end: Button
var _treasure: Button
var _traps: Button
var _items: HBoxContainer
var _spells: HBoxContainer
var _schools: PanelContainer
var _party: Label
var _log: RichTextLabel
var _card: PanelContainer
var _card_title: Label
var _card_text: Label
var _card_tween: Tween
var _popup_card: GameCard
var _popup_back: GameCard
var _intro: PanelContainer
var _game_over: PanelContainer
var _game_over_title: Label
var _game_over_details: Label
var _game_over_button: Button
var _use_item: Callable
var _select_spell: Callable


## actions: {"roll", "end", "treasure", "traps", "use_item"(índice), "select_spell"(id), "leave"}.
func setup(actions: Dictionary) -> void:
	_use_item = actions.use_item
	_select_spell = actions.select_spell
	# Objetivo: uma linha discreta no alto, à esquerda.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style(0.55, 8))
	top.position = Vector2(12, 12)
	add_child(top)
	_objective = Label.new()
	_objective.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_objective.add_theme_font_size_override("font_size", 14)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(420, 0)
	top.add_child(_objective)

	# Alto à direita: ficha do herói da vez e, embaixo dela, o grupo; à
	# esquerda dela, a ficha do monstro clicado (frente a frente).
	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_left = -12
	top_right.offset_right = -12
	top_right.offset_top = 12
	top_right.add_theme_constant_override("separation", 8)
	add_child(top_right)
	_monster_sheet = HeroSheet.create(true, 200)
	_monster_sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_monster_sheet.visible = false
	_monster_sheet.clickable = true
	_monster_sheet.set_card_tooltip("Clique para fechar.")
	_monster_sheet.pressed.connect(hide_monster)
	top_right.add_child(_monster_sheet)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_right.add_child(right)
	_sheet = HeroSheet.create(true)
	_sheet.size_flags_horizontal = Control.SIZE_SHRINK_END
	_sheet.visible = false
	right.add_child(_sheet)
	var party_panel := PanelContainer.new()
	party_panel.add_theme_stylebox_override("panel", _panel_style(0.55, 8))
	party_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(party_panel)
	_party = Label.new()
	_party.add_theme_font_size_override("font_size", 13)
	party_panel.add_child(_party)

	# Embaixo, no centro: os botões do herói da vez.
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel_style(0.75, 8))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -10
	add_child(bottom)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(330, 0)
	bottom.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_stats)
	var row1 := HBoxContainer.new()
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row1)
	_roll = _button("Rolar (R)", actions.roll)
	_roll.tooltip_text = "Rolar os dados de movimento."
	row1.add_child(_roll)
	_end = _button("Encerrar (Espaço)", actions.end)
	_end.tooltip_text = "Encerrar o turno."
	row1.add_child(_end)
	var leave := _button("Sair", actions.leave)
	leave.tooltip_text = "Volta sem cumprir a quest (em campanha, a partida fica gravada para continuar)."
	row1.add_child(leave)
	var help := _button("?", func() -> void: pass)
	help.tooltip_text = "Azul: andar · Vermelho: atacar · Verde: abrir porta · Laranja: desarmar · Roxo: feitiço · Lima: pular fosso\nEsc: cancelar feitiço · Botão direito: girar · Meio/WASD: mover · Roda: zoom"
	row1.add_child(help)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row2)
	_treasure = _button("Tesouro (T)", actions.treasure)
	_treasure.tooltip_text = "Procurar tesouro."
	row2.add_child(_treasure)
	_traps = _button("Armadilhas (F)", actions.traps)
	_traps.tooltip_text = "Procurar armadilhas e portas secretas."
	row2.add_child(_traps)

	_card = PanelContainer.new()
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 90
	_card.custom_minimum_size = Vector2(340, 0)
	_card.visible = false
	add_child(_card)
	var card_box := VBoxContainer.new()
	_card.add_child(card_box)
	_card_title = Label.new()
	_card_title.add_theme_font_size_override("font_size", 24)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_box.add_child(_card_title)
	_card_text = Label.new()
	_card_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_box.add_child(_card_text)

	_game_over = PanelContainer.new()
	var over_bg := StyleBoxFlat.new()
	over_bg.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	over_bg.set_content_margin_all(24)
	over_bg.set_corner_radius_all(8)
	_game_over.add_theme_stylebox_override("panel", over_bg)
	_game_over.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_game_over.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_game_over.grow_vertical = Control.GROW_DIRECTION_BOTH
	_game_over.visible = false
	add_child(_game_over)
	var over_box := VBoxContainer.new()
	over_box.add_theme_constant_override("separation", 12)
	_game_over.add_child(over_box)
	_game_over_title = Label.new()
	_game_over_title.add_theme_font_size_override("font_size", 48)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(_game_over_title)
	_game_over_details = Label.new()
	_game_over_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(_game_over_details)
	_game_over_button = Button.new()
	_game_over_button.custom_minimum_size = Vector2(260, 44)
	_game_over_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	over_box.add_child(_game_over_button)

	# Embaixo à esquerda, a "mão" do herói da vez: itens em cima, feitiços embaixo
	# (clique = usar o item / escolher o feitiço).
	var hand := VBoxContainer.new()
	hand.add_theme_constant_override("separation", 8)
	hand.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hand.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hand.offset_left = 12
	hand.offset_bottom = -12
	add_child(hand)
	_items = HBoxContainer.new()
	hand.add_child(_items)
	_spells = HBoxContainer.new()
	hand.add_child(_spells)

	# Log pequeno no canto inferior direito, ao lado da ficha.
	var log_panel := PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", _panel_style(0.6, 6))
	log_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.offset_right = -10
	log_panel.offset_bottom = -10
	add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(280, 150)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_font_size_override("bold_font_size", 12)
	_log.add_theme_font_size_override("italics_font_size", 12)
	log_panel.add_child(_log)


func refresh(state: GameState, busy: bool, pending_spell := "") -> void:
	var lines: Array[String] = []
	var objective: String = state.objective.get("text", "Volte à escada.")
	_objective.text = ("Cumprido: %s Volte à escada." if state.is_objective_done() else "Objetivo: %s") % objective
	for unit in state.units:
		if unit.is_hero():
			var status := "Corpo %d/%d   Ouro %d" % [unit.body, unit.body_max, unit.gold] if unit.is_alive() else "caiu"
			if unit.escaped:
				status = "saiu   Ouro %d" % unit.gold
			lines.append("%s   %s" % [unit.name, status])
	_party.text = "\n".join(lines)

	var hero := state.active
	var hero_turn := hero != null and hero.is_hero()
	for child in _items.get_children() + _spells.get_children():
		child.get_parent().remove_child(child)  # sai já, para _fan contar só as novas
		child.queue_free()
	if not hero_turn:
		_title.text = "Preparação" if state.round_number == 0 else "Rodada %d — Zargon" % state.round_number
		_stats.text = ""
		_sheet.visible = false
		for b in [_roll, _end, _treasure, _traps]:
			b.disabled = true
		return
	_title.text = "Rodada %d — %s" % [state.round_number, hero.name]
	var movement := "rolar (R)" if state.needs_movement_roll() else "restam %d" % state.move_left
	if not state.can_move():
		movement = "encerrado"
	_sheet.visible = true
	_sheet.show_unit(hero, "Ouro %d" % hero.gold)
	_stats.text = "Movimento: %s   Ação: %s%s" % [
		movement, "disponível" if state.can_act() else "usada",
		"   (no fosso: −1 dado)" if hero.in_pit else ""]
	_roll.disabled = busy or not (state.needs_movement_roll() and state.can_move())
	_end.disabled = busy
	_treasure.disabled = busy or not Exploration.can_search_treasure(state)
	_traps.disabled = busy or not Exploration.can_search(state)
	for i in hero.inventory.size():
		var item := GameCard.create(hero.inventory[i], "treasure", HAND_CARD)
		item.disabled = busy
		item.pressed.connect(_use_item.bind(i))
		_items.add_child(item)
	for id in hero.spells:
		var spell := GameData.spell(id)
		var card := GameCard.create(spell, GameCard.spell_kind(spell), HAND_CARD)
		card.disabled = busy or not state.can_act()
		card.selected = id == pending_spell
		card.tooltip_text += "\nEscola: %s (clique e escolha o alvo)" % GameData.module("spells").schools.get(spell.school, spell.school)
		card.pressed.connect(_select_spell.bind(id))
		_spells.add_child(card)
	_fan(_items)
	_fan(_spells)


## Escolha das escolas no começo: o Mago escolhe uma, o Elfo outra, e o Mago
## fica com as duas que sobram. Chama done(escola_do_mago, escola_do_elfo).
func ask_schools(has_wizard: bool, has_elf: bool, done: Callable) -> void:
	_schools = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.10, 0.95)
	bg.set_content_margin_all(16)
	bg.set_corner_radius_all(6)
	_schools.add_theme_stylebox_override("panel", bg)
	_schools.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_schools.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_schools.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_schools)
	var box := VBoxContainer.new()
	_schools.add_child(box)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var names: Dictionary = GameData.module("spells").schools
	var picks := {"wizard": "", "elf": ""}
	# O lambda captura variáveis locais por valor (ao ser criado, "ask" ainda é nulo);
	# guardado num Dictionary, ele consegue chamar a si mesmo para a vez do Elfo.
	var step := {}
	step.ask = func(who: String) -> void:
		for child in row.get_children():
			child.queue_free()
		title.text = "Mago: escolha sua primeira escola de magia" if who == "wizard" else "Elfo: escolha sua escola de magia"
		for school: String in Magic.SCHOOLS:
			if school == picks.wizard:
				continue
			var pick := func() -> void:
				picks[who] = school
				if who == "wizard" and has_elf:
					step.ask.call("elf")
				else:
					_schools.queue_free()
					var elf_school: String = picks.elf
					if elf_school == "":
						elf_school = Magic.SCHOOLS.filter(func(x: String) -> bool: return x != picks.wizard)[0]
					var wizard_school: String = picks.wizard
					if wizard_school == "":
						wizard_school = Magic.SCHOOLS.filter(func(x: String) -> bool: return x != picks.elf)[0]
					done.call(wizard_school, elf_school)
			# Cada escola: as 3 cartas de feitiço (clique escolhe) e o botão.
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 8)
			row.add_child(column)
			var cards := HBoxContainer.new()
			cards.add_theme_constant_override("separation", 4)
			cards.size_flags_vertical = Control.SIZE_EXPAND_FILL  # botões alinhados embaixo
			column.add_child(cards)
			for id: String in Magic.school_spells(school):
				var card := GameCard.create(GameData.spell(id), "spell", 80)
				card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # não estica: fica na proporção
				card.pressed.connect(pick)
				cards.add_child(card)
			var button := _button("Escolher %s" % names[school], pick)
			button.modulate = SCHOOL_COLORS[school].lightened(0.4)
			column.add_child(button)
	step.ask.call("wizard" if has_wizard else "elf")


## Fecha a escolha de escolas (quando ela foi feita por código).
func close_schools() -> void:
	if is_instance_valid(_schools):
		_schools.queue_free()


## Ficha do monstro (clicado ou ferido). body: Corpo a mostrar (-1 = o atual);
## ao mostrar o mesmo monstro com menos Corpo, o risco novo é traçado na hora.
func show_monster(unit: Unit, extra := "", body := -1) -> void:
	_monster = unit
	_monster_sheet.visible = true
	_monster_sheet.show_unit(unit, extra if unit.is_alive() or body > 0 else "Derrotado", body)


func hide_monster() -> void:
	_monster = null
	_monster_sheet.visible = false


## Monstro com a ficha aberta (null se nenhuma).
func shown_monster() -> Unit:
	return _monster


func log_line(text: String) -> void:
	_log.append_text(text + "\n")


## Mostra a carta no alto por alguns segundos (não bloqueia). Com card (a
## carta de tesouro, feitiço, monstro...), mostra a carta pintada do tipo kind
## em vez do aviso simples.
func show_card(title: String, text: String, card := {}, kind := "treasure") -> void:
	if _card_tween != null:
		_card_tween.kill()
	for old in [_popup_card, _popup_back]:
		if is_instance_valid(old):
			old.queue_free()
	if card.is_empty():
		_card_title.text = title
		_card_text.text = text
		_card.visible = true
		_card.modulate.a = 1.0
		_card_tween = create_tween()
		_card_tween.tween_interval(2.5)
		_card_tween.tween_property(_card, "modulate:a", 0.0, 0.4)
		_card_tween.tween_callback(func() -> void: _card.visible = false)
		return
	_card.visible = false
	var front := _place_popup(GameCard.create(card, kind, 230, text))
	_popup_card = front
	_card_tween = create_tween()
	# Carta comprada do baralho (tesouro): aparece de costas e vira.
	if kind == "treasure" or kind == "artifact":
		var back := _place_popup(GameCard.create_back(kind))
		_popup_back = back
		front.scale.x = 0.0
		_card_tween.tween_interval(0.35)
		_card_tween.tween_property(back, "scale:x", 0.0, 0.12)
		_card_tween.tween_callback(func() -> void: back.visible = false)
		_card_tween.tween_property(front, "scale:x", 1.0, 0.12)
	# Depois de lida de relance, encolhe e vai para a esquerda, para não tapar
	# a ação que acontece no tabuleiro (feitiço, dano, monstro errante...).
	_card_tween.tween_interval(CARD_GLANCE)
	_card_tween.set_parallel()
	_card_tween.tween_property(front, "scale", Vector2.ONE * CARD_ASIDE_SCALE, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card_tween.tween_property(front, "position", _aside_position(front), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_card_tween.set_parallel(false)
	_card_tween.tween_interval(3.0)
	_card_tween.tween_property(front, "modulate:a", 0.0, 0.4)
	_card_tween.tween_callback(func() -> void: front.visible = false)


## Põe a carta grande no alto, no centro (girando pelo meio na virada).
func _place_popup(card: GameCard) -> GameCard:
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.offset_top = 60
	add_child(card)
	card.pivot_offset = card.custom_minimum_size / 2
	return card


## Onde a carta grande fica depois de encolhida: na margem esquerda, no
## meio da altura (entre o objetivo e as cartas da mão). O giro é pelo centro,
## então desconta o pedaço que o encolhimento tira de cada lado.
func _aside_position(card: GameCard) -> Vector2:
	var view := card.get_viewport_rect().size
	var size := card.custom_minimum_size
	var shown := size * CARD_ASIDE_SCALE
	var top_left := Vector2(16, (view.y - shown.y) / 2.0 - 20)
	return top_left - card.pivot_offset * (1.0 - CARD_ASIDE_SCALE)


## Página do livro de quests: título, texto de abertura e objetivo num
## pergaminho; "Começar" fecha e chama done.
## `extra`: linha a mais embaixo do objetivo (online: a iniciativa).
func show_intro(title: String, intro: String, objective: String, done: Callable, extra := "") -> void:
	_intro = PanelContainer.new()
	_intro.add_theme_stylebox_override("panel", CardStyle.card_box("parchment", 46))
	_intro.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_intro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_intro.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_intro)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_intro.add_child(box)
	box.add_child(CardStyle.label(title, CardStyle.title_font(), 34, CardStyle.RED))
	for part: Array in [[intro, CardStyle.INK, CardStyle.italic_font(), 18], [objective, CardStyle.RED, CardStyle.body_font(), 17],
			[extra, CardStyle.INK, CardStyle.body_font(), 16]]:
		if part[0] == "":
			continue
		var label := CardStyle.label(part[0], part[2], part[3], part[1])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
		label.justification_flags = TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_SKIP_LAST_LINE
		label.custom_minimum_size = Vector2(560, 0)
		box.add_child(label)
	var go := _button("Começar", func() -> void:
		close_intro()
		done.call())
	go.custom_minimum_size = Vector2(200, 40)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(go)


## Fecha a página do livro (quando a partida segue por código).
func close_intro() -> void:
	if is_instance_valid(_intro):
		_intro.queue_free()


## Encavala as cartas da mão quando não cabem lado a lado em HAND_WIDTH.
func _fan(row: HBoxContainer) -> void:
	var n := row.get_child_count()
	var gap := 6
	if n > 1:
		gap = clampi((HAND_WIDTH - n * HAND_CARD) / (n - 1), -HAND_CARD + 22, 6)
	row.add_theme_constant_override("separation", gap)


## Painel do fim da quest com o resumo e um botão (voltar à campanha/menu).
func show_game_over(victory: bool, details: String, button_text: String, on_button: Callable) -> void:
	_game_over_title.text = "Vitória! A quest foi cumprida" if victory else "Derrota — Zargon venceu"
	_game_over_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if victory else Color(0.9, 0.25, 0.2))
	_game_over_details.text = details
	_game_over_button.text = button_text
	for c in _game_over_button.pressed.get_connections():
		_game_over_button.pressed.disconnect(c.callable)
	_game_over_button.pressed.connect(on_button)
	_game_over.visible = true


func party_text() -> String:
	return _party.text


func _panel_style(alpha: float, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, alpha)
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(6)
	return style


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
