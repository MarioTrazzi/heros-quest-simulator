class_name GameCard
extends PanelContainer
## Carta do jogo como as do HeroQuest europeu de 1989 (CardStyle):
##  - tesouro, feitiço, equipamento e artefato: carta branca de moldura marrom
##    rasgada, título em cursiva, ilustração a nanquim (cards/ink/<id>.png; sem
##    ela, a pintura com o filtro de nanquim) num quadro deitado, texto
##    centralizado, linha de regra e (tesouro) a faixa "HeroQuest" no rodapé;
##  - monstro: pergaminho com o ícone redondo nos cantos, nome em cursiva,
##    ilustração colorida e os atributos escritos ("Movimento: 8 casas"...);
##  - verso (create_back): pintura de ponta a ponta com a faixa do baralho.
## Sempre na proporção 54 × 80 mm. Estreita (< 150 px) é carta de mão: cresce
## com o mouse em cima e o clique emite pressed. A pintura vem de
## assets/textures/cards/<id>.png (tools/gen_cards.py); sem ela, a inicial.

signal pressed

const ART := "res://assets/textures/cards/%s.png"
## Ilustração a nanquim das cartas brancas (tools/gen_cards.py --ink); sem ela,
## a pintura colorida passa pelo filtro de nanquim.
const INK_ART := "res://assets/textures/cards/ink/%s.png"
## Cartas que dividem a mesma pintura.
const ART_ALIAS := {
	"gold_10": "gold", "gold_20": "gold", "gold_25": "gold", "gold_50": "gold", "gold_room": "gold",
	"potion_healing_quest": "potion_healing", "quest": "chest",
	"c_ball_of_flame": "ball_of_flame", "c_sleep": "sleep", "c_tempest": "tempest",
}
## Proporção das cartas do HeroQuest europeu de 1989 (≈ 54 × 80 mm, todas do
## mesmo tamanho): altura = largura × ASPECT.
const ASPECT := 80.0 / 54.0
## Verso de cada baralho: pintura e nome na faixa.
const BACKS := {
	"treasure": ["treasure_horde", "Tesouro"],
	"equipment": ["broadsword", "Equipamento"],
	"artifact": ["spell_ring", "Tesouro da Quest"],
	"chaos": ["chaos_warlock", "Feitiço do Caos"],
	"air": ["genie", "Feitiço do Ar"],
	"fire": ["ball_of_flame", "Feitiço do Fogo"],
	"water": ["water_of_healing", "Feitiço da Água"],
	"earth": ["rock_skin", "Feitiço da Terra"],
}

var interactive := true
var disabled := false:
	set(value):
		disabled = value
		modulate = Color(0.55, 0.55, 0.55) if value else Color.WHITE
		mouse_default_cursor_shape = Control.CURSOR_ARROW if value or not interactive else Control.CURSOR_POINTING_HAND
## Carta escolhida (feitiço esperando o alvo): contorno dourado e erguida.
var selected := false:
	set(value):
		selected = value
		queue_redraw()
		if not _hovered:
			_lift(1.15 if value else 1.0)
var _hovered := false
var _tween: Tween


## kind: "treasure", "spell", "chaos", "equipment", "artifact" ou "monster".
## width: < 150 = carta de mão (inventário, feitiços); text vazio = describe().
static func create(card: Dictionary, kind := "treasure", width := 96, text := "") -> GameCard:
	var c := GameCard.new()
	c.interactive = width < 150
	c._setup_size(width)
	if kind == "monster":
		c._build_monster(card, width)
	else:
		c._build_ink(card, kind, width, text if text != "" else describe(card))
	return c


## Verso do baralho (key: tipo da carta ou escola do feitiço).
static func create_back(key: String, width := 230) -> GameCard:
	var c := GameCard.new()
	c.interactive = false
	c._setup_size(width)
	c._build_back(BACKS.get(key, BACKS.treasure), width)
	return c


## Chave do verso de uma carta (o feitiço usa a escola).
static func back_key(card: Dictionary, kind: String) -> String:
	return card.get("school", kind) if kind == "spell" else kind


static func art_path(card: Dictionary) -> String:
	return ART % _art_id(card)


static func _art_id(card: Dictionary) -> String:
	var id: String = card.get("art", card.get("id", ""))
	return ART_ALIAS.get(id, id)


## Tipo da carta de um feitiço (dos heróis ou do Caos).
static func spell_kind(spell: Dictionary) -> String:
	return "chaos" if spell.get("school", "") == "chaos" else "spell"


