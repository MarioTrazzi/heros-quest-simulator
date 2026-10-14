class_name DiceSim
extends RefCounted
## Física simples de dados (cubos) caindo no tabuleiro: gravidade, quiques no
## chão, nas peças da cena (paredes, portas, móveis, miniaturas — cada uma vira
## uma caixa alinhada aos eixos) e choque entre dados. A simulação roda inteira
## de uma vez e grava os quadros; a `DiceTray` reproduz a gravação. Assim dá
## para saber, antes de mostrar, qual face cada dado deixa para cima e girar só
## o desenho para que seja a face sorteada pelo `Dice` (a regra não depende
## desta física, que usa o randf da apresentação).

const RATE := 120
const GRAVITY := 24.0
const RESTITUTION := 0.5
const WALL_RESTITUTION := 0.55
const FRICTION := 0.35
const MAX_TIME := 3.2
## Depois deste tempo o atrito de rolamento aperta, para nada ficar girando à toa.
const SETTLE_TIME := 1.6
## Golpe mínimo (impulso) que vira estalo no som.
const CLICK_IMPULSE := 1.6
## Peça mais fina que isto (parede, porta) engorda para o dado não atravessar num
## passo e vira coluna alta: dado não fica equilibrado em cima da parede.
const MIN_THICKNESS := 0.16
const THIN_TOP := 4.0

const CORNERS: Array[Vector3] = [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1),
	Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1),
]
const AXES: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]

var half: float
## Peças paradas e a borda do tabuleiro (os dados não saem dela).
var boxes: Array[AABB] = []
var bounds: Rect2
## Centros de dados parados de uma rolagem anterior (o ataque, quando a defesa cai).
var fixed: Array[Vector3] = []
var pos: Array[Vector3] = []
var rot: Array[Quaternion] = []
var vel: Array[Vector3] = []
var spin: Array[Vector3] = []
var _still: Array[int] = []
var _asleep: Array[bool] = []
var _last_click: Array[float] = []
var _inv_mass := 1.0
var _inv_inertia := 1.0

## Gravação: frames[i] = [posições, rotações] de cada dado; clicks = [[tempo, força], ...].
var frames: Array = []
var clicks: Array = []
## Índice (0..5, ordem de DieView.NORMALS) da face que terminou para cima em cada dado.
var up_faces: Array[int] = []
var duration := 0.0


func _init(die_half: float, obstacles: Array[AABB], area: Rect2) -> void:
	half = die_half
	bounds = area
	# Cubo maciço de lado 2h: I = m (2h)² / 6.
	_inv_inertia = 1.5 / (half * half)
	for box in obstacles:
		if minf(box.size.x, box.size.z) < MIN_THICKNESS:
			box.size.y = maxf(box.size.y, THIN_TOP - box.position.y)
		for a in [0, 2]:
			if box.size[a] < MIN_THICKNESS:
				box.position[a] -= (MIN_THICKNESS - box.size[a]) / 2.0
				box.size[a] = MIN_THICKNESS
		boxes.append(box)


## Solta um dado de `from` com velocidade e giro dados.
func add_die(from: Vector3, velocity: Vector3, angular: Vector3) -> void:
	pos.append(from)
	rot.append(Quaternion.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)))
	vel.append(velocity)
	spin.append(angular)
	_still.append(0)
	_asleep.append(false)
	_last_click.append(-1.0)


## Roda até todos pararem (ou MAX_TIME), endireita o fim e descobre as faces de cima.
func run() -> void:
	var dt := 1.0 / RATE
	var t := 0.0
	_record()
	while t < MAX_TIME and _asleep.has(false):
		_step(dt, t)
		t += dt
		_record()
	_settle_flat()
	duration = t
	up_faces.clear()
	for q in rot:
		up_faces.append(_up_face(q))


func frame_count() -> int:
	return frames.size()




# ---------- passo ----------

