class_name DiceTray
extends Node3D
## Mostra as rolagens com dados 3D jogados no próprio tabuleiro: caem do alto,
## perto da ação e do lado da câmera, e quicam com física (`DiceSim`) no chão,
## nas paredes, portas, móveis e miniaturas até parar. O desenho de cada dado é
## girado para que a face de cima seja a sorteada pelo `Dice`. No combate o
## atacante joga primeiro e o defensor depois, do outro lado. Os dados que
## contam (caveiras no ataque, escudo certo na defesa) crescem um pouco ao parar.

const DIE_SIZE := 0.5
## Altura de onde os dados caem.
const HEIGHT := 2.0
## Os dados caem um pouco para o lado da câmera, para não cair em cima das figuras.
const TOWARD_CAMERA := 0.7
## Até onde (do ponto da queda) as peças da cena entram na física.
const REACH := 4.0
## Miniatura vira uma coluna alta: dado não fica equilibrado na cabeça de ninguém.
const FIGURE_TOP := 4.0
## Pausa entre o ataque parar e a defesa ser jogada, e depois do último dado parar.
const BETWEEN_TIME := 0.3
const HOLD_TIME := 0.8

## Depois de mostrado, o resultado some sozinho após este tempo.
const LINGER_TIME := 1.2

var camera: Camera3D
## Onde procurar as peças em que os dados batem (a cena da partida) e a borda do tabuleiro.
var scene_root: Node
var bounds := Rect2(-100, -100, 200, 200)
var _dice: Array[DieView] = []
## Cada rolagem nova invalida a limpeza agendada pela anterior.
var _generation := 0


## Ataque e defesa (vazia: só o ataque, como nas armadilhas).
func roll_combat(anchor: Vector3, attack: Array[String], defend: Array[String], defender_is_hero: bool) -> void:
	clear()
	var generation := _generation
	var shield := Dice.WHITE_SHIELD if defender_is_hero else Dice.BLACK_SHIELD
	var right := _flat(camera.global_basis.x)
	var toward := _flat(camera.global_basis.z)
	var resting: Array[Vector3] = []
	if defend.is_empty():
		await _throw(attack, DieView.combat, anchor + toward * TOWARD_CAMERA, right, resting,
			func(key: String) -> bool: return key == Dice.SKULL)
	else:
		await _throw(attack, DieView.combat, anchor + toward * TOWARD_CAMERA - right * 0.5, right, resting,
			func(key: String) -> bool: return key == Dice.SKULL)
		if generation != _generation:
			return
		await get_tree().create_timer(BETWEEN_TIME).timeout
		await _throw(defend, DieView.combat, anchor + toward * (TOWARD_CAMERA + 0.6) + right * 0.5, -right, resting,
			func(key: String) -> bool: return key == shield)
	await get_tree().create_timer(HOLD_TIME).timeout
	_clear_later()


## min_counted > 0: os dados com esse valor ou mais crescem ao parar (ex.: 5 e 6 resistem).
func roll_d6(anchor: Vector3, values: Array, min_counted := 0) -> void:
	clear()
	var keys: Array[String] = []
	for v: int in values:
		keys.append(str(v))
	var resting: Array[Vector3] = []
	await _throw(keys, DieView.d6, anchor + _flat(camera.global_basis.z) * TOWARD_CAMERA,
		_flat(camera.global_basis.x), resting,
		func(key: String) -> bool: return min_counted > 0 and int(key) >= min_counted)
	await get_tree().create_timer(HOLD_TIME).timeout
	_clear_later()


func clear() -> void:
	_generation += 1
	for die in _dice:
		if is_instance_valid(die):
			die.queue_free()
	_dice.clear()