## Texto da carta: o "text" dos dados ou, sem ele, o efeito montado pelos campos.
static func describe(card: Dictionary) -> String:
	if card.get("text", "") != "":
		return card.text
	var parts: Array[String] = []
	var potion: Dictionary = card.get("potion", {})
	if potion.has("heal"):
		var heal: Variant = potion.heal
		parts.append(("Recupera %s de Corpo." if heal is String else "Recupera até %d de Corpo.") % [heal])
	if potion.has("next_attack_bonus_dice"):
		parts.append("+%d dados no próximo ataque." % int(potion.next_attack_bonus_dice))
	if potion.has("next_defend_bonus_dice"):
		parts.append("+%d dados na próxima defesa." % int(potion.next_defend_bonus_dice))
	if potion.has("next_move_dice_mult"):
		parts.append("Dobra os dados do próximo movimento.")
	if potion.has("extra_attacks"):
		parts.append("Um ataque a mais neste turno.")
	if card.has("item") and card.item.get("kill_adjacent_tag", "") == "undead":
		parts.append("Destrói um morto-vivo colado em você (gasta a ação).")
	if not parts.is_empty():
		return " ".join(parts)
	return equipment_effect(card)


## Efeito de uma peça da armeria/artefato em poucas palavras.
static func equipment_effect(item: Dictionary) -> String:
	var parts: Array[String] = []
	if item.has("attack"):
		parts.append("Ataque %d" % int(item.attack))
	if item.has("defend_bonus"):
		parts.append("+%d Defesa" % int(item.defend_bonus))
	if item.get("diagonal", false):
		parts.append("diagonal")
	if item.get("ranged", false):
		parts.append("à distância")
	if item.get("throwable", false):
		parts.append("arremessável")
	if item.get("two_handed", false):
		parts.append("duas mãos")
	if item.has("move_dice_override"):
		parts.append("movimento %dd6" % int(item.move_dice_override))
	if item.get("disarm_traps", false):
		parts.append("desarma armadilhas")
	var text := ", ".join(parts)
	if item.get("wizard_only", false):
		text += ". Só o Mago."
	elif item.has("wizard_ok") and not item.wizard_ok:
		text += ". O Mago não pode usar."
	return text


## Linha de regra no pé da carta (o lembrete pequeno das cartas originais).
static func rule_text(card: Dictionary, kind: String) -> String:
	match kind:
		"equipment":
			return "Custa %d moedas de ouro." % int(card.get("price", 0)) if card.has("price") else ""
		"spell", "chaos":
			return "Pode ser lançado uma vez por quest."
		"artifact":
			return "Tesouro da quest: fica com o herói."
	if card.has("potion") or card.has("item"):
		return "Guarde esta carta até usá-la; depois devolva-a ao baralho."
	if card.get("id", "") == "quest":
		return ""
	return "Devolva a carta ao baralho."


func _setup_size(width: int) -> void:
	custom_minimum_size = Vector2(width, roundf(width * ASPECT))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if interactive else Control.CURSOR_ARROW
	if not interactive:
		mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))


## Carta branca de moldura rasgada com a ilustração a nanquim.
func _build_ink(card: Dictionary, kind: String, width: int, text: String) -> void:
	var small := width < 150
	var k := width / 230.0
	add_theme_stylebox_override("panel", CardStyle.card_box("ink", width * 0.085))
	var title: String = card.get("name_pt", card.get("name", ""))
	tooltip_text = "%s\n%s" % [title, text]
	var col := _column(roundi(5 * k))

	col.add_child(CardStyle.label(title, CardStyle.title_font(), maxi(9, roundi(22 * k))))
	if (kind == "spell" or kind == "chaos") and not small:
		var schools: Dictionary = GameData.module("spells").schools
		var school: String = card.get("school", "")
		col.add_child(CardStyle.label("Feitiço do Caos" if kind == "chaos" else "Escola: %s" % schools.get(school, school),
			CardStyle.italic_font(), roundi(12 * k), Hud.SCHOOL_COLORS.get(school, CardStyle.INK).darkened(0.5)))

	var art_w := width * 0.83 - 4
	col.add_child(_art_frame(card, Vector2(art_w, art_w * 0.76), Color.BLACK, true))

	if text != "":
		var effect := CardStyle.label(text, CardStyle.body_font(), maxi(8, roundi(14 * k)))
		effect.custom_minimum_size = Vector2(art_w, 0)
		if small:  # o texto ocupa o que sobra e é cortado: a carta não passa da proporção
			effect.clip_text = true
			effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			effect.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			effect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(effect)

	if not (small and text != ""):
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(spacer)
	if not small:
		var rule := rule_text(card, kind)
		if rule != "":
			col.add_child(CardStyle.label(rule, CardStyle.body_font(), roundi(10 * k)))
		if kind == "treasure":
			col.add_child(CardStyle.ribbon("HeroQuest", roundi(15 * k)))


