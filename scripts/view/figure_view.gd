class_name FigureView
extends Node3D
## Miniatura de um herói ou monstro: base preta + modelo do Blender
## (assets/models/figures/<def_id>.glb, feito por tools/blender/build_figures.py).
## Sem o .glb, monta a figura provisória de primitivos.

const MODEL_DIR := "res://assets/models/figures/%s.glb"
## Monstros sem miniatura própria que usam a de outro (como manda o livro).
const MODEL_ALIAS := {"witch_lord": "chaos_warlock"}
const BASE_HEIGHT := 0.06

## Cor e escala da figura provisória por def_id (a cor também serve à reserva).
const LOOKS := {
	"barbarian": [Color(0.85, 0.35, 0.15), 1.05],
	"dwarf": [Color(0.85, 0.65, 0.15), 0.85],
	"elf": [Color(0.25, 0.70, 0.30), 1.0],
	"wizard": [Color(0.25, 0.40, 0.90), 1.0],
	"goblin": [Color(0.45, 0.65, 0.20), 0.75],
	"orc": [Color(0.25, 0.45, 0.15), 0.95],
	"fimir": [Color(0.50, 0.35, 0.55), 1.0],
	"chaos_warrior": [Color(0.15, 0.15, 0.18), 1.1],
	"chaos_warlock": [Color(0.40, 0.10, 0.45), 1.05],
	"gargoyle": [Color(0.45, 0.45, 0.48), 1.2],
	"skeleton": [Color(0.90, 0.88, 0.80), 0.95],
	"zombie": [Color(0.45, 0.55, 0.42), 0.95],
	"mummy": [Color(0.80, 0.72, 0.55), 1.0],
}
const STEP_TIME := 0.14
const TORCH_ENERGY := 1.7

var unit: Unit
var _flash_mat: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _label: Label3D


func setup(p_unit: Unit) -> void:
	unit = p_unit
	name = "%s_%s" % [unit.def_id, unit.get_instance_id()]
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.36
	base_mesh.bottom_radius = 0.38
	base_mesh.height = BASE_HEIGHT
	var base := _part(base_mesh, Color(0.12, 0.12, 0.12))
	base.position.y = BASE_HEIGHT / 2.0
	# Heróis têm a borda da base dourada para se destacar dos monstros.
	if unit.is_hero():
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.355
		rim_mesh.outer_radius = 0.39
		_part(rim_mesh, Color(0.85, 0.65, 0.2)).position.y = BASE_HEIGHT

	var path := MODEL_DIR % MODEL_ALIAS.get(unit.def_id, unit.def_id)
	if ResourceLoader.exists(path):
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.position.y = BASE_HEIGHT
		add_child(model)
	else:
		_build_placeholder()

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	_collect_meshes(self)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.38
	ring_mesh.outer_radius = 0.46
	_ring = _part(ring_mesh, Color(1.0, 0.9, 0.3))
	(_ring.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.position.y = 0.02
	_ring.visible = false

	_label = Label3D.new()
	_label.text = unit.name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.3
	_label.pixel_size = 0.004
	_label.font_size = 40
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)

	if unit.is_hero():
		_torch()
	position = BoardView.cell_center(unit.pos)


## Luz de tocha que acompanha o herói: é ela que ilumina a masmorra escura.
func _torch() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.68, 0.38)
	light.light_energy = TORCH_ENERGY
	light.omni_range = 4.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.position = Vector3(0, 1.4, 0)
	add_child(light)
	var tween := light.create_tween().set_loops()
	tween.tween_property(light, "light_energy", TORCH_ENERGY * 0.8, 0.19 + randf() * 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "light_energy", TORCH_ENERGY * 1.1, 0.27 + randf() * 0.1).set_trans(Tween.TRANS_SINE)


## Figura provisória (corpo + cabeça + chapéu) para quem ainda não tem modelo.
func _build_placeholder() -> void:
	var look: Array = LOOKS.get(MODEL_ALIAS.get(unit.def_id, unit.def_id), [Color.MAGENTA, 1.0])
	var color: Color = look[0]
	scale = Vector3.ONE * float(look[1])
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.2
	capsule.height = 0.62
	_part(capsule, color).position.y = 0.37
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.13
	head_mesh.height = 0.26
	_part(head_mesh, color.lightened(0.25)).position.y = 0.8
	if unit.is_hero():
		var hat_mesh := CylinderMesh.new()
		hat_mesh.top_radius = 0.0
		hat_mesh.bottom_radius = 0.15
		hat_mesh.height = 0.22
		_part(hat_mesh, color.darkened(0.3)).position.y = 0.98


