class_name HeroSheet
extends VBoxContainer
## Carta de personagem como a do HeroQuest europeu de 1989 (54 × 80 mm, em
## pergaminho de bordas queimadas): nome em cursiva no alto, o retrato grande na
## moldura dourada (a apresentação aparece sobre ele quando o mouse passa na carta),
## os atributos escritos em três colunas ("Ataque — rola 3 dados de combate"...),
## Mente e Corpo no canto de baixo (o Corpo em quadradinhos riscados a cada ponto
## perdido, como a gente fazia a lápis na folha de personagem) e o herói de corpo
## inteiro (a miniatura 3D, que gira ao arrastar o mouse para os lados) do outro lado.
## Embaixo da carta, fora dela, vão a linha extra, o equipamento e o footer().
## O retrato vem de assets/textures/ui/portrait_<id>.png; sem ele, a miniatura.
## Também serve de ficha de monstro (clicado na partida): a apresentação diz o
## que ele tem de especial e o retrato é a arte da carta do monstro.
## Só mostra: quem chama passa a Unit em show_unit().

const PORTRAIT := "res://assets/textures/ui/portrait_%s.png"

## Clique na carta (só quando clickable: na campanha, abre a armeria do herói).
signal pressed

var compact := false
## A carta reage ao mouse (mãozinha) e emite pressed no clique.
var clickable := false:
	set(value):
		clickable = value
		_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW
## Carta escolhida: contorno dourado em volta.
var selected := false:
	set(value):
		selected = value
		_card.queue_redraw()
var _card: PanelContainer
var _width := 230
var _portrait_id := ""
var _portrait_slot: Control
var _portrait_art: Control
var _intro_panel: PanelContainer
var _intro_tween: Tween
var _figure_slot: Control
var _figure: FigureView
var _turn_hint: TurnHint
var _drag_moved := 0.0
var _name: Label
var _intro: Label
var _stats: HBoxContainer
var _mind: Label
var _body: Label
var _body_track: BodyTrack
var _extra: Label
var _gear: Label
var _footer: VBoxContainer


## compact: versão do HUD da partida (Corpo atual, sem equipamento).
## width: largura da carta (0 = a padrão).
static func create(p_compact := false, width := 0) -> HeroSheet:
	var sheet := HeroSheet.new()
	sheet.compact = p_compact
	sheet._width = width if width > 0 else (220 if p_compact else 230)
	sheet._build()
	return sheet


## Caixa para pôr botões e textos embaixo da carta.
func footer() -> VBoxContainer:
	return _footer


