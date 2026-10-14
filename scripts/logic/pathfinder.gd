class_name Pathfinder
extends RefCounted
## BFS ortogonal sobre o Board. AStarGrid2D não entende paredes nas arestas,
## e com no máximo 12 passos em 494 quadrados o BFS sobra.
##
## `occupancy(cell) -> int` diz o que há no quadrado para quem está andando:
## FREE, PASS_ONLY (aliado: atravessa mas não para) ou BLOCKED (inimigo).

enum { FREE, PASS_ONLY, BLOCKED }


## cell -> {"dist": int, "prev": Vector2i, "stop": bool} de tudo que dá para
## alcançar com até max_steps passos. "stop" = pode terminar o movimento ali.
## `ignore_walls`: Atravessar Rocha (paredes e portas não contam; quadrados
## bloqueados e móveis, sim).
static func flood(board: Board, start: Vector2i, max_steps: int, occupancy: Callable, ignore_walls := false) -> Dictionary:
	var seen := {start: {"dist": 0, "prev": start, "stop": true}}
	var frontier: Array[Vector2i] = [start]
	var head := 0
	while head < frontier.size():
		var cur := frontier[head]
		head += 1
		var dist: int = seen[cur].dist
		if dist >= max_steps:
			continue
		for dir in Board.DIRS:
			var next := cur + dir
			var can_go := board.in_bounds(next) and board.is_walkable(next) if ignore_walls else board.can_step(cur, next)
			if seen.has(next) or not can_go:
				continue
			var occ: int = occupancy.call(next)
			if occ == BLOCKED:
				continue
			seen[next] = {"dist": dist + 1, "prev": cur, "stop": occ == FREE}
			frontier.append(next)
	return seen


## Quadrados onde dá para terminar o movimento (sem contar a origem).
static func destinations(flooded: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in flooded:
		var info: Dictionary = flooded[cell]
		if info.stop and info.dist > 0:
			out.append(cell)
	return out


## Caminho até target (sem a origem); vazio se não dá para parar lá.
static func path_to(flooded: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not flooded.has(target) or not flooded[target].stop:
		return path
	var cur := target
	while flooded[cur].dist > 0:
		path.push_front(cur)
		cur = flooded[cur].prev
	return path