## Guarda as malhas da figura (menos anel e base) para o pisca de dano/cura.
func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child != _ring:
			_meshes.append(child)
		_collect_meshes(child)


## Vira a figura de frente para o ponto (o modelo olha para +Z).
func face(point: Vector3, time := 0.08) -> void:
	var dir := point - position
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := rotation.y + wrapf(atan2(dir.x, dir.z) - rotation.y, -PI, PI)
	create_tween().tween_property(self, "rotation:y", target, time)


## Estado sob o nome: "Dormindo", "Tempestade", "Pele de Pedra"...
func show_status(text: String) -> void:
	_label.text = unit.name if text == "" else "%s\n(%s)" % [unit.name, text]


func set_active(on: bool) -> void:
	_ring.visible = on


## Anda quadrado a quadrado com um pulinho.
func walk(path: Array[Vector2i]) -> void:
	for cell in path:
		Sfx.play("step")
		var target := BoardView.cell_center(cell)
		face(target)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "position:x", target.x, STEP_TIME)
		tween.tween_property(self, "position:z", target.z, STEP_TIME)
		tween.tween_property(self, "position:y", 0.12, STEP_TIME / 2.0).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position:y", 0.0, STEP_TIME / 2.0) \
			.set_delay(STEP_TIME / 2.0).set_ease(Tween.EASE_IN)
		await tween.finished
		position = target


## Salto em arco direto até o quadrado (pular fosso).
func hop_to(cell: Vector2i) -> void:
	var target := BoardView.cell_center(cell)
	face(target)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:x", target.x, 0.35)
	tween.tween_property(self, "position:z", target.z, 0.35)
	tween.tween_property(self, "position:y", 0.6, 0.175).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", 0.0, 0.175).set_delay(0.175).set_ease(Tween.EASE_IN)
	await tween.finished
	position = target


## Texto que sobe da miniatura e some ("-2", "+4", "Defendeu").
func float_text(text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 64
	label.outline_size = 14
	label.pixel_size = 0.005
	label.position = Vector3(0, 1.4, 0) / scale
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.8 / scale.y, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


## Investida curta na direção do alvo e volta.
func lunge(toward: Vector3) -> void:
	var start := position
	face(toward)
	var dir := (toward - start).normalized() * 0.3
	var tween := create_tween()
	tween.tween_property(self, "position", start + dir, 0.1)
	tween.tween_property(self, "position", start, 0.15)
	await tween.finished


## Pisca em vermelho ao levar dano.
func flash_hit() -> void:
	await _flash(Color(1, 0.1, 0.1))


## Pisca em verde ao ser curado.
func flash_heal() -> void:
	await _flash(Color(0.3, 1.0, 0.4))


## Surge do chão (monstro revelado ou monstro errante).
func appear() -> void:
	visible = true
	var final_scale := scale
	scale = final_scale * 0.01
	var tween := create_tween()
	tween.tween_property(self, "scale", final_scale, 0.3).set_trans(Tween.TRANS_BACK)
	await tween.finished


## Cobre a figura com uma camada da cor que aparece e some.
func _flash(color: Color) -> void:
	for mesh in _meshes:
		mesh.material_overlay = _flash_mat
	_flash_mat.albedo_color = Color(color, 0.0)
	var tween := create_tween()
	tween.tween_property(_flash_mat, "albedo_color:a", 0.75, 0.08)
	tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.25)
	await tween.finished
	for mesh in _meshes:
		mesh.material_overlay = null


## Desce pela escada e some (herói que saiu da masmorra).
func leave() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", -1.2, 0.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "scale", scale * 0.5, 0.5)
	await tween.finished
	queue_free()


func die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees:z", 90.0, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.3)
	await tween.finished
	queue_free()


func _part(mesh: PrimitiveMesh, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	node.material_override = mat
	add_child(node)
	return node