func _clear_later() -> void:
	var generation := _generation
	await get_tree().create_timer(LINGER_TIME).timeout
	if generation != _generation:
		return
	for die in _dice:
		if is_instance_valid(die):
			die.create_tween().tween_property(die, "scale", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(0.3).timeout
	if generation == _generation:
		clear()


## Solta `keys` do alto sobre `spot`, jogados na direção `dir`, e espera parar.
## `resting` traz os dados já parados (e recebe estes); `counts(key)` diz quais crescem.
func _throw(keys: Array[String], make: Callable, spot: Vector3, dir: Vector3, resting: Array[Vector3], counts: Callable) -> void:
	if keys.is_empty():
		return
	var generation := _generation
	var half := DIE_SIZE / 2.0
	var obstacles := _obstacles(spot)
	spot = _clear_spot(spot, obstacles)
	var side := dir.cross(Vector3.UP)
	var sim := DiceSim.new(half, obstacles, bounds)
	sim.fixed = resting.duplicate()
	for i in keys.size():
		var from := spot + side * (i - (keys.size() - 1) / 2.0) * DIE_SIZE * 1.3 \
			+ Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
		from.y = HEIGHT + randf_range(-0.15, 0.25)
		var velocity := dir * randf_range(1.0, 2.2) + side * randf_range(-0.5, 0.5) + Vector3(0, randf_range(0.0, 1.0), 0)
		var angular := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(10.0, 20.0)
		sim.add_die(from, velocity, angular)
	sim.run()

	var dice: Array[DieView] = []
	for i in keys.size():
		var die: DieView = make.call()
		die.scale = Vector3.ONE * DIE_SIZE
		add_child(die)
		die.show_face(keys[i], sim.up_faces[i])
		dice.append(die)
		_dice.append(die)
		resting.append(sim.pos[i])
	var played := [0]
	var show := func(t: float) -> void:
		var f := clampi(int(t * DiceSim.RATE), 0, sim.frame_count() - 1)
		var g := mini(f + 1, sim.frame_count() - 1)
		var k := t * DiceSim.RATE - f
		for i in dice.size():
			if not is_instance_valid(dice[i]):
				return
			dice[i].position = (sim.frames[f][0][i] as Vector3).lerp(sim.frames[g][0][i], k)
			dice[i].quaternion = (sim.frames[f][1][i] as Quaternion).slerp(sim.frames[g][1][i], k)
		while played[0] < sim.clicks.size() and sim.clicks[played[0]][0] <= t:
			var force: float = sim.clicks[played[0]][1]
			Sfx.play("die_hit", clampf(1.25 - force * 0.05, 0.8, 1.2))
			played[0] += 1
	show.call(0.0)
	var tween := create_tween()
	tween.tween_method(show, 0.0, sim.duration, sim.duration)
	await tween.finished
	if generation != _generation:
		return
	for i in dice.size():
		if counts.call(keys[i]):
			dice[i].highlight()


## Caixas (no mundo) das peças à vista perto de `spot`: paredes, portas, móveis e
## miniaturas (estas como colunas altas). Pisos e marcas no chão ficam de fora.
func _obstacles(spot: Vector3) -> Array[AABB]:
	var out: Array[AABB] = []
	if scene_root:
		_collect(scene_root, spot, out)
	return out


func _collect(node: Node, spot: Vector3, out: Array[AABB]) -> void:
	if node == self or node is CanvasLayer or node is SubViewport or node is Control:
		return
	if node is Node3D and not (node as Node3D).is_visible_in_tree():
		return
	if node is FigureView:
		var merged := _merged_aabb(node)
		if merged.size != Vector3.ZERO and _near(merged, spot):
			merged.size.y = FIGURE_TOP - merged.position.y
			out.append(merged)
		return
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var box: AABB = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).mesh.get_aabb()
		if box.end.y > 0.06 and box.position.y < HEIGHT and _near(box, spot):
			out.append(box)
	for child in node.get_children():
		_collect(child, spot, out)


## Caixa juntando as malhas de uma miniatura (sem o que fica rente ao chão, como o anel).
func _merged_aabb(node: Node) -> AABB:
	var merged := AABB()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as Node3D).is_visible_in_tree():
			var box: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			if box.end.y <= 0.06:
				continue
			merged = box if merged.size == Vector3.ZERO else merged.merge(box)
	return merged


func _near(box: AABB, spot: Vector3) -> bool:
	return box.position.x < spot.x + REACH and box.end.x > spot.x - REACH \
		and box.position.z < spot.z + REACH and box.end.z > spot.z - REACH


## Afasta o ponto da queda (para o lado da câmera) se ele cair dentro de uma miniatura.
func _clear_spot(spot: Vector3, obstacles: Array[AABB]) -> Vector3:
	var toward := _flat(camera.global_basis.z)
	for attempt in 6:
		var blocked := false
		for box in obstacles:
			if box.end.y >= FIGURE_TOP - 0.01 and box.grow(DIE_SIZE).has_point(Vector3(spot.x, box.position.y + 0.5, spot.z)):
				blocked = true
				break
		if not blocked:
			break
		spot += toward * 0.35
	return spot


static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.001 else Vector3.BACK
