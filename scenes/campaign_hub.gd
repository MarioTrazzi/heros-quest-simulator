extends Control
## Tela da campanha entre quests: fichas dos heróis (com o equipamento e o
## ouro), a lista de quests e a armeria do herói escolhido.
## Online (sala do lobby): cada ficha mostra o assento (dono, online, sentar/
## liberar); compras e quests vão ao servidor, que manda a sala atualizada.

var _heroes_box: HBoxContainer
var _quests_box: VBoxContainer
var _armory_title: Label
var _armory_list: HFlowContainer
var _message: Label
var _armory_hero := "barbarian"
var _title: Label
var _online_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(CardStyle.backdrop())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	# A tela toda rola (as fichas são altas; a armeria fica embaixo).
	var page := ScrollContainer.new()
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(page)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_title = CardStyle.heading("Campanha", 40)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var menu := Button.new()
	menu.text = "Sair da sala" if Session.online else "Menu"
	menu.pressed.connect(leave)
	top.add_child(menu)
	_online_label = Label.new()
	_online_label.modulate = Color(0.6, 0.85, 1.0)
	_online_label.visible = Session.online
	root.add_child(_online_label)

	_heroes_box = HBoxContainer.new()
	_heroes_box.add_theme_constant_override("separation", 10)
	root.add_child(_heroes_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	root.add_child(bottom)

	var quests_panel := _panel(bottom, 0.4)
	quests_panel.add_child(CardStyle.heading("Quests", 28))
	_quests_box = VBoxContainer.new()
	_quests_box.add_theme_constant_override("separation", 6)
	quests_panel.add_child(_quests_box)

	var armory_panel := _panel(bottom, 0.6)
	_armory_title = CardStyle.heading("", 28)
	armory_panel.add_child(_armory_title)
	_message = Label.new()
	_message.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	armory_panel.add_child(_message)
	_armory_list = HFlowContainer.new()
	_armory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_armory_list.add_theme_constant_override("h_separation", 10)
	_armory_list.add_theme_constant_override("v_separation", 10)
	armory_panel.add_child(_armory_list)

	if Session.online:
		Net.room_changed.connect(refresh)
		Net.quest_started.connect(_on_quest_started)
		Net.error_received.connect(_on_error)
		var mine := Net.my_heroes()
		if not mine.is_empty():
			_armory_hero = mine[0]
	refresh()


# ---------- ações (também usadas pelo smoke) ----------

func open_armory(hero_id: String) -> void:
	_armory_hero = hero_id
	_message.text = ""
	refresh()


## Compra para o herói; "" se deu certo, senão o motivo.
func buy(hero_id: String, item_id: String) -> String:
	if Session.online:
		# A resposta chega como sala nova (ou erro, em _message).
		_message.text = ""
		Net.buy(hero_id, item_id)
		return ""
	# A quest em andamento guardou os heróis do começo: comprar agora se perderia no fim dela.
	var reason := "Termine ou abandone a quest em andamento antes de comprar." \
		if not Session.campaign.in_progress.is_empty() else Armory.buy(Session.campaign.hero(hero_id), item_id)
	if reason == "":
		Session.campaign.save(Session.save_path)
		_message.text = ""
	else:
		_message.text = reason
	refresh()
	return reason


## Liberada na campanha (na prévia local, todas).
func _unlocked(quest_id: String) -> bool:
	return Session.campaign.is_unlocked(quest_id) or (Session.preview and not Session.online)


## Quest em andamento continua de onde parou; outra quest começa do zero (e descarta a anterior).
func play(quest_id: String) -> void:
	if not _unlocked(quest_id):
		return
	if Session.online:
		Net.start_quest(quest_id)
	else:
		Session.play(quest_id)


## Joga fora a quest em andamento (nada muda na campanha).
func abandon_quest() -> void:
	if Session.online:
		Net.abandon_quest()
		return
	Session.campaign.in_progress = {}
	Session.campaign.save(Session.save_path)
	refresh()


func sit(hero_id: String) -> void:
	Net.sit(hero_id)


func free_seat(hero_id: String) -> void:
	Net.free_seat(hero_id)


func leave() -> void:
	if Session.online:
		Net.leave_room()
		Session.go(Session.LOBBY)
	else:
		Session.go(Session.MENU)


func _on_error(reason: String) -> void:
	_message.text = reason


## O servidor chamou a sala para a quest.
func _on_quest_started(quest_id: String) -> void:
	Session.play(quest_id)


# ---------- tela ----------

func refresh() -> void:
	var campaign := Session.campaign
	if Session.online:
		var room := Net.room
		_title.text = "%s%s" % [room.get("name", "Sala"), "  🔒" if room.get("locked", false) else ""]
		_online_label.text = "Online agora: %s · criada por %s" % [", ".join(room.get("online", [])), room.get("owner", "?")]
	for child in _heroes_box.get_children() + _quests_box.get_children() + _armory_list.get_children():
		child.queue_free()
	for rec in campaign.heroes:
		_heroes_box.add_child(_hero_card(rec))
	for id in campaign.quest_order:
		_quests_box.add_child(_quest_row(id))
	var rec := campaign.hero(_armory_hero)
	_armory_title.text = "Armeria — %s (ouro: %d)" % [GameData.hero(_armory_hero).name, int(rec.gold)]
	for item: Dictionary in Armory.items():
		_armory_list.add_child(_item_card(rec, item))


func _hero_card(rec: Dictionary) -> Control:
	var unit := Session.campaign.hero_unit(rec.id)
	var sheet := HeroSheet.create()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.show_unit(unit, "Movimento %dd6 · Ouro %d · Quests %d%s" % [
		unit.move_dice, int(rec.gold), int(rec.quests_done), "\nCampeão do Reino" if rec.champion else ""])
	# Clique na ficha abre a armeria do herói; a escolhida fica com contorno dourado.
	sheet.clickable = true
	sheet.selected = rec.id == _armory_hero
	sheet.set_card_tooltip("Clique para abrir a armeria de %s." % unit.name)
	sheet.pressed.connect(open_armory.bind(rec.id))
	if Session.online:
		_seat_controls(sheet.footer(), rec.id)
	return sheet


## Assento do herói: dono (e se está online), sentar no vazio, liberar o seu (ou qualquer um, se criou a sala).
func _seat_controls(footer: Control, hero_id: String) -> void:
	var seat: Variant = Net.seat(hero_id)
	var label := Label.new()
	if seat == null:
		label.text = "Livre (fica fora da quest)"
		label.modulate = Color(1, 1, 1, 0.6)
	else:
		label.text = "%s %s%s" % ["●" if seat.online else "○", seat.name, " (você)" if seat.mine else ""]
		label.modulate = Color(0.5, 1.0, 0.5) if seat.online else Color(1, 1, 1, 0.6)
	footer.add_child(label)
	if seat == null:
		var b := Button.new()
		b.text = "Escolher"
		b.tooltip_text = "Este herói passa a ser seu; os outros jogadores não podem mais escolhê-lo."
		b.pressed.connect(sit.bind(hero_id))
		footer.add_child(b)
	elif seat.mine or Net.room.get("is_owner", false):
		var b := Button.new()
		b.text = "Liberar"
		b.tooltip_text = "Devolve o herói (ele continua na campanha, mas fica fora das próximas quests até alguém escolhê-lo)."
		b.pressed.connect(free_seat.bind(hero_id))
		footer.add_child(b)


## Faixa de pergaminho da quest: nome, selo da situação e os botões.
func _quest_row(id: String) -> Control:
	var campaign := Session.campaign
	var strip := PanelContainer.new()
	var paper := CardStyle.button_box(CardStyle.PARCHMENT, CardStyle.FRAME)
	paper.set_content_margin_all(6)
	paper.content_margin_left = 12
	strip.add_theme_stylebox_override("panel", paper)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	var unlocked := _unlocked(id)
	var quest_name := CardStyle.label(GameData.quest(id).name, CardStyle.title_font(), 20,
		CardStyle.INK if unlocked else Color(CardStyle.INK, 0.5), false)
	quest_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	quest_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_name.clip_text = true
	row.add_child(quest_name)
	var running: bool = campaign.in_progress.get("quest_id", "") == id
	if running:
		row.add_child(CardStyle.seal("Em andamento", Color(0.18, 0.32, 0.5)))
	elif campaign.completed.has(id):
		row.add_child(CardStyle.seal("Cumprida", Color(0.2, 0.38, 0.18)))
	elif id == campaign.next_quest():
		row.add_child(CardStyle.seal("Próxima", CardStyle.RED))
	elif not unlocked:
		row.add_child(CardStyle.seal("Bloqueada", Color(0.35, 0.32, 0.28)))
	var go := Button.new()
	go.text = "Continuar" if running else "Jogar"
	go.disabled = not unlocked
	if Session.online and not running and Net.my_heroes().is_empty():
		go.disabled = true
		go.tooltip_text = "Escolha um herói primeiro."
	elif Session.online and not running:
		go.tooltip_text = "Entram só os heróis escolhidos; cada um rola 1d6 e o maior começa."
	go.custom_minimum_size = Vector2(110, 0)
	go.pressed.connect(play.bind(id))
	row.add_child(go)
	if running:
		var drop := Button.new()
		drop.text = "Abandonar"
		drop.tooltip_text = "Joga fora a partida em andamento (nada muda na campanha)."
		drop.pressed.connect(abandon_quest)
		row.add_child(drop)
	return strip


## Carta da peça da armeria com o preço e o botão de compra embaixo.
func _item_card(rec: Dictionary, item: Dictionary) -> Control:
	# A carta fica na proporção do jogo; preço e botão vão embaixo dela.
	var box := VBoxContainer.new()
	var card := GameCard.create(item, "equipment", 150)
	box.add_child(card)
	var price := Label.new()
	price.text = "%d moedas de ouro" % int(item.price)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_override("font", CardStyle.body_font())
	price.add_theme_font_size_override("font_size", 12)
	price.add_theme_color_override("font_color", CardStyle.GOLD)
	box.add_child(price)
	var reason := Armory.why_not(rec, item)
	if reason == "" and not Session.campaign.in_progress.is_empty():
		reason = "Quest em andamento"
	if reason == "" and Session.online and not Net.my_heroes().has(rec.id):
		reason = "Herói de outro jogador"
	var button := Button.new()
	button.text = "Comprar" if reason == "" else reason
	button.disabled = reason != ""
	button.tooltip_text = reason
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 12)
	button.custom_minimum_size = Vector2(150, 0)
	button.pressed.connect(func() -> void: buy(rec.id, item.id))
	box.add_child(button)
	return box


func _panel(parent: Control, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box
