class_name BoardView
extends Node3D
## Tabuleiro em 3D: piso, paredes geradas a partir do Board, portas, móveis,
## marcadores de armadilha, névoa e as marcas de destaque (alcance, caminho,
## alvo). Só desenha; regra é do GameState. 1 quadrado = 1 m; o quadrado
## (x, y) fica centrado em (x + 0.5, 0, y + 0.5).
##
## Névoa: a planta (piso e paredes) aparece sempre, como no tabuleiro de
## papelão; o que não foi revelado fica escuro, e portas, móveis e blocos
## só aparecem quando um quadrado deles é revelado. A área fora da quest
## (board.dark) não tem piso e é cercada de paredes.

## Texturas e modelos do Blender (tools/blender/build_board.py). Sem eles,
## piso, paredes e portas caem nas cores lisas abaixo.
const TEXTURE := "res://assets/textures/board/%s_%s.png"
## Tema da quest ("theme" no JSON; tools/gen_board.py --themes): vale antes
## das texturas do Blender, parte por parte.
const THEME_TEXTURE := "res://assets/textures/board/themes/%s/%s_%s.png"
const BOARD_MODEL := "res://assets/models/board/%s.glb"

const WALL_HEIGHT := 0.8
const WALL_THICKNESS := 0.08
const DOOR_HEIGHT := 0.7
const CORRIDOR_COLOR := Color(0.40, 0.38, 0.34)
const ROOM_COLOR := Color(0.62, 0.52, 0.40)
const FOG_COLOR := Color(0.09, 0.09, 0.11)
const WALL_COLOR := Color(0.55, 0.50, 0.42)
const DOOR_COLOR := Color(0.45, 0.27, 0.12)
const PIT_COLOR := Color(0.03, 0.03, 0.03)

const MARK_COLORS := {
	"reach": Color(0.15, 0.50, 1.0, 0.55),
	"path": Color(1.0, 0.85, 0.25, 0.65),
	"target": Color(1.0, 0.25, 0.20, 0.55),
	"door": Color(0.4, 1.0, 0.4, 0.55),
	"disarm": Color(1.0, 0.55, 0.1, 0.6),
	"spell": Color(0.75, 0.30, 1.0, 0.6),
	"spell_out": Color(0.85, 0.10, 0.10, 0.45),  # o feitiço pegaria, mas está fora da vista
	"jump": Color(0.85, 1.0, 0.3, 0.6),
}

## Modelos do Blender (tools/blender/build_furniture.py): a peça vem no tamanho
## "sem giro" do furniture.json, frente para +Z; rot 0..3 = virada para
## baixo/esquerda/cima/direita (convenção do HeroScribe).
const FURNITURE_MODEL := "res://assets/models/furniture/%s.glb"

## Peças de encostar na parede: se o mapa as deixar de frente para a parede
## (o giro do HeroScribe não é consistente entre mapas), viram 180°.
const WALL_BACKED := ["bookcase", "cupboard", "fireplace", "weapons_rack"]
## Frente da peça por rot (0..3), em coordenadas do tabuleiro.
const ROT_FRONT: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

## Altura e cor da caixa provisória de cada móvel sem modelo.
const FURNITURE_LOOK := {
	"table": [0.40, Color(0.50, 0.33, 0.18)],
	"sorcerers_table": [0.40, Color(0.30, 0.22, 0.40)],
	"alchemists_bench": [0.40, Color(0.35, 0.40, 0.30)],
	"tomb": [0.50, Color(0.55, 0.55, 0.58)],
	"rack": [0.50, Color(0.40, 0.28, 0.18)],
	"bookcase": [0.90, Color(0.42, 0.26, 0.14)],
	"cupboard": [0.90, Color(0.48, 0.32, 0.18)],
	"fireplace": [0.70, Color(0.35, 0.33, 0.32)],
	"weapons_rack": [0.80, Color(0.38, 0.36, 0.34)],
	"throne": [0.80, Color(0.60, 0.48, 0.15)],
	"treasure_chest": [0.35, Color(0.62, 0.44, 0.15)],
	"blocked_single": [0.80, Color(0.30, 0.28, 0.26)],
	"blocked_double": [0.80, Color(0.30, 0.28, 0.26)],
}

