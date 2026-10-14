class_name CardStyle
extends RefCounted
## Aparência do papel do HeroQuest europeu de 1989, comum às cartas (GameCard),
## à ficha do herói (HeroSheet) e ao livro de quests:
##  - "parchment": pergaminho amarelado de bordas queimadas (carta de
##    personagem, carta de monstro, livro de quests);
##  - "ink": carta branca com moldura marrom de borda rasgada (tesouro,
##    feitiço, equipamento, artefato), com a ilustração em nanquim.
## As texturas são geradas em código uma vez (sem arquivos) e esticadas na
## proporção da carta (54 × 80 mm).

const INK := Color(0.16, 0.11, 0.07)  # tinta dos textos
const FRAME := Color(0.27, 0.19, 0.12)  # moldura marrom da carta branca
const PAPER := Color(0.96, 0.94, 0.88)  # miolo da carta branca
const PARCHMENT := Color(0.91, 0.82, 0.60)
const BURNT := Color(0.42, 0.22, 0.08)
const RED := Color(0.55, 0.10, 0.07)
const GOLD := Color(0.86, 0.68, 0.30)

const TITLE_FONT := "res://assets/fonts/Fondamento-Italic.ttf"
const BODY_FONT := "res://assets/fonts/CrimsonText-Regular.ttf"
const ITALIC_FONT := "res://assets/fonts/CrimsonText-Italic.ttf"

## Textura em 10 px por mm da carta.
const TEX_SIZE := Vector2i(540, 800)

static var _cache := {}


## Título em cursiva caligráfica (nomes das cartas, do herói, da quest).
static func title_font() -> Font:
	return _font(TITLE_FONT)


## Texto corrido, como a tipografia impressa das cartas.
static func body_font() -> Font:
	return _font(BODY_FONT)


static func italic_font() -> Font:
	return _font(ITALIC_FONT)


static func _font(path: String) -> Font:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
	return _cache[path]


