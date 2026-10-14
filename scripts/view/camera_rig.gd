class_name CameraRig
extends Node3D
## Câmera em órbita sobre o tabuleiro.
## Botão direito arrasta = gira; botão do meio arrasta ou WASD/setas = move;
## roda = zoom. focus() leva o centro até um ponto (figura ativa).

const PAN_SPEED := 10.0

var yaw := 0.0
var pitch := -55.0
var distance := 14.0
var bounds := Rect2(0, 0, 26, 19)
var camera := Camera3D.new()


func _ready() -> void:
	camera.fov = 50.0
	add_child(camera)
	_apply()


func focus(point: Vector3, instant := false) -> void:
	point.y = 0.0
	if instant:
		position = point
		_apply()
		return
	var tween := create_tween()
	tween.tween_property(self, "position", point, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_apply)


## Tremidinha (golpe forte, armadilha).
func shake(strength := 0.12) -> void:
	var tween := create_tween()
	for i in 5:
		tween.tween_property(camera, "h_offset", randf_range(-strength, strength), 0.03)
		tween.parallel().tween_property(camera, "v_offset", randf_range(-strength, strength), 0.03)
	tween.tween_property(camera, "h_offset", 0.0, 0.04)
	tween.parallel().tween_property(camera, "v_offset", 0.0, 0.04)


## Ponto do piso (y = 0) sob o cursor, ou null.
func floor_point(screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var normal := camera.project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)


func _process(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	input = (input + keys).limit_length(1.0)
	if input != Vector2.ZERO:
		_pan(input * PAN_SPEED * delta)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.3
			pitch = clampf(pitch - event.relative.y * 0.3, -85.0, -20.0)
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(-event.relative * distance * 0.0015)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(5.0, distance - 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(35.0, distance + 1.0)


## Move no plano do piso, relativo ao giro da câmera.
func _pan(screen_delta: Vector2) -> void:
	var basis_yaw := Basis(Vector3.UP, deg_to_rad(yaw))
	position += basis_yaw * Vector3(screen_delta.x, 0, screen_delta.y)
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)


func _apply() -> void:
	var rot := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	camera.position = rot * Vector3(0, 0, distance)
	camera.look_at(global_position)