## extra: linha livre embaixo da carta (ouro, quests...). body: Corpo a mostrar
## (-1 = o atual da unidade; a partida passa o de antes do golpe para riscar na hora).
func show_unit(unit: Unit, extra := "", body := -1) -> void:
	var k := _width / 230.0
	if body < 0:
		body = unit.body
	_name.text = unit.name
	_intro.text = GameData.hero(unit.def_id).get("text", "") if unit.is_hero() else _monster_intro(unit)
	_intro_panel.visible = _intro.text != ""
	for child in _stats.get_children():
		child.queue_free()
	for line: Array in [
			["Ataque", "rola %d %s de combate" % [unit.attack, "dado" if unit.attack == 1 else "dados"]],
			["Defesa", "rola %d %s de combate" % [unit.defend, "dado" if unit.defend == 1 else "dados"]],
			["Movimento", "rola %d %s normais" % [unit.move_dice, "dado" if unit.move_dice == 1 else "dados"]
				if unit.is_hero() else "anda %d casas" % unit.move]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", roundi(-3 * k))
		column.add_child(CardStyle.label(line[0], CardStyle.title_font(), roundi(14 * k), CardStyle.INK, false))
		var detail := CardStyle.label(line[1], CardStyle.body_font(), roundi(11 * k))
		detail.add_theme_constant_override("line_spacing", -3)
		column.add_child(detail)
		_stats.add_child(column)
	_mind.text = "Mente %d" % unit.mind
	# Um quadradinho por ponto de Corpo; o que foi perdido aparece riscado.
	_body.text = "Corpo"
	_body.add_theme_color_override("font_color", CardStyle.RED if body < unit.body_max else CardStyle.INK)
	_body_track.show_points(str(unit.get_instance_id()), unit.body_max, body)
	_extra.text = extra
	_extra.visible = extra != ""
	if _gear != null:
		_gear.text = ", ".join(unit.equipment.map(func(it: Dictionary) -> String: return it.name))
	if unit.def_id != _portrait_id:
		_portrait_id = unit.def_id
		_set_portrait(unit)
		if _figure != null:
			_figure.get_parent().get_parent().queue_free()
		var view := _model_view(unit, true)
		_figure = view.get_meta("figure")
		_figure_slot.add_child(view)
		_figure_slot.move_child(view, 0)  # o arco da dica fica por cima


## Apresentação do monstro: o que ele tem de diferente (não há texto no livro).
func _monster_intro(unit: Unit) -> String:
	var lines: Array[String] = []
	if unit.is_objective:
		lines.append("Alvo da quest.")
	if not unit.carries.is_empty():
		lines.append("Leva %s." % unit.carries.get("name", "um item"))
	if unit.has_tag("undead"):
		lines.append("Morto-vivo: o Sono não o pega.")
	if unit.has_tag("spirit_blade_only"):
		lines.append("Só a Lâmina Espiritual o fere.")
	if unit.has_tag("spell_immune"):
		lines.append("Imune a feitiços.")
	if not unit.spells.is_empty():
		lines.append("Conjura feitiços do Caos.")
	return " ".join(lines) if not lines.is_empty() else "Servo de Zargon."


func _build() -> void:
	var k := _width / 230.0
	add_theme_constant_override("separation", 4)
	var card := PanelContainer.new()
	_card = card
	card.draw.connect(_draw_selection)
	card.gui_input.connect(_on_card_input)
	card.add_theme_stylebox_override("panel", CardStyle.card_box("parchment", _width * 0.08))
	card.custom_minimum_size = Vector2(_width, roundf(_width * GameCard.ASPECT))
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(3 * k))
	card.add_child(col)

	_name = CardStyle.label("", CardStyle.title_font(), roundi(26 * k))
	col.add_child(_name)

	# Retrato grande na moldura dourada de fundo vermelho; a apresentação fica
	# escondida e aparece sobre ele quando o mouse passa na carta.
	var frame := PanelContainer.new()
	var frame_box := CardStyle.frame_box(CardStyle.GOLD.darkened(0.2), roundi(3 * k), CardStyle.RED)
	frame_box.set_content_margin_all(roundi(3 * k))
	frame_box.border_color = CardStyle.GOLD
	frame_box.shadow_color = Color(0, 0, 0, 0.35)
	frame_box.shadow_size = 2
	frame.add_theme_stylebox_override("panel", frame_box)
	# Meio da carta: o retrato alto à esquerda; à direita, a miniatura que gira,
	# com Mente e Corpo embaixo dela.
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", roundi(4 * k))
	col.add_child(middle)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(frame)
	_portrait_slot = Control.new()
	_portrait_slot.clip_contents = true
	frame.add_child(_portrait_slot)
	_portrait_art = Control.new()
	_portrait_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_slot.add_child(_portrait_art)
	_intro_panel = PanelContainer.new()
	var intro_box := StyleBoxFlat.new()
	intro_box.bg_color = Color(0.07, 0.04, 0.02, 0.8)
	intro_box.set_content_margin_all(roundi(5 * k))
	_intro_panel.add_theme_stylebox_override("panel", intro_box)
	_intro_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	_intro_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_intro_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_panel.modulate.a = 0.0
	_portrait_slot.add_child(_intro_panel)
	_intro = CardStyle.label("", CardStyle.italic_font(), roundi(11 * k), CardStyle.PARCHMENT)
	_intro.add_theme_constant_override("line_spacing", -3)
	_intro_panel.add_child(_intro)
	card.mouse_entered.connect(_show_intro.bind(true))
	card.mouse_exited.connect(_show_intro.bind(false))

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(66, 0) * k
	side.add_theme_constant_override("separation", roundi(-2 * k))
	middle.add_child(side)
	# A miniatura gira ao arrastar para os lados; um arco discreto nos pés avisa.
	_figure_slot = Control.new()
	_figure_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_figure_slot.mouse_filter = Control.MOUSE_FILTER_STOP
	_figure_slot.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_figure_slot.tooltip_text = "Arraste para os lados para girar."
	_figure_slot.gui_input.connect(_on_figure_input)
	_figure_slot.mouse_entered.connect(func() -> void: _turn_hint.hot = true)
	_figure_slot.mouse_exited.connect(func() -> void: _turn_hint.hot = false)
	side.add_child(_figure_slot)
	_turn_hint = TurnHint.new()
	_turn_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_figure_slot.add_child(_turn_hint)
	_mind = CardStyle.label("", CardStyle.title_font(), roundi(15 * k), CardStyle.INK, false)
	side.add_child(_mind)
	_body = CardStyle.label("", CardStyle.title_font(), roundi(15 * k), CardStyle.INK, false)
	side.add_child(_body)
	_body_track = BodyTrack.new()
	_body_track.box = roundf(11 * k)
	_body_track.gap = roundf(3 * k)
	side.add_child(_body_track)

	# Embaixo, os atributos em três colunas.
	_stats = HBoxContainer.new()
	_stats.add_theme_constant_override("separation", roundi(3 * k))
	col.add_child(_stats)

	_extra = CardStyle.label("", CardStyle.body_font(), 14, CardStyle.PARCHMENT)
	add_child(_extra)
	if not compact:
		_gear = CardStyle.label("", CardStyle.italic_font(), 13, CardStyle.PARCHMENT.darkened(0.15))
		_gear.custom_minimum_size = Vector2(_width, 0)
		add_child(_gear)
	_footer = VBoxContainer.new()
	add_child(_footer)