var board: Board
var theme := ""
var _tiles: Dictionary = {}        # Vector2i -> MeshInstance3D
var _lit: Dictionary = {}          # Vector2i -> material sem névoa
var _fog_mats: Dictionary = {}     # "room"/"corridor" -> material com névoa
var _marks: Dictionary = {}        # Vector2i -> MeshInstance3D
var _mark_mats: Dictionary = {}    # tipo -> material
var _walls: Dictionary = {}        # Vector4i -> MeshInstance3D (paredes internas)
var _door_pivots: Dictionary = {}  # Vector4i -> Node3D
var _traps: Dictionary = {}        # Vector2i -> Node3D
## Peças que só aparecem quando reveladas: [{"node": Node3D, "cells": Array}].
var _hidden: Array[Dictionary] = []


static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)


func build(state: GameState) -> void:
	board = state.board
	theme = str(state.quest.get("theme", ""))
	for kind: String in MARK_COLORS:
		_mark_mats[kind] = _flat_material(MARK_COLORS[kind])
	_fog_mats = {
		"room": _textured("floor_room", FOG_COLOR * 2.0, FOG_COLOR),
		"corridor": _textured("floor_corridor", FOG_COLOR * 2.0, FOG_COLOR),
	}
	_build_floor()
	_build_walls()
	_build_doors()
	_build_furniture(state.furniture)
	for cell: Vector2i in board.blocked:
		_hide_until_seen(_rubble(cell), [cell])
	reveal(state.revealed.keys(), state.revealed, false)
	if Session.preview and not Session.online:
		# Prévia da arte: tudo à vista desde o começo (só na tela; as regras não mudam).
		var all := {}
		for cell: Vector2i in _tiles:
			all[cell] = true
		reveal(all.keys(), all, false)


## Troca todas as marcas: {Vector2i: tipo em MARK_COLORS}.
func set_marks(marks: Dictionary) -> void:
	for cell: Vector2i in _marks:
		_marks[cell].visible = marks.has(cell)
		if marks.has(cell):
			_marks[cell].material_override = _mark_mats[marks[cell]]


## Tira a névoa dos quadrados novos e mostra o que ficou à vista.
func reveal(cells: Array, revealed: Dictionary, animate := true) -> void:
	for cell: Vector2i in cells:
		if not board.dark.has(cell):
			_tiles[cell].material_override = _lit[cell]
	for entry in _hidden:
		var node: Node3D = entry.node
		if node.visible or not entry.cells.any(func(c: Vector2i) -> bool: return revealed.has(c)):
			continue
		node.visible = true
		if animate:
			var final_scale := node.scale
			node.scale = final_scale * 0.01
			create_tween().tween_property(node, "scale", final_scale, 0.3).set_trans(Tween.TRANS_BACK)


## Gira a folha da porta para dentro da passagem.
func open_door(a: Vector2i, b: Vector2i) -> void:
	var pivot: Node3D = _door_pivots.get(Board.edge_key(a, b))
	if pivot == null:
		return
	var tween := create_tween()
	tween.tween_property(pivot, "rotation_degrees:y", pivot.rotation_degrees.y + 95.0, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


## Porta falsa: a folha só treme.
func shake_door(a: Vector2i, b: Vector2i) -> void:
	var pivot: Node3D = _door_pivots.get(Board.edge_key(a, b))
	if pivot == null:
		return
	var tween := create_tween()
	for angle in [6.0, -6.0, 4.0, -4.0, 0.0]:
		tween.tween_property(pivot, "rotation_degrees:y", angle, 0.06)
	await tween.finished


## Porta secreta achada: a parede afunda e no lugar fica uma porta aberta.
func reveal_secret_door(a: Vector2i, b: Vector2i) -> void:
	var key := Board.edge_key(a, b)
	var wall: Node3D = _walls.get(key)
	if wall != null:
		_walls.erase(key)
		var tween := create_tween()
		tween.tween_property(wall, "position:y", -WALL_HEIGHT, 0.4)
		await tween.finished
		wall.queue_free()
	_door_frame(a, b)
	var pivot := _make_door(a, b, true)
	pivot.rotation_degrees.y = 95.0


func show_trap(cell: Vector2i, id: String) -> void:
	if _traps.has(cell) or id != "pit":
		return
	var hole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.02, 0.8)
	hole.mesh = box
	hole.material_override = _material(PIT_COLOR)
	hole.position = cell_center(cell) + Vector3(0, 0.006, 0)
	add_child(hole)
	_traps[cell] = hole


