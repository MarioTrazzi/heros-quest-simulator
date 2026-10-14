class_name Board
extends RefCounted
## Grade 26×19 do HeroQuest. As paredes ficam nas ARESTAS entre quadrados:
## há parede entre dois vizinhos se e só se estão em zonas diferentes
## (sala ≠ sala ou sala ≠ corredor). Portas abertas furam essa parede.
## Coordenadas base 0: Vector2i(coluna, linha).

const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const CORRIDOR := 0

var width := 0
var height := 0
var _zones := PackedInt32Array()
## edge_key -> {"open": bool, "secret": bool, "fake": bool}. Porta secreta ainda
## não achada é só parede; ao ser achada fica aberta para sempre. Porta falsa
## parece porta mas nunca abre.
var doors: Dictionary = {}
## Quadrados opacos e intransitáveis: entulho e bloco que caiu.
var blocked: Dictionary = {}
## Área fora da quest (o "escuro" do HeroScribe): opaca e intransitável.
var dark: Dictionary = {}
## Móveis: bloqueiam o movimento mas não a visão. Vector2i -> id do móvel.
var furniture: Dictionary = {}


static func from_data(data: Dictionary) -> Board:
	var board := Board.new()
	board.width = int(data.width)
	board.height = int(data.height)
	for row: Array in data.zones:
		for zone: float in row:
			board._zones.append(int(zone))
	return board


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func zone_at(cell: Vector2i) -> int:
	return _zones[cell.y * width + cell.x]


func is_room(cell: Vector2i) -> bool:
	return zone_at(cell) != CORRIDOR


func same_room(a: Vector2i, b: Vector2i) -> bool:
	return is_room(a) and zone_at(a) == zone_at(b)


func room_ids() -> Array[int]:
	var ids: Array[int] = []
	for z in _zones:
		if z != CORRIDOR and not ids.has(z):
			ids.append(z)
	ids.sort()
	return ids


func cells_of_zone(zone: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in height:
		for x in width:
			if _zones[y * width + x] == zone:
				out.append(Vector2i(x, y))
	return out


## Chave da aresta entre dois vizinhos, independente da ordem.
static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.y < b.y or (a.y == b.y and a.x < b.x):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


func add_door(a: Vector2i, b: Vector2i, open := false, secret := false, fake := false) -> void:
	assert((a - b).abs().x + (a - b).abs().y == 1, "porta precisa ligar vizinhos")
	doors[edge_key(a, b)] = {"open": open, "secret": secret, "fake": fake}


func door_between(a: Vector2i, b: Vector2i) -> Dictionary:
	return doors.get(edge_key(a, b), {})


## Abre a porta (ou revela a porta secreta). Devolve false se não há porta.
func open_door(a: Vector2i, b: Vector2i) -> bool:
	var door := door_between(a, b)
	if door.is_empty():
		return false
	door.open = true
	return true


## Parede (ou porta fechada) entre dois vizinhos. Fora do tabuleiro conta como parede.
func is_wall(a: Vector2i, b: Vector2i) -> bool:
	if not in_bounds(a) or not in_bounds(b):
		return true
	if zone_at(a) == zone_at(b):
		return false
	var door := door_between(a, b)
	return door.is_empty() or not door.open


## Opaco para linha de visão (paredes ficam nas arestas, não aqui).
func is_opaque(cell: Vector2i) -> bool:
	return not in_bounds(cell) or blocked.has(cell) or dark.has(cell)


## Dá para pisar, ignorando figuras.
func is_walkable(cell: Vector2i) -> bool:
	return in_bounds(cell) and not blocked.has(cell) and not dark.has(cell) and not furniture.has(cell)


## Passo ortogonal de a para b, ignorando figuras.
func can_step(a: Vector2i, b: Vector2i) -> bool:
	return is_walkable(b) and not is_wall(a, b)


func place_furniture(id: String, top_left: Vector2i, size: Vector2i) -> void:
	for dy in size.y:
		for dx in size.x:
			furniture[top_left + Vector2i(dx, dy)] = id