## Dica ao passar o mouse na carta (o VBox de fora não recebe o mouse).
func set_card_tooltip(text: String) -> void:
	_card.tooltip_text = text


func _draw_selection() -> void:
	if selected:
		_card.draw_rect(Rect2(Vector2.ONE * 2, _card.size - Vector2.ONE * 4), CardStyle.GOLD, false, 4.0)


func _on_card_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


## Mostra/esconde a apresentação sobre o retrato.
func _show_intro(on: bool) -> void:
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_tween = create_tween()
	_intro_tween.tween_property(_intro_panel, "modulate:a", 1.0 if on else 0.0, 0.2)


## Arrastar para os lados gira a miniatura; clique sem arrastar vale como clique na carta.
func _on_figure_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_moved = 0.0
		elif _drag_moved < 4.0 and clickable:
			pressed.emit()
		_figure_slot.accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and _figure != null:
		_drag_moved += absf(event.relative.x)
		_figure.rotation.y += event.relative.x * 0.012
		_figure_slot.accept_event()


## Herói: o retrato pintado; monstro: a arte da carta dele. Sem arte, a miniatura.
func _set_portrait(unit: Unit) -> void:
	for child in _portrait_art.get_children():
		child.queue_free()
	var path := PORTRAIT % unit.def_id if unit.is_hero() else GameCard.art_path({"id": unit.def_id})
	if ResourceLoader.exists(path):
		var art := TopCrop.new()
		art.texture = load(path)
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_art.add_child(art)
	else:
		_portrait_art.add_child(_model_view(unit, false))


## Fotografa a miniatura 3D à luz de vela. full_body: o herói inteiro com fundo
## transparente (embaixo da carta); senão, meio corpo com fundo escuro (retrato).
func _model_view(source: Unit, full_body: bool) -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = full_body
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR if full_body else Environment.BG_COLOR
	env.background_color = Color(0.09, 0.07, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.4, 0.36)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.85, 0.65)
	key.rotation_degrees = Vector3(-30, 35, 0)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.55, 0.9)
	rim.light_energy = 0.6
	rim.rotation_degrees = Vector3(-15, 200, 0)
	viewport.add_child(rim)

	var unit := Unit.new()
	unit.def_id = source.def_id
	unit.side = source.side
	var figure := FigureView.new()
	viewport.add_child(figure)
	figure.setup(unit)
	figure.position = Vector3.ZERO
	for child in figure.get_children():
		if child is Label3D:
			child.visible = false

	var camera := Camera3D.new()
	camera.fov = 30
	container.set_meta("figure", figure)
	if full_body:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 21
		camera.look_at_from_position(Vector3(0.3, 1.05, 2.4), Vector3(0, 0.82, 0))
	else:
		camera.look_at_from_position(Vector3(0.25, 0.75, 1.9), Vector3(0, 0.5, 0))
	viewport.add_child(camera)
	return container


## Pintura em pé recortada para preencher a área sem perder a cabeça: ocupa a
## largura toda e o corte começa perto do alto (o rosto fica no terço de cima).
class TopCrop extends Control:
	const TOP := 0.06  # quanto do alto da pintura fica de fora
	var texture: Texture2D

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		if texture == null or size.x <= 0.0:
			return
		var tex := texture.get_size()
		var s := maxf(size.x / tex.x, size.y / tex.y)
		var drawn := tex * s
		var y := clampf(-drawn.y * TOP, size.y - drawn.y, 0.0)
		draw_texture_rect(texture, Rect2(Vector2((size.x - drawn.x) / 2.0, y), drawn), false)