func remove_trap(cell: Vector2i) -> void:
	if _traps.has(cell):
		_traps[cell].queue_free()
		_traps.erase(cell)


## Bloco que cai do teto (armadilha).
func drop_block(cell: Vector2i) -> void:
	remove_trap(cell)
	var rubble := _rubble(cell)
	var rest := rubble.position
	rubble.position.y += 3.0
	var tween := create_tween()
	tween.tween_property(rubble, "position", rest, 0.3).set_ease(Tween.EASE_IN)
	await tween.finished


# ---------- construção ----------

func _build_floor() -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(0.97, 0.1, 0.97)
	var corridor_mat := _textured("floor_corridor", Color.WHITE, CORRIDOR_COLOR)
	var room_mats := {}
	var mark_mesh := PlaneMesh.new()
	mark_mesh.size = Vector2(0.86, 0.86)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			var zone := board.zone_at(cell)
			if zone != Board.CORRIDOR and not room_mats.has(zone):
				# Leve variação por sala para dar para distinguir as salas vizinhas.
				var hue := Color.from_hsv(fmod(zone * 0.137, 1.0), 0.4, 0.7)
				room_mats[zone] = _textured("floor_room", Color.WHITE.lerp(hue, 0.3),
					ROOM_COLOR.lerp(hue, 0.25))
			var tile_node := MeshInstance3D.new()
			tile_node.mesh = tile
			_lit[cell] = corridor_mat if zone == Board.CORRIDOR else room_mats[zone]
			tile_node.material_override = _fog_mats["corridor" if zone == Board.CORRIDOR else "room"]
			tile_node.position = cell_center(cell) + Vector3(0, -0.05, 0)
			# Giro de 0/90/180/270° (fixo por quadrado) para a textura não se repetir.
			tile_node.rotation.y = posmod(x * 7 + y * 13 + x * y, 4) * PI / 2.0
			tile_node.visible = not board.dark.has(cell)
			add_child(tile_node)
			_tiles[cell] = tile_node
			var mark := MeshInstance3D.new()
			mark.mesh = mark_mesh
			mark.position = cell_center(cell) + Vector3(0, 0.012, 0)
			mark.visible = false
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mark)
			_marks[cell] = mark


## Uma parede por aresta entre zonas diferentes (menos onde há porta visível)
## e a borda do tabuleiro.
func _build_walls() -> void:
	var mat := _textured("wall", Color.WHITE, WALL_COLOR, true)
	for y in board.height:
		for x in board.width:
			var cell := Vector2i(x, y)
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var other := cell + dir
				if not board.in_bounds(other):
					_add_wall(cell, dir, mat)
				elif _wall_between(cell, other) and not _has_visible_door(cell, other):
					_walls[Board.edge_key(cell, other)] = _add_wall(cell, dir, mat)
			if x == 0:
				_add_wall(cell, Vector2i.LEFT, mat)
			if y == 0:
				_add_wall(cell, Vector2i.UP, mat)


## Zonas diferentes, ou a borda da área escura (fora da quest).
func _wall_between(a: Vector2i, b: Vector2i) -> bool:
	return board.zone_at(a) != board.zone_at(b) or board.dark.has(a) != board.dark.has(b)


func _has_visible_door(a: Vector2i, b: Vector2i) -> bool:
	var door := board.door_between(a, b)
	return not door.is_empty() and not door.secret


