extends SceneTree
## Prepara a arte crua do tools/gen_board.py (assets/textures/raw/, sem import):
##   temas  → board/themes/<tema>/<parte>_albedo.png + _normal.png
##            (a parede fica repetível para o triplanar em mundo do BoardView)
##   papel  → furniture/paper/<id>_<face>.png no aspecto da face
##            (PaperFurniture.face_size); recortes ganham a borda branca de papel,
##            o tampo ganha uma moldura fina.
##
##   $G --headless --path . --script res://tools/prep_board_textures.gd [--force]
## Depois: $G --headless --path . --import

const RAW := "res://assets/textures/raw/"
const THEMES_OUT := "res://assets/textures/board/themes/%s/%s_%s.png"
const PAPER_OUT := "res://assets/textures/furniture/paper/%s_%s.png"
const MAX_SIDE := 1024
const PAPER_BORDER := 5     # px da borda de papel recortado
const TOP_FRAME := 6        # px da moldura do tampo
const NORMAL_STRENGTH := 2.5

var force := false


func _init() -> void:
	force = "--force" in OS.get_cmdline_user_args() or "--force" in OS.get_cmdline_args()
	_themes()
	_paper()
	quit()


# ---------------------------------------------------------------- temas

func _themes() -> void:
	var root := RAW + "themes/"
	for theme in _dirs(root):
		for file in _pngs(root + theme):
			var part := file.get_basename()
			var albedo := THEMES_OUT % [theme, part, "albedo"]
			if not force and FileAccess.file_exists(albedo):
				continue
			var img := _load(root + theme + "/" + file)
			if img == null:
				continue
			img.resize(MAX_SIDE, MAX_SIDE, Image.INTERPOLATE_LANCZOS)
			if part == "wall":
				img = _seamless(img)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(albedo.get_base_dir()))
			img.save_png(albedo)
			_normal_map(img).save_png(THEMES_OUT % [theme, part, "normal"])
			print("ok: ", albedo)


