class_name LineOfSight
extends RefCounted
## Linha de visão do HeroQuest: na mesma sala sempre se vê; fora disso, a reta
## entre os centros dos quadrados não pode cruzar parede, porta fechada,
## quadrado bloqueado nem outra figura.
##
## A reta é percorrida quadrado a quadrado (supercover, sem pular quinas).

## Reta que passa exatamente por uma quina: true = bloqueia se QUALQUER um dos
## dois lados estiver fechado; false = só se os dois estiverem.
const CORNER_STRICT := true


## `occupied(cell) -> bool`: há figura no quadrado (as pontas são ignoradas).
static func can_see(board: Board, from: Vector2i, to: Vector2i, occupied: Callable) -> bool:
	if from == to or board.same_room(from, to):
		return true
	var delta := to - from
	var nx := absi(delta.x)
	var ny := absi(delta.y)
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var cur := from
	var ix := 0
	var iy := 0
	while ix < nx or iy < ny:
		# Compara onde a reta cruza a próxima borda vertical e a horizontal.
		var decision := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		var next: Vector2i
		if decision == 0:
			next = cur + step
			var side_x := cur + Vector2i(step.x, 0)
			var side_y := cur + Vector2i(0, step.y)
			var shut_x := board.is_wall(cur, side_x) or board.is_wall(side_x, next) or _blocks(board, side_x, occupied)
			var shut_y := board.is_wall(cur, side_y) or board.is_wall(side_y, next) or _blocks(board, side_y, occupied)
			if (shut_x or shut_y) if CORNER_STRICT else (shut_x and shut_y):
				return false
			ix += 1
			iy += 1
		elif decision < 0:
			next = cur + Vector2i(step.x, 0)
			ix += 1
		else:
			next = cur + Vector2i(0, step.y)
			iy += 1
		if decision != 0 and board.is_wall(cur, next):
			return false
		if next != to and _blocks(board, next, occupied):
			return false
		cur = next
	return true


static func _blocks(board: Board, cell: Vector2i, occupied: Callable) -> bool:
	return board.is_opaque(cell) or occupied.call(cell)