func _add_wall(cell: Vector2i, dir: Vector2i, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	if dir.x != 0:
		box.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0 + WALL_THICKNESS)
	else:
		box.size = Vector3(1.0 + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = cell_center(cell) + Vector3(dir.x * 0.5, WALL_HEIGHT / 2.0, dir.y * 0.5)
	add_child(mesh)
	return mesh


func _build_doors() -> void:
	for key: Vector4i in board.doors:
		var door: Dictionary = board.doors[key]
		if door.secret:
			continue
		var a := Vector2i(key.x, key.y)
		var b := Vector2i(key.z, key.w)
		_door_frame(a, b)
		var pivot := _make_door(a, b)
		if door.open:
			pivot.rotation_degrees.y = 95.0
		_hide_until_seen(pivot, [a, b])


## A folha fica presa num pivô na ponta da aresta (a dobradiça) e gira ao abrir.
## O modelo vem com a dobradiça na origem e a folha ao longo de +X.
func _make_door(a: Vector2i, b: Vector2i, secret := false) -> Node3D:
	var mid := (cell_center(a) + cell_center(b)) / 2.0
	var along := Vector3(0, 0, 1) if a.x != b.x else Vector3(1, 0, 0)
	var pivot := Node3D.new()
	pivot.position = mid - along * 0.45
	add_child(pivot)
	_door_pivots[Board.edge_key(a, b)] = pivot
	var model := _board_model("secret_door" if secret else "door")
	if model:
		model.rotation.y = -PI / 2.0 if a.x != b.x else 0.0
		pivot.add_child(model)
		return pivot
	var color := Color(0.30, 0.30, 0.34) if secret else DOOR_COLOR
	var leaf := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, DOOR_HEIGHT, 0.88) if a.x != b.x else Vector3(0.88, DOOR_HEIGHT, 0.1)
	leaf.mesh = box
	leaf.material_override = _material(color)
	leaf.position = along * 0.45 + Vector3(0, DOOR_HEIGHT / 2.0, 0)
	pivot.add_child(leaf)
	return pivot


## Batente de pedra na aresta da porta (fica à vista como as paredes).
func _door_frame(a: Vector2i, b: Vector2i) -> void:
	var frame := _board_model("door_frame")
	if frame == null:
		return
	frame.position = (cell_center(a) + cell_center(b)) / 2.0
	frame.rotation.y = -PI / 2.0 if a.x != b.x else 0.0
	add_child(frame)


func _board_model(id: String) -> Node3D:
	var path := BOARD_MODEL % id
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


func _build_furniture(pieces: Array[Dictionary]) -> void:
	for piece in pieces:
		var pos: Vector2i = piece.pos
		var size: Vector2i = piece.size
		var cells: Array[Vector2i] = []
		for dy in size.y:
			for dx in size.x:
				cells.append(pos + Vector2i(dx, dy))
		var center := Vector3(pos.x + size.x / 2.0, 0, pos.y + size.y / 2.0)
		var rot := int(piece.get("rot", 0))
		if piece.id in WALL_BACKED and _walls_on(cells, ROT_FRONT[rot]) > _walls_on(cells, -ROT_FRONT[rot]):
			rot = (rot + 2) % 4
		var node := _paper(piece.id, size, center, rot)
		if node == null:
			node = _model(piece.id, center, rot)
		if node:
			if piece.id == "fireplace":
				_fire_light(node)
		elif piece.id == "stairway":
			node = _stairs(center, size)
		else:
			var look: Array = FURNITURE_LOOK.get(piece.id, [0.5, Color.GRAY])
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(size.x - 0.12, look[0], size.y - 0.12)
			mesh.mesh = box
			mesh.material_override = _material(look[1])
			mesh.position = center + Vector3(0, look[0] / 2.0, 0)
			add_child(mesh)
			node = mesh
		_hide_until_seen(node, cells)