## Mistura a imagem com ela mesma deslocada meia volta: as costuras do
## original (nas bordas) ficam cobertas pelo miolo da cópia.
func _seamless(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var dx := absf(2.0 * x / w - 1.0)
			var dy := absf(2.0 * y / h - 1.0)
			var t := smoothstep(0.55, 1.0, maxf(dx, dy))
			var a := img.get_pixel(x, y)
			var b := img.get_pixel((x + w / 2) % w, (y + h / 2) % h)
			out.set_pixel(x, y, a.lerp(b, t))
	return out


## Normal map pelo brilho (Sobel, dando a volta nas bordas para repetir).
func _normal_map(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			lum[y * w + x] = img.get_pixel(x, y).get_luminance()
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		var up := ((y - 1 + h) % h) * w
		var mid := y * w
		var down := ((y + 1) % h) * w
		for x in w:
			var l := (x - 1 + w) % w
			var r := (x + 1) % w
			var gx := (lum[up + r] + 2.0 * lum[mid + r] + lum[down + r]) \
				- (lum[up + l] + 2.0 * lum[mid + l] + lum[down + l])
			var gy := (lum[down + l] + 2.0 * lum[down + x] + lum[down + r]) \
				- (lum[up + l] + 2.0 * lum[up + x] + lum[up + r])
			var n := Vector3(-gx * NORMAL_STRENGTH, gy * NORMAL_STRENGTH, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	return out


# ---------------------------------------------------------------- papel

func _paper() -> void:
	var sizes := {"rubble": Vector2i(1, 1)}
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/furniture.json"))
	for f: Dictionary in data.furniture:
		sizes[f.id] = Vector2i(int(f.size[0]), int(f.size[1]))
	var root := RAW + "paper/"
	for file in _pngs(root):
		var name := file.get_basename()
		var cut := name.rfind("_")
		var id := name.substr(0, cut)
		var face := name.substr(cut + 1)
		if not sizes.has(id) or not PaperFurniture.HEIGHT.has(id):
			push_warning("móvel desconhecido: " + file)
			continue
		var out_path := PAPER_OUT % [id, face]
		if not force and FileAccess.file_exists(out_path):
			continue
		var img := _load(root + file)
		if img == null:
			continue
		var meters := PaperFurniture.face_size(id, face, sizes[id])
		var px := _pixels(meters)
		img.convert(Image.FORMAT_RGBA8)
		if face == "top":
			img = _top(img, px)
		else:
			img = _cutout(img, px)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
		img.save_png(out_path)
		print("ok: ", out_path, " ", px)


## Lado maior em MAX_SIDE, o outro no aspecto da face (mínimo 64 px).
func _pixels(meters: Vector2) -> Vector2i:
	var s := MAX_SIDE / maxf(meters.x, meters.y)
	return Vector2i(maxi(64, roundi(meters.x * s)), maxi(64, roundi(meters.y * s)))


## Tampo: corta o meio no aspecto certo, redimensiona e põe a moldura branca.
func _top(img: Image, px: Vector2i) -> Image:
	var aspect := float(px.x) / px.y
	var w := img.get_width()
	var h := img.get_height()
	var crop := Rect2i(0, 0, w, h)
	if float(w) / h > aspect:
		crop.size.x = roundi(h * aspect)
		crop.position.x = (w - crop.size.x) / 2
	else:
		crop.size.y = roundi(w / aspect)
		crop.position.y = (h - crop.size.y) / 2
	var out := img.get_region(crop)
	out.resize(px.x, px.y, Image.INTERPOLATE_LANCZOS)
	var white := Color(0.97, 0.95, 0.90)
	out.fill_rect(Rect2i(0, 0, px.x, TOP_FRAME), white)
	out.fill_rect(Rect2i(0, px.y - TOP_FRAME, px.x, TOP_FRAME), white)
	out.fill_rect(Rect2i(0, 0, TOP_FRAME, px.y), white)
	out.fill_rect(Rect2i(px.x - TOP_FRAME, 0, TOP_FRAME, px.y), white)
	return out


## Recorte: corta no contorno do desenho, estica para a face (menos a borda) e
## pinta de branco o que o contorno engordado cobre (papel recortado à tesoura).
func _cutout(img: Image, px: Vector2i) -> Image:
	var used := _solid_rect(img)
	if used.size.x > 0:
		img = img.get_region(used)
	var b := PAPER_BORDER
	img.resize(px.x - 2 * b, px.y - b, Image.INTERPOLATE_LANCZOS)
	# Encostado embaixo (a peça fica no chão), com a borda dos outros lados.
	var out := Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(b, b))
	var solid := _alpha_mask(out)
	var grown := _dilate(solid, px, b)
	var paper := Color(0.97, 0.95, 0.90)
	for y in px.y:
		for x in px.x:
			var i := y * px.x + x
			var c := out.get_pixel(x, y)
			if solid[i]:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			elif grown[i]:
				out.set_pixel(x, y, paper)
			else:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


## Retângulo do que é desenho de fato (alfa > 0.5); o get_used_rect conta
## também a névoa quase transparente que a OpenAI deixa em volta.
func _solid_rect(img: Image) -> Rect2i:
	var lo := Vector2i(img.get_width(), img.get_height())
	var hi := Vector2i(-1, -1)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE) if hi.x >= 0 else Rect2i()


func _alpha_mask(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var mask := PackedByteArray()
	mask.resize(w * img.get_height())
	for y in img.get_height():
		for x in w:
			mask[y * w + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	return mask


## Engorda a máscara `r` px (quadrado, em duas passadas).
func _dilate(mask: PackedByteArray, px: Vector2i, r: int) -> PackedByteArray:
	var tmp := PackedByteArray()
	tmp.resize(mask.size())
	for y in px.y:
		for x in px.x:
			for k in range(maxi(0, x - r), mini(px.x, x + r + 1)):
				if mask[y * px.x + k]:
					tmp[y * px.x + x] = 1
					break
	var out := PackedByteArray()
	out.resize(mask.size())
	for y in px.y:
		for x in px.x:
			for k in range(maxi(0, y - r), mini(px.y, y + r + 1)):
				if tmp[k * px.x + x]:
					out[y * px.x + x] = 1
					break
	return out


# ---------------------------------------------------------------- arquivos

func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		push_warning("não abriu: " + path)
	return img


func _dirs(path: String) -> PackedStringArray:
	var d := DirAccess.open(path)
	return d.get_directories() if d else PackedStringArray()


func _pngs(path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(path)
	if d:
		for f in d.get_files():
			if f.get_extension() == "png":
				out.append(f)
	return out
