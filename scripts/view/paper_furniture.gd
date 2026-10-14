class_name PaperFurniture
extends RefCounted
## Móvel de papel dobrado: uma caixa de cartão com as faces pintadas
## (tools/gen_board.py --paper + tools/prep_board_textures.gd). O tampo é a
## arte vista de cima; frente/costas e lados são recortes com fundo
## transparente e borda branca de papel. Escada e entulho são placas finas,
## como as peças de papelão do jogo.
##
## A peça vem centrada na origem, no tamanho "sem giro" do furniture.json, com
## a frente para +Z (a mesma convenção dos .glb; o BoardView gira por rot).

const TEXTURE := "res://assets/textures/furniture/paper/%s_%s.png"

## Altura de cada peça em m (o gen_board.py usa os mesmos números).
const HEIGHT := {
	"table": 0.42, "sorcerers_table": 0.42, "alchemists_bench": 0.42,
	"tomb": 0.5, "rack": 0.5,
	"bookcase": 0.9, "cupboard": 0.9, "fireplace": 0.7, "weapons_rack": 0.8,
	"throne": 0.8, "treasure_chest": 0.35,
	"stairway": 0.03, "rubble": 0.03,
}
## Silhueta recortada demais para virar caixa: um recorte em pé no meio da
## pegada, numa base de papelão (como um standee).
const STANDEE := ["throne"]
## Peças que usam a arte de outra.
const ART_ALIAS := {"blocked_single": "rubble", "blocked_double": "rubble"}
## Folga até a borda dos quadrados (a mesma da caixa provisória do BoardView).
const MARGIN := 0.12
## As paredes ficam um pouco para dentro do tampo, como cartão dobrado.
const INSET := 0.015
## Abaixo disso a peça é uma placa chata (só o tampo).
const FLAT := 0.05
const EDGE_COLOR := Color(0.93, 0.90, 0.82)  # miolo do papelão

static var _mats: Dictionary = {}


static func art_id(id: String) -> String:
	return ART_ALIAS.get(id, id)


## Tamanho em m de cada face ("top", "front", "side") para uma pegada `size`.
static func face_size(id: String, face: String, size: Vector2i) -> Vector2:
	var w := size.x - MARGIN
	var d := size.y - MARGIN
	var h: float = HEIGHT[art_id(id)]
	match face:
		"top":
			return Vector2(w, d)
		"front":
			return Vector2(w, h)
	return Vector2(d, h)


## A peça montada, ou null se faltar a arte (o BoardView cai no .glb/caixa).
static func build(id: String, size: Vector2i) -> Node3D:
	var art := art_id(id)
	var face := "front" if art in STANDEE else "top"
	if not HEIGHT.has(art) or not ResourceLoader.exists(TEXTURE % [art, face]):
		return null
	var h: float = HEIGHT[art]
	var top_size := face_size(id, "top", size)
	var root := Node3D.new()
	if art in STANDEE:
		var base := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(top_size.x, 0.02, top_size.y * 0.5)
		base.mesh = plate
		base.material_override = _edge_material()
		base.position.y = 0.01
		root.add_child(base)
		_quad(root, art, "front", Vector2(top_size.x, h), Vector3(0, h / 2.0 + 0.02, 0), Vector3.ZERO)
		return root
	if h <= FLAT:
		var slab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(top_size.x, h, top_size.y)
		slab.mesh = box
		slab.material_override = _edge_material()
		slab.position.y = h / 2.0
		root.add_child(slab)
		_quad(root, art, "top", top_size, Vector3(0, h + 0.001, 0), Vector3.ZERO, true)
		return root
	_quad(root, art, "top", top_size, Vector3(0, h, 0), Vector3.ZERO, true)
	var front := Vector2(top_size.x - 2 * INSET, h)
	var side := Vector2(top_size.y - 2 * INSET, h)
	var side_art := "side" if ResourceLoader.exists(TEXTURE % [art, "side"]) else "front"
	var hz := top_size.y / 2.0 - INSET
	var hx := top_size.x / 2.0 - INSET
	_quad(root, art, "front", front, Vector3(0, h / 2.0, hz), Vector3.ZERO)
	_quad(root, art, "front", front, Vector3(0, h / 2.0, -hz), Vector3(0, PI, 0))
	_quad(root, art, side_art, side, Vector3(hx, h / 2.0, 0), Vector3(0, PI / 2.0, 0))
	_quad(root, art, side_art, side, Vector3(-hx, h / 2.0, 0), Vector3(0, -PI / 2.0, 0))
	return root


## Um plano com a face pintada; `flat` = deitado (tampo), senão em pé virado
## para +Z antes do giro `rot`.
static func _quad(root: Node3D, art: String, face: String, size: Vector2, pos: Vector3,
		rot: Vector3, flat := false) -> void:
	var mesh := QuadMesh.new()
	mesh.size = size
	if flat:
		mesh.orientation = PlaneMesh.FACE_Y
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(TEXTURE % [art, face], not flat)
	node.position = pos
	node.rotation = rot
	root.add_child(node)


static func _material(path: String, cutout: bool) -> StandardMaterial3D:
	if _mats.has(path):
		return _mats[path]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(path)
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	_mats[path] = mat
	return mat


static func _edge_material() -> StandardMaterial3D:
	if not _mats.has("edge"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = EDGE_COLOR
		mat.roughness = 1.0
		_mats["edge"] = mat
	return _mats["edge"]