## Quantos quadrados da peça têm parede logo depois, no lado `dir`.
func _walls_on(cells: Array[Vector2i], dir: Vector2i) -> int:
	var count := 0
	for c in cells:
		if not cells.has(c + dir) and (not board.in_bounds(c + dir) or _wall_between(c, c + dir)):
			count += 1
	return count


## Móvel de papel (PaperFurniture), centrado e girado; null sem a arte.
## `size` é o ocupado no tabuleiro (já trocado se rot é 1 ou 3).
func _paper(id: String, size: Vector2i, center: Vector3, rot: int) -> Node3D:
	if rot % 2 == 1:
		size = Vector2i(size.y, size.x)
	var node := PaperFurniture.build(id, size)
	if node == null:
		return null
	node.position = center
	node.rotation.y = -rot * PI / 2.0
	add_child(node)
	return node


## Instancia o .glb do móvel, centrado e girado; null se não houver modelo.
func _model(id: String, center: Vector3, rot: int) -> Node3D:
	var path := FURNITURE_MODEL % id
	if not ResourceLoader.exists(path):
		return null
	var node: Node3D = (load(path) as PackedScene).instantiate()
	node.position = center
	node.rotation.y = -rot * PI / 2.0
	add_child(node)
	return node


## Luz bruxuleante na boca da lareira (some junto com o móvel na névoa).
func _fire_light(fireplace: Node3D) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 1.6
	light.omni_range = 3.5
	light.position = Vector3(0, 0.35, 0.1)
	fireplace.add_child(light)
	var tween := light.create_tween().set_loops()
	tween.tween_property(light, "light_energy", 1.1, 0.23).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "light_energy", 1.8, 0.31).set_trans(Tween.TRANS_SINE)


## Escada em degraus: o herói pisa nela (não bloqueia).
func _stairs(center: Vector3, size: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.position = center
	add_child(root)
	var mat := _material(Color(0.50, 0.50, 0.52))
	for i in 3:
		var step := MeshInstance3D.new()
		var box := BoxMesh.new()
		var depth := size.y * (1.0 - i / 3.0) - 0.1
		box.size = Vector3(size.x - 0.1, 0.04, depth)
		step.mesh = box
		step.material_override = mat
		step.position = Vector3(0, 0.02 + i * 0.04, (size.y - depth) / 2.0 - 0.05)
		root.add_child(step)
	return root


func _rubble(cell: Vector2i) -> Node3D:
	var model := _paper("rubble", Vector2i.ONE, cell_center(cell), (cell.x + cell.y) % 4)
	if model == null:
		model = _model("rubble", cell_center(cell), (cell.x + cell.y) % 4)
	if model:
		return model
	var look: Array = FURNITURE_LOOK.blocked_single
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, look[0], 0.9)
	mesh.mesh = box
	mesh.material_override = _material(look[1])
	mesh.position = cell_center(cell) + Vector3(0, look[0] / 2.0, 0)
	add_child(mesh)
	return mesh


func _hide_until_seen(node: Node3D, cells: Array) -> void:
	node.visible = false
	_hidden.append({"node": node, "cells": cells})


static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


## Material com a textura do Blender (cor × tint, normal map, triplanar para
## servir a qualquer caixa); sem a textura, só a cor de reserva.
## world = true alinha a textura no mundo (tijolos contínuos entre paredes).
## O tema da quest vem antes das texturas do Blender.
func _textured(name: String, tint: Color, fallback: Color, world := false) -> StandardMaterial3D:
	var albedo := THEME_TEXTURE % [theme, name, "albedo"]
	var normal := THEME_TEXTURE % [theme, name, "normal"]
	if theme.is_empty() or not ResourceLoader.exists(albedo):
		albedo = TEXTURE % [name, "albedo"]
		normal = TEXTURE % [name, "normal"]
	if not ResourceLoader.exists(albedo):
		return _material(fallback)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(albedo)
	mat.albedo_color = tint
	if ResourceLoader.exists(normal):
		mat.normal_enabled = true
		mat.normal_texture = load(normal)
	mat.roughness = 0.9
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = world
	mat.uv1_offset = Vector3.ONE * 0.5
	return mat


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