## Fundo da carta: StyleBoxTexture com o papel do estilo pedido.
static func card_box(style: String, margin: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = paper_texture(style)
	box.set_content_margin_all(margin)
	return box


static func paper_texture(style: String) -> Texture2D:
	var key := "paper_" + style
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(_ink_card() if style == "ink" else _parchment())
	return _cache[key]


## Pergaminho: creme manchado que escurece e queima nas bordas irregulares.
static func _parchment() -> Image:
	var img := Image.create(TEX_SIZE.x, TEX_SIZE.y, false, Image.FORMAT_RGBA8)
	var stain := _noise(7, 0.008)
	var edge := _noise(11, 0.02)
	for y in TEX_SIZE.y:
		for x in TEX_SIZE.x:
			var d := _edge_distance(x, y, 26.0) + edge.get_noise_2d(x, y) * 18.0
			if d < 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := PARCHMENT.darkened(0.12 * (stain.get_noise_2d(x, y) + 0.5))
			# Queimado: marrom escuro colado na borda, clareando até ~45 px dentro.
			var burn := clampf(1.0 - d / 45.0, 0.0, 1.0)
			c = c.lerp(BURNT, burn * burn * 0.9)
			if d < 4.0:
				c = c.lerp(Color(0.12, 0.06, 0.02), 0.8)
			img.set_pixel(x, y, c)
	return img


## Carta branca: moldura marrom grossa com o lado de dentro rasgado.
static func _ink_card() -> Image:
	var img := Image.create(TEX_SIZE.x, TEX_SIZE.y, false, Image.FORMAT_RGBA8)
	var tear := _noise(5, 0.03)
	var grain := _noise(9, 0.05)
	for y in TEX_SIZE.y:
		for x in TEX_SIZE.x:
			var d := _edge_distance(x, y, 34.0)
			if d < 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var border := 30.0 + tear.get_noise_2d(x, y) * 14.0
			var c: Color
			if d < border:
				c = FRAME.darkened(0.15 * grain.get_noise_2d(x, y))
			else:
				c = PAPER.darkened(0.03 * (grain.get_noise_2d(x * 2, y * 2) + 0.5))
			img.set_pixel(x, y, c)
	return img


## Distância até a borda do retângulo de cantos arredondados (negativa = fora).
static func _edge_distance(x: int, y: int, radius: float) -> float:
	var w := float(TEX_SIZE.x)
	var h := float(TEX_SIZE.y)
	var px := float(x) + 0.5
	var py := float(y) + 0.5
	var dx := maxf(radius - px, px - (w - radius))
	var dy := maxf(radius - py, py - (h - radius))
	if dx > 0.0 and dy > 0.0:
		return radius - Vector2(dx, dy).length()
	return minf(minf(px, w - px), minf(py, h - py))


static func _noise(seed: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = frequency
	noise.fractal_octaves = 3
	return noise


## Material que deixa a pintura com cara de ilustração a nanquim (preto e
## branco, contraste alto, hachura nas sombras) — o traço das cartas de 1989.
static func ink_material() -> ShaderMaterial:
	if not _cache.has("ink_material"):
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;
// Esboço por "color dodge": cinza ÷ (1 − desfoque do negativo). Áreas lisas
// (inclusive o fundo escuro das pinturas) ficam brancas; só sobram os traços.
uniform float radius = 2.5;
uniform float darkness = 0.55;
float gray(sampler2D tex, vec2 uv) {
	return dot(texture(tex, uv).rgb, vec3(0.299, 0.587, 0.114));
}
void fragment() {
	float g = gray(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * radius;
	float blur = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			blur += 1.0 - gray(TEXTURE, UV + vec2(float(x), float(y)) * px);
		}
	}
	blur /= 25.0;
	float sketch = clamp(g / max(1.0 - blur, 0.001), 0.0, 1.0);
	// Traço mais preto e um pouco de sombra (hachura) onde a pintura é escura.
	float line = smoothstep(0.55, 0.92, sketch);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	float hatch = step(0.3, fract((p.x + p.y) / 5.0));  // linhas finas
	float shade = mix(1.0, hatch, darkness * smoothstep(0.35, 0.05, g));
	float v = line * shade;
	COLOR = vec4(vec3(mix(0.08, 0.97, v)) * vec3(1.0, 0.98, 0.93), texture(TEXTURE, UV).a);
}
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		_cache["ink_material"] = material
	return _cache["ink_material"]


## Rótulo pronto: fonte, tamanho, cor e alinhamento centralizado com quebra.
static func label(text: String, font: Font, size: int, color := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Imagem recortada para preencher a área (sem distorcer), com material opcional.
static func picture(texture: Texture2D, material: Material = null) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	return rect


## Moldura fina (preta na carta branca; dourada no retrato do herói).
static func frame_box(border: Color, width: int, bg := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	return box


## Faixa de pergaminho com texto (rodapé "HeroQuest" do tesouro, nome no verso).
static func ribbon(text: String, size: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.93, 0.88, 0.76)
	box.border_color = FRAME
	box.set_border_width_all(maxi(1, size / 8))
	box.set_corner_radius_all(maxi(2, size / 3))
	box.content_margin_left = size * 0.8
	box.content_margin_right = size * 0.8
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", box)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label(text, title_font(), size, INK, false))
	return panel


## Põe o tema do jogo no tema padrão do Godot: vale para toda tela, inclusive
## dentro de CanvasLayer e de nós 3D (onde a herança de tema não chega).
static func apply_theme() -> void:
	ThemeDB.fallback_font = body_font()
	ThemeDB.fallback_font_size = 18
	ThemeDB.get_default_theme().merge_with(theme())


## Tema do jogo todo (CardStyle.apply_theme, chamado pelo Session): textos em Crimson
## Text, botões de pergaminho com título em cursiva, painéis de couro escuro com
## borda dourada, campos e dicas em pergaminho.
static func theme() -> Theme:
	if _cache.has("theme"):
		return _cache["theme"]
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18

	t.set_color("font_color", "Label", Color(0.93, 0.88, 0.76))
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("italics_font", "RichTextLabel", italic_font())
	t.set_font("bold_font", "RichTextLabel", title_font())
	t.set_color("default_color", "RichTextLabel", Color(0.93, 0.88, 0.76))

	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", RED)
	t.set_color("font_pressed_color", "Button", RED.darkened(0.3))
	t.set_color("font_hover_pressed_color", "Button", RED.darkened(0.3))
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.45))
	t.set_stylebox("normal", "Button", button_box(PARCHMENT, FRAME))
	t.set_stylebox("hover", "Button", button_box(PARCHMENT.lightened(0.15), GOLD))
	t.set_stylebox("pressed", "Button", button_box(PARCHMENT.darkened(0.15), RED))
	t.set_stylebox("hover_pressed", "Button", button_box(PARCHMENT.darkened(0.1), GOLD))
	t.set_stylebox("disabled", "Button", button_box(PARCHMENT.darkened(0.35), FRAME.darkened(0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.08, 0.06, 0.92)
	panel.border_color = GOLD.darkened(0.35)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", panel)

	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.95, 0.9, 0.78)
	field.border_color = FRAME
	field.set_border_width_all(2)
	field.set_corner_radius_all(3)
	field.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", field)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = GOLD
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	t.set_color("caret_color", "LineEdit", INK)

	var tip := field.duplicate() as StyleBoxFlat
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", body_font())
	_cache["theme"] = t
	return t


## Plaquinha de pergaminho dos botões: papel manchado, borda marrom (dourada
## com o mouse em cima) e uma sombra curta.
static func button_box(paper: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = paper
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 2)
	return box


## Fundo das telas fora da partida (menu, campanha, lobby): a pintura do baú,
## bem escurecida.
static func backdrop() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var path := GameCard.ART % "treasure_horde"
	if ResourceLoader.exists(path):
		var art := picture(load(path))
		art.modulate = Color(0.32, 0.27, 0.24)
		bg.add_child(art)
	return bg


## Título dourado em cursiva das telas (Campanha, Quests, Armeria...).
static func heading(text: String, size: int) -> Label:
	var l := label(text, title_font(), size, GOLD, false)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	l.add_theme_constant_override("outline_size", 4)
	return l


## Selo de situação (quest próxima, cumprida...): plaquinha colorida com texto claro.
static func seal(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = color.darkened(0.4)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", box)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_child(label(text, title_font(), 16, Color(0.98, 0.94, 0.84), false))
	return panel