## Carta de monstro: pergaminho, ícones nos cantos e atributos por extenso.
func _build_monster(monster: Dictionary, width: int) -> void:
	var k := width / 230.0
	add_theme_stylebox_override("panel", CardStyle.card_box("parchment", width * 0.09))
	var col := _column(roundi(4 * k))
	var title: String = monster.get("name", "")
	tooltip_text = title

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var icon_size := roundi(26 * k)
	head.add_child(_monster_icon(icon_size))
	var name_label := CardStyle.label(title, CardStyle.title_font(), maxi(9, roundi(22 * k)))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var balance := Control.new()  # mantém o nome no centro
	balance.custom_minimum_size = Vector2(icon_size, icon_size)
	balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(balance)

	var art_w := width * 0.82 - 4
	col.add_child(_art_frame(monster, Vector2(art_w, art_w * 0.82), CardStyle.FRAME, false))

	var lines := "Movimento: %d casas\nAtaque: %d dados\nDefesa: %d dados\nCorpo: %d\nMente: %d" % [
		int(monster.get("move", 0)), int(monster.get("attack", 0)), int(monster.get("defend", 0)),
		int(monster.get("body", 0)), int(monster.get("mind", 0))]
	var stats := CardStyle.label(lines, CardStyle.body_font(), maxi(7, roundi(14 * k)))
	stats.add_theme_constant_override("line_spacing", roundi(-2 * k))
	col.add_child(stats)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(_monster_icon(icon_size))
	col.add_child(foot)


## Verso: a pintura de ponta a ponta numa moldura escura, com a faixa do nome.
func _build_back(back: Array, width: int) -> void:
	var k := width / 230.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.06, 0.05)
	box.border_color = CardStyle.FRAME
	box.set_border_width_all(roundi(6 * k))
	box.set_corner_radius_all(roundi(10 * k))
	box.set_content_margin_all(roundi(6 * k))
	add_theme_stylebox_override("panel", box)
	var stack := Control.new()
	stack.clip_contents = true
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	var path: String = ART % back[0]
	if ResourceLoader.exists(path):
		stack.add_child(CardStyle.picture(load(path)))
	var ribbon := CardStyle.ribbon(back[1], roundi(18 * k))
	ribbon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ribbon.offset_bottom = -roundi(14 * k)
	stack.add_child(ribbon)


func _column(separation: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", separation)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	return col


## Quadro da ilustração (nanquim na carta branca, colorida no pergaminho).
func _art_frame(card: Dictionary, art_size: Vector2, border: Color, ink: bool) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", CardStyle.frame_box(border, 2, Color(0.1, 0.08, 0.06)))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := Control.new()
	art.custom_minimum_size = art_size
	art.clip_contents = true
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)
	var ink_path := INK_ART % _art_id(card)
	var path := art_path(card)
	if ink and ResourceLoader.exists(ink_path):
		art.add_child(CardStyle.picture(load(ink_path)))
	elif ResourceLoader.exists(path):
		art.add_child(CardStyle.picture(load(path), CardStyle.ink_material() if ink else null))
	else:
		var initial := CardStyle.label(String(card.get("name_pt", card.get("name", "?"))).left(1), CardStyle.title_font(),
			roundi(art_size.y * 0.6), CardStyle.PARCHMENT)
		initial.set_anchors_preset(Control.PRESET_FULL_RECT)
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		art.add_child(initial)
	return frame


## Selo redondo do monstro (caveira num disco de borda preta).
func _monster_icon(size: int) -> Control:
	var disc := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.95, 0.92, 0.84)
	box.border_color = Color(0.08, 0.06, 0.05)
	box.set_border_width_all(maxi(1, size / 12))
	box.set_corner_radius_all(size)
	box.set_content_margin_all(size * 0.18)
	disc.add_theme_stylebox_override("panel", box)
	disc.custom_minimum_size = Vector2(size, size)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skull := TextureRect.new()
	skull.texture = DieView._texture(Dice.SKULL, Color(0.95, 0.92, 0.84))
	skull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(skull)
	return disc


func _draw() -> void:
	if selected:
		draw_rect(Rect2(Vector2.ONE * 1.5, size - Vector2.ONE * 3), Color(1.0, 0.82, 0.25), false, 3.0)


## Cresce a partir da base quando o mouse passa em cima (como erguer a carta da mão).
func _hover(on: bool) -> void:
	_hovered = on
	z_index = 2 if on else (1 if selected else 0)
	_lift(1.7 if on else (1.15 if selected else 1.0))


func _lift(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * to, 0.12)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and interactive:  # carta de mão cresce a partir da base
		pivot_offset = Vector2(size.x / 2, size.y)


func _gui_input(event: InputEvent) -> void:
	if disabled or not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
