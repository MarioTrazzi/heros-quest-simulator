extends Control
## Lobby online: conecta no servidor, lista as salas de todos os grupos (as
## suas primeiro), cria sala (nome + senha opcional) e entra (com a senha, se
## ainda não tem assento nela). Ao entrar, vai para a tela da campanha da sala.

var _name_edit: LineEdit
var _server_edit: LineEdit
var _status: Label
var _connect_box: Control
var _rooms_box: Control
var _search: LineEdit
var _list: VBoxContainer
var _room_name: LineEdit
var _room_password: LineEdit
var _prompt: Control
var _prompt_title: Label
var _prompt_password: LineEdit
var _prompt_room := ""
## Última lista recebida (o smoke lê).
var rooms: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(CardStyle.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var title := CardStyle.heading("Jogar online", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button("Voltar", func() -> void: Session.go_offline()))
	_status = Label.new()
	_status.modulate = Color(1.0, 0.8, 0.5)
	root.add_child(_status)

	# Conexão: nome do jogador e endereço do servidor.
	var connect_row := HBoxContainer.new()
	connect_row.add_theme_constant_override("separation", 8)
	_connect_box = connect_row
	root.add_child(connect_row)
	_name_edit = _edit("Seu nome", Net.player_name, 200)
	_name_edit.max_length = Protocol.MAX_NAME
	connect_row.add_child(_name_edit)
	_server_edit = _edit("Servidor (wss://...)", Net.server_url, 360)
	connect_row.add_child(_server_edit)
	connect_row.add_child(_button("Conectar", func() -> void: connect_server(_server_edit.text, _name_edit.text)))

	# Salas.
	var rooms_box := HBoxContainer.new()
	rooms_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rooms_box.add_theme_constant_override("separation", 16)
	_rooms_box = rooms_box
	root.add_child(rooms_box)

	var list_panel := _panel(rooms_box, 0.65)
	var search_row := HBoxContainer.new()
	list_panel.add_child(search_row)
	_search = _edit("Procurar sala pelo nome", "", 260)
	_search.text_submitted.connect(func(_t: String) -> void: refresh_rooms())
	search_row.add_child(_search)
	search_row.add_child(_button("Atualizar", refresh_rooms))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var create_panel := _panel(rooms_box, 0.35)
	create_panel.add_child(CardStyle.heading("Nova sala", 28))
	var hint := Label.new()
	hint.text = "Uma sala é a campanha do seu grupo: fica aberta no servidor e cada amigo senta no seu herói."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_override("font", CardStyle.italic_font())
	hint.modulate = Color(1, 1, 1, 0.75)
	create_panel.add_child(hint)
	_room_name = _edit("Nome da sala", "", 0)
	_room_name.max_length = Protocol.MAX_ROOM_NAME
	create_panel.add_child(_room_name)
	_room_password = _edit("Senha (vazio = sala aberta)", "", 0)
	_room_password.secret = true
	_room_password.max_length = Protocol.MAX_PASSWORD
	create_panel.add_child(_room_password)
	create_panel.add_child(_button("Criar sala", func() -> void: create_room(_room_name.text, _room_password.text)))

	_build_prompt()
	Net.status_changed.connect(_set_status)
	Net.error_received.connect(_set_status)
	Net.welcomed.connect(_on_welcomed)
	Net.rooms_received.connect(_on_rooms)
	Net.room_changed.connect(_on_room_entered)
	_show_connected(Net.is_online())
	if Net.is_online():
		refresh_rooms()


# ---------- ações (também usadas pelo smoke) ----------

func connect_server(url: String, player_name: String) -> void:
	if Protocol.clean_name(player_name, Protocol.MAX_NAME) == "":
		_set_status("Escolha um nome.")
		return
	Net.connect_server(url, player_name)


func refresh_rooms() -> void:
	Net.list_rooms(_search.text)


func create_room(room_name: String, password: String) -> void:
	if Protocol.clean_name(room_name, Protocol.MAX_ROOM_NAME) == "":
		_set_status("Dê um nome à sala.")
		return
	Net.create_room(room_name, password)


func enter_room(id: String, password := "") -> void:
	_prompt.visible = false
	Net.enter_room(id, password)


# ---------- eventos ----------

func _on_welcomed() -> void:
	_show_connected(true)
	refresh_rooms()


func _on_rooms(list: Array) -> void:
	rooms = list
	for child in _list.get_children():
		child.queue_free()
	if list.is_empty():
		var empty := Label.new()
		empty.text = "Nenhuma sala ainda. Crie a do seu grupo ao lado."
		empty.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(empty)
	for room: Dictionary in list:
		_list.add_child(_room_row(room))


func _on_room_entered() -> void:
	if not Net.room.is_empty():
		Session.go(Session.HUB)


func _set_status(text: String) -> void:
	_status.text = text


func _show_connected(connected: bool) -> void:
	_rooms_box.visible = connected
	_connect_box.visible = not connected


# ---------- tela ----------

## Faixa de pergaminho da sala: nome em cursiva, resumo e o botão de entrar.
func _room_row(room: Dictionary) -> Control:
	var strip := PanelContainer.new()
	var paper := CardStyle.button_box(CardStyle.PARCHMENT, CardStyle.FRAME)
	paper.set_content_margin_all(6)
	paper.content_margin_left = 12
	strip.add_theme_stylebox_override("panel", paper)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	strip.add_child(row)
	var label := CardStyle.label("%s%s%s" % ["★ " if room.mine else "", room.name, "  🔒" if room.locked else ""],
		CardStyle.title_font(), 20, CardStyle.INK, false)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	var where: String = GameData.quest(room.quest).name if room.quest != "" else "no acampamento"
	var info := CardStyle.label("de %s · %d/4 assentos · %d online · %s · %d quests" % [
		room.owner, int(room.seats), int(room.online), where, int(room.completed)],
		CardStyle.italic_font(), 15, Color(CardStyle.INK, 0.8), false)
	row.add_child(info)
	var enter := Button.new()
	enter.text = "Entrar"
	enter.pressed.connect(func() -> void:
		if room.locked and not room.mine:
			_ask_password(room)
		else:
			enter_room(room.id))
	row.add_child(enter)
	return strip


func _build_prompt() -> void:
	_prompt = ColorRect.new()
	_prompt.color = Color(0, 0, 0, 0.75)
	_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt.visible = false
	add_child(_prompt)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_prompt.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CardStyle.card_box("parchment", 40))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_prompt_title = CardStyle.label("", CardStyle.title_font(), 24, CardStyle.RED, false)
	box.add_child(_prompt_title)
	_prompt_password = _edit("Senha da sala", "", 280)
	_prompt_password.secret = true
	_prompt_password.text_submitted.connect(func(t: String) -> void: enter_room(_prompt_room, t))
	box.add_child(_prompt_password)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("Entrar", func() -> void: enter_room(_prompt_room, _prompt_password.text)))
	row.add_child(_button("Cancelar", func() -> void: _prompt.visible = false))


func _ask_password(room: Dictionary) -> void:
	_prompt_room = room.id
	_prompt_title.text = "Senha de \"%s\"" % room.name
	_prompt_password.text = ""
	_prompt.visible = true
	_prompt_password.grab_focus()


func _edit(placeholder: String, text: String, width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(width, 0)
	if width == 0:
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


func _panel(parent: Control, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box