## Arco de tinta em volta dos pés da miniatura, com setas nas pontas: avisa, sem
## chamar atenção, que ela gira ao arrastar. Mais forte com o mouse em cima.
class TurnHint extends Control:
	var hot := false:
		set(value):
			hot = value
			queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var color := Color(CardStyle.INK, 0.7 if hot else 0.28)
		var center := Vector2(size.x * 0.5, size.y - size.y * 0.07)
		var radius := Vector2(size.x * 0.38, size.y * 0.06)
		var points := PackedVector2Array()
		# Meia elipse da frente (embaixo), de um lado ao outro.
		for i in 17:
			var a := deg_to_rad(lerpf(15.0, 165.0, i / 16.0))
			points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
		draw_polyline(points, color, 1.3, true)
		for end in [[points[0], points[1]], [points[16], points[15]]]:
			var tip: Vector2 = end[0]
			var dir: Vector2 = (tip - end[1]).normalized()
			var side := dir.orthogonal() * 3.0
			draw_polyline(PackedVector2Array([tip - dir * 5.0 + side, tip, tip - dir * 5.0 - side]), color, 1.3, true)


## Fileira de quadradinhos do Corpo desenhados à mão; os pontos perdidos levam um X
## a lápis. O risco novo é traçado aos poucos (só quando é a mesma figura perdendo
## Corpo; ao trocar de figura, aparece pronto). Cura apaga os riscos.
class BodyTrack extends Control:
	var box := 12.0
	var gap := 3.0
	var _max := 0
	var _owner := ""
	var _drawn := 0.0  # quantos riscos já estão traçados (fracionário durante a animação)
	var _tween: Tween

	func show_points(key: String, body_max: int, body: int) -> void:
		var lost := clampi(body_max - body, 0, body_max)
		var animate := key == _owner and lost > _drawn
		_owner = key
		_max = body_max
		if _tween != null:
			_tween.kill()
		if animate:
			_tween = create_tween()
			_tween.tween_method(_set_drawn, _drawn, float(lost), 0.35 * (lost - _drawn))
		else:
			_drawn = lost
		update_minimum_size()
		queue_redraw()

	func _set_drawn(value: float) -> void:
		_drawn = value
		queue_redraw()

	func _per_row() -> int:
		var w := size.x if size.x > 0 else box * 6 + gap * 5
		var fits := maxi(1, int((w + gap) / (box + gap)))
		# Fileiras iguais (8 = 4 + 4, não 7 + 1).
		return ceili(_max / float(ceili(_max / float(fits)))) if _max > 0 else fits

	func _get_minimum_size() -> Vector2:
		var rows := ceili(_max / float(_per_row())) if _max > 0 else 0
		return Vector2(box * 4, rows * box + maxi(rows - 1, 0) * gap)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			update_minimum_size()

	func _draw() -> void:
		var per_row := _per_row()
		var ink := CardStyle.INK
		var pencil := Color(CardStyle.INK, 0.85)
		for i in _max:
			var origin := Vector2((i % per_row) * (box + gap), (i / per_row) * (box + gap))
			# Quadrado com as quinas um pouco tortas, como feito à mão.
			var c: Array[Vector2] = []
			for j in 4:
				var corner := Vector2(box if j == 1 or j == 2 else 0.0, box if j >= 2 else 0.0)
				c.append(origin + corner + _wobble(i * 4 + j) * box * 0.06)
			draw_polyline(PackedVector2Array([c[0], c[1], c[2], c[3], c[0]]), ink, 1.2, true)
			# Risco do ponto perdido (os primeiros quadrados são os primeiros a sair).
			var t := clampf(_drawn - i, 0.0, 1.0)
			if t <= 0.0:
				continue
			var a := origin + Vector2(-1, -1) + _wobble(i * 7 + 1) * 1.5
			var b := origin + Vector2(box + 1, box + 1) + _wobble(i * 7 + 2) * 1.5
			draw_line(a, a.lerp(b, minf(t * 2.0, 1.0)), pencil, 2.0, true)
			if t > 0.5:
				var d := origin + Vector2(box + 1, -1) + _wobble(i * 7 + 3) * 1.5
				var e := origin + Vector2(-1, box + 1) + _wobble(i * 7 + 4) * 1.5
				draw_line(d, d.lerp(e, (t - 0.5) * 2.0), pencil, 2.0, true)

	## Tremido fixo por índice (sem RNG: nada de sorteio fora do Dice).
	func _wobble(n: int) -> Vector2:
		return Vector2(sin(n * 12.9898), cos(n * 78.233))