func _step(dt: float, t: float) -> void:
	var late := t > SETTLE_TIME
	for i in pos.size():
		if _asleep[i]:
			continue
		vel[i].y -= GRAVITY * dt
		pos[i] += vel[i] * dt
		var w := spin[i]
		if w.length() > 0.0001:
			rot[i] = (Quaternion(w.normalized(), w.length() * dt) * rot[i]).normalized()
		# hit = [maior impulso do passo, apoiado em algo].
		var hit := [0.0, false]
		_collide_planes(i, hit)
		_collide_boxes(i, hit)
		var resting: bool = hit[1]
		if resting:
			var roll := 6.0 if late else 0.8
			spin[i] *= maxf(0.0, 1.0 - roll * dt)
			vel[i].x *= maxf(0.0, 1.0 - (3.0 if late else 0.6) * dt)
			vel[i].z *= maxf(0.0, 1.0 - (3.0 if late else 0.6) * dt)
		if hit[0] > CLICK_IMPULSE and t - _last_click[i] > 0.06:
			_last_click[i] = t
			clicks.append([t, hit[0]])
		_update_sleep(i, resting)
	_collide_dice()


## Chão (y = 0) e a borda do tabuleiro.
func _collide_planes(i: int, hit: Array) -> void:
	var planes := [
		[Vector3.UP, 0.0, RESTITUTION],
		[Vector3.RIGHT, bounds.position.x, WALL_RESTITUTION],
		[Vector3.LEFT, -bounds.end.x, WALL_RESTITUTION],
		[Vector3.BACK, bounds.position.y, WALL_RESTITUTION],
		[Vector3.FORWARD, -bounds.end.y, WALL_RESTITUTION],
	]
	for plane: Array in planes:
		var n: Vector3 = plane[0]
		var d: float = plane[1]
		var deepest := 0.0
		for c in CORNERS:
			var r: Vector3 = rot[i] * (c * half)
			var pen := d - n.dot(pos[i] + r)
			if pen > 0.0:
				deepest = maxf(deepest, pen)
				_contact(i, r, n, plane[2], hit)
		if deepest > 0.0:
			pos[i] += n * deepest


## Quinas do dado dentro de uma peça e quinas da peça dentro do dado.
func _collide_boxes(i: int, hit: Array) -> void:
	var reach := half * 1.75
	for box in boxes:
		var p := pos[i]
		if p.x < box.position.x - reach or p.x > box.end.x + reach \
				or p.y < box.position.y - reach or p.y > box.end.y + reach \
				or p.z < box.position.z - reach or p.z > box.end.z + reach:
			continue
		var push := Vector3.ZERO
		for c in CORNERS:
			var r: Vector3 = rot[i] * (c * half)
			var world := pos[i] + r
			if not box.has_point(world):
				continue
			# Sai pela face mais próxima da peça.
			var best := INF
			var n := Vector3.UP
			for a in 3:
				var low: float = world[a] - box.position[a]
				var high: float = box.end[a] - world[a]
				if low < best:
					best = low
					n = -AXES[a]
				if high < best:
					best = high
					n = AXES[a]
			if push.length() < best:
				push = n * best
			_contact(i, r, n, RESTITUTION if n == Vector3.UP else WALL_RESTITUTION, hit)
		var inv := rot[i].inverse()
		for k in 8:
			var corner := box.position + box.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)
			if corner.y < 0.02:
				continue  # rente ao chão: só levantaria o dado do piso
			var local := inv * (corner - pos[i])
			var a := local.abs().max_axis_index()
			var depth := half - absf(local[a])
			if depth <= 0.0:
				continue
			# A quina da peça empurra o dado pela face dele que ela furou.
			var face := Vector3.ZERO
			face[a] = signf(local[a])
			var n: Vector3 = -(rot[i] * face)
			if push.length() < depth:
				push = n * depth
			_contact(i, corner - pos[i], n, WALL_RESTITUTION, hit)
		pos[i] += push


## Impulso de choque (e atrito, no que apoia) num ponto `r` do dado, normal `n`.
func _contact(i: int, r: Vector3, n: Vector3, restitution: float, hit: Array) -> void:
	if n.y > 0.5:
		hit[1] = true
	var vc := vel[i] + spin[i].cross(r)
	var vn := vc.dot(n)
	if vn >= 0.0:
		return
	var e := restitution if vn < -1.5 else 0.0
	var rn := r.cross(n)
	var j := -(1.0 + e) * vn / (_inv_mass + _inv_inertia * rn.length_squared())
	vel[i] += n * j * _inv_mass
	spin[i] += rn * j * _inv_inertia
	hit[0] = maxf(hit[0], j)
	# Atrito só no que apoia (parede lisa não segura dado espremido): tira a
	# velocidade tangente do ponto, até µ·j.
	if n.y <= 0.5:
		return
	vc = vel[i] + spin[i].cross(r)
	var vt := vc - n * vc.dot(n)
	var speed := vt.length()
	if speed > 0.0001:
		var tan := vt / speed
		var rt := r.cross(tan)
		var jt := minf(speed / (_inv_mass + _inv_inertia * rt.length_squared()), FRICTION * j)
		vel[i] -= tan * jt * _inv_mass
		spin[i] -= rt * jt * _inv_inertia


