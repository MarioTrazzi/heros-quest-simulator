extends Control
## Menu inicial: nova campanha, continuar (se há save), jogar online, treino avulso, opções e sair.

var _options: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(CardStyle.backdrop())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	# Página do livro: pergaminho queimado com o título e os botões.
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", CardStyle.card_box("parchment", 52))
	center.add_child(page)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	page.add_child(box)

	box.add_child(CardStyle.label("HeroQuest", CardStyle.title_font(), 76, CardStyle.RED, false))
	box.add_child(CardStyle.label("Simulador do jogo de tabuleiro (1989)", CardStyle.italic_font(), 20, CardStyle.INK, false))
	box.add_child(_ornament())

	var has_save := Campaign.has_save(Session.save_path)
	var continue_button := _button("Continuar campanha", continue_campaign)
	continue_button.disabled = not has_save
	box.add_child(continue_button)
	var fresh := _button("Nova campanha", new_campaign)
	if has_save:
		fresh.tooltip_text = "Começa do zero e apaga a campanha atual."
	box.add_child(fresh)
	box.add_child(_button("Jogar online", play_online))
	box.add_child(_button("Treino avulso", play_training))
	box.add_child(_button("Opções", open_options))
	box.add_child(_button("Sair", func() -> void: get_tree().quit()))
	_build_options()


## Fio com losango no meio, separando o título dos botões.
func _ornament() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for i in 3:
		if i == 1:
			row.add_child(CardStyle.label("◆", CardStyle.body_font(), 14, CardStyle.RED, false))
			continue
		var line := ColorRect.new()
		line.color = CardStyle.FRAME
		line.custom_minimum_size = Vector2(110, 2)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line)
	return row


func new_campaign() -> void:
	Session.new_campaign()


func continue_campaign() -> void:
	Session.continue_campaign()


func play_online() -> void:
	Session.go(Session.LOBBY)


func play_training() -> void:
	Session.play("sandbox", false)


func open_options() -> void:
	_options.visible = true


## Velocidade das animações e volume (Settings grava sozinho).
func _build_options() -> void:
	# Fundo escurecido em tela cheia + painel no centro.
	_options = ColorRect.new()
	_options.color = Color(0, 0, 0, 0.8)
	_options.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options.visible = false
	add_child(_options)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_options.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", CardStyle.card_box("parchment", 44))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(CardStyle.label("Opções", CardStyle.title_font(), 34, CardStyle.RED, false))

	box.add_child(_caption("Velocidade das animações"))
	var speeds := HBoxContainer.new()
	box.add_child(speeds)
	var group := ButtonGroup.new()
	for label: String in Settings.SPEEDS:
		var value: float = Settings.SPEEDS[label]
		var b := Button.new()
		b.text = label
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = is_equal_approx(Settings.speed, value)
		b.pressed.connect(func() -> void: Settings.set_speed(value))
		speeds.add_child(b)

	box.add_child(_caption("Volume"))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = Settings.volume
	volume.custom_minimum_size = Vector2(320, 0)
	volume.value_changed.connect(Settings.set_volume)
	box.add_child(volume)
	box.add_child(_button("Testar som", func() -> void: Sfx.play("dice")))
	box.add_child(_button("Fechar", func() -> void: _options.visible = false))


func _caption(text: String) -> Label:
	return CardStyle.label(text, CardStyle.italic_font(), 18, CardStyle.INK, false)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(320, 48)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	return button
