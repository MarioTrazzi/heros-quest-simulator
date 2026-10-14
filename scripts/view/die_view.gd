class_name DieView
extends Node3D
## Um dado 3D: modelo do Blender (assets/models/dice/<combat|d6>.glb, feito por
## tools/blender/build_dice.py) ou, sem ele, cubo com faces desenhadas em código.
## O valor já vem sorteado pelo Dice do GameState; a `DiceTray` joga o dado com
## física (`DiceSim`) e `show_face` gira só o desenho (`model`) para que a face
## que caiu para cima mostre a marca sorteada.
##
## Ordem das faces: +Y, -Y, +X, -X, +Z, -Z (o modelo segue a mesma ordem).

const NORMALS: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
## Dado de combate: 3 caveiras, 2 escudos brancos (herói), 1 preto (monstro).
const COMBAT_FACES: Array[String] = [Dice.SKULL, Dice.SKULL, Dice.SKULL, Dice.WHITE_SHIELD, Dice.WHITE_SHIELD, Dice.BLACK_SHIELD]
## d6 com faces opostas somando 7.
const D6_FACES: Array[String] = ["1", "6", "2", "5", "3", "4"]
const TEX_SIZE := 64
const BODY_COLOR := Color(0.93, 0.91, 0.85)
const INK := Color(0.08, 0.07, 0.07)
const MODEL := "res://assets/models/dice/%s.glb"

static var _textures: Dictionary = {}

var faces: Array[String] = []
## Desenho do dado (modelo ou faces), girado dentro do nó por `show_face`.
var model := Node3D.new()


static func combat() -> DieView:
	return _make(COMBAT_FACES, BODY_COLOR, "combat")


static func d6() -> DieView:
	return _make(D6_FACES, Color(0.75, 0.12, 0.10), "d6")


static func _make(face_keys: Array[String], body: Color, model: String) -> DieView:
	var die := DieView.new()
	die.faces = face_keys
	die.add_child(die.model)
	if ResourceLoader.exists(MODEL % model):
		die.model.add_child((load(MODEL % model) as PackedScene).instantiate())
		return die
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i in 6:
		var n := NORMALS[i]
		var face := MeshInstance3D.new()
		face.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _texture(face_keys[i], body)
		face.material_override = mat
		# QuadMesh olha para +Z; looking_at aponta -Z para o alvo.
		var up := Vector3.FORWARD if absf(n.y) > 0.5 else Vector3.UP
		face.transform = Transform3D(Basis.looking_at(-n, up), n * 0.5)
		die.model.add_child(face)
	return die


## O nó caiu com a face `landed` (índice de NORMALS) para cima: gira o desenho
## para que lá apareça uma das faces com a marca `key`.
func show_face(key: String, landed: int) -> void:
	var options: Array[int] = []
	for i in faces.size():
		if faces[i] == key:
			options.append(i)
	var from := NORMALS[options.pick_random()]
	var to := NORMALS[landed]
	if from == to:
		model.basis = Basis.IDENTITY
	elif from == -to:
		# Meia volta em torno de um eixo perpendicular.
		var axis := Vector3.RIGHT if absf(from.x) < 0.5 else Vector3.UP
		model.basis = Basis(axis, PI)
	else:
		model.basis = Basis(Quaternion(from, to))


## Cresce um pouco (e sobe junto, para continuar apoiado no fundo).
func highlight() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "scale", scale * 1.25, 0.15).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "position:y", position.y + scale.y * 0.125, 0.15)


# ---------- texturas ----------

static func _texture(key: String, body: Color) -> Texture2D:
	var cache_key := "%s_%s" % [key, body.to_html()]
	if _textures.has(cache_key):
		return _textures[cache_key]
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(body)
	_rect(img, 0, 0, TEX_SIZE, 2, body.darkened(0.35))
	_rect(img, 0, TEX_SIZE - 2, TEX_SIZE, 2, body.darkened(0.35))
	_rect(img, 0, 0, 2, TEX_SIZE, body.darkened(0.35))
	_rect(img, TEX_SIZE - 2, 0, 2, TEX_SIZE, body.darkened(0.35))
	match key:
		Dice.SKULL:
			_draw_skull(img, body)
		Dice.WHITE_SHIELD:
			_draw_shield(img, INK, 0)
			_draw_shield(img, Color.WHITE, 4)
			_rect(img, 30, 18, 4, 30, Color(0.2, 0.4, 0.85))
			_rect(img, 21, 26, 22, 4, Color(0.2, 0.4, 0.85))
		Dice.BLACK_SHIELD:
			_draw_shield(img, INK, 0)
		_:
			_draw_pips(img, int(key))
	var tex := ImageTexture.create_from_image(img)
	_textures[cache_key] = tex
	return tex


static func _draw_skull(img: Image, body: Color) -> void:
	_circle(img, 32, 27, 17, INK)
	_rect(img, 22, 36, 21, 15, INK)
	_circle(img, 25, 28, 5, body)
	_circle(img, 39, 28, 5, body)
	_rect(img, 31, 34, 3, 5, body)
	for x in [26, 31, 36]:
		_rect(img, x, 44, 2, 7, body)


## Escudo: retângulo em cima, ponta arredondada embaixo. `inset` encolhe.
static func _draw_shield(img: Image, color: Color, inset: int) -> void:
	var left := 14 + inset
	var right := 50 - inset
	var top := 10 + inset
	var mid := 34
	var bottom := 56 - inset
	for y in range(top, bottom):
		var half := (right - left) / 2.0
		if y > mid:
			half *= sqrt(maxf(0.0, 1.0 - pow(float(y - mid) / (bottom - mid), 2.0)))
		var cx := (left + right) / 2.0
		for x in range(int(cx - half), int(cx + half)):
			img.set_pixel(x, y, color)


static func _draw_pips(img: Image, value: int) -> void:
	var spots := {
		1: [Vector2i(32, 32)],
		2: [Vector2i(18, 18), Vector2i(46, 46)],
		3: [Vector2i(18, 18), Vector2i(32, 32), Vector2i(46, 46)],
		4: [Vector2i(18, 18), Vector2i(46, 18), Vector2i(18, 46), Vector2i(46, 46)],
		5: [Vector2i(18, 18), Vector2i(46, 18), Vector2i(32, 32), Vector2i(18, 46), Vector2i(46, 46)],
		6: [Vector2i(18, 16), Vector2i(46, 16), Vector2i(18, 32), Vector2i(46, 32), Vector2i(18, 48), Vector2i(46, 48)],
	}
	for p: Vector2i in spots.get(value, []):
		_circle(img, p.x, p.y, 6, Color.WHITE)


static func _rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), color)


static func _circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, color)