## Dados como esferas que só se empurram de lado (nenhum fica em cima de outro).
func _collide_dice() -> void:
	var radius := half * 1.25
	for a in pos.size():
		for center in fixed:
			var delta := pos[a] - center
			delta.y = 0.0
			var dist := delta.length()
			if dist >= radius * 2.0 or dist < 0.0001:
				continue
			var n := delta / dist
			pos[a] += n * (radius * 2.0 - dist)
			var vn := vel[a].dot(n)
			if vn < 0.0:
				vel[a] -= n * vn * 1.4
				if vn < -0.3:
					_asleep[a] = false
					_still[a] = 0
	for a in pos.size():
		for b in range(a + 1, pos.size()):
			var delta := pos[b] - pos[a]
			delta.y = 0.0
			var dist := delta.length()
			if dist >= radius * 2.0 or dist < 0.0001:
				continue
			var n := delta / dist
			# Dado parado não é empurrado de leve: quem chega o tira do lugar inteiro.
			var share_a := 0.0 if _asleep[a] else (1.0 if _asleep[b] else 0.5)
			var share_b := 1.0 - share_a if not (_asleep[a] and _asleep[b]) else 0.0
			var overlap := radius * 2.0 - dist
			pos[a] -= n * overlap * share_a
			pos[b] += n * overlap * share_b
			var vn := (vel[b] - vel[a]).dot(n)
			if vn < -0.3:
				var j := -(1.0 + 0.4) * vn / 2.0
				vel[a] -= n * j
				vel[b] += n * j
				# O raspão faz o dado girar um pouco.
				spin[a] += n.cross(Vector3.UP) * j * 0.8
				spin[b] -= n.cross(Vector3.UP) * j * 0.8
				_asleep[a] = false
				_asleep[b] = false
				_still[a] = 0
				_still[b] = 0


func _update_sleep(i: int, resting: bool) -> void:
	# O contato deixa um resto de velocidade vertical (gravidade do passo); só o de lado conta.
	var sideways := Vector2(vel[i].x, vel[i].z).length()
	if resting and _flatness(rot[i]) > 0.995 and sideways < 0.2 and absf(vel[i].y) < 0.5 and spin[i].length() < 0.6:
		_still[i] += 1
		if _still[i] > RATE / 10:
			_asleep[i] = true
			vel[i] = Vector3.ZERO
			spin[i] = Vector3.ZERO
	else:
		_still[i] = 0


## Endireita os últimos quadros: face de cima exatamente para cima.
func _settle_flat() -> void:
	var blend := mini(12, frames.size())
	var targets: Array[Quaternion] = []
	for i in rot.size():
		var face := DieView.NORMALS[_up_face(rot[i])]
		var world_n: Vector3 = rot[i] * face
		var fix := Quaternion(world_n.normalized(), Vector3.UP) if world_n.dot(Vector3.UP) < 0.99999 else Quaternion.IDENTITY
		targets.append((fix * rot[i]).normalized())
	for k in blend:
		var f: int = frames.size() - blend + k
		var w := float(k + 1) / blend
		var turn: Array = frames[f][1]
		for i in rot.size():
			turn[i] = (turn[i] as Quaternion).slerp(targets[i], w)
	rot = targets


func _record() -> void:
	frames.append([pos.duplicate(), rot.duplicate()])


static func _up_face(q: Quaternion) -> int:
	var best := 0
	var best_dot := -2.0
	for f in DieView.NORMALS.size():
		var d := (q * DieView.NORMALS[f]).dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = f
	return best


static func _flatness(q: Quaternion) -> float:
	return (q * DieView.NORMALS[_up_face(q)]).dot(Vector3.UP)
