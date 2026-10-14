# Dados do HeroQuest: dado de combate (marfim, caveiras e escudos) e d6 de
# movimento (vermelho, pintas brancas). Exporta assets/models/dice/<id>.glb.
#
# Rodar dentro do Blender (MCP ou Text Editor):
#   g = {}; exec(open("<projeto>/tools/blender/build_dice.py").read(), g); g["run"]()
# Cria/recria a cena "Dados"; não mexe nas outras cenas do arquivo.
#
# Cubo de 1 × 1 × 1 centrado na origem (o DiceTray escala). A ordem das faces
# tem que bater com DieView.NORMALS (+Y, -Y, +X, -X, +Z, -Z do Godot), que no
# Blender (Z para cima, -Y vira +Z) fica +Z, -Z, +X, -X, -Y, +Y.

import math
import os

HERE = os.path.join(os.environ.get("HQ_PROJECT", "/Users/mariotrazzigmail.com/Documents/GitHub/heros-quest-simulator"), "tools", "blender")
exec(open(os.path.join(HERE, "hq_common.py")).read(), globals())

from mathutils import Matrix

OUT_DIR = os.path.join(PROJECT, "assets", "models", "dice")
SCENE = "Dados"

FACE_NORMALS = [(0, 0, 1), (0, 0, -1), (1, 0, 0), (-1, 0, 0), (0, -1, 0), (0, 1, 0)]
# Mesma ordem de DieView.COMBAT_FACES e DieView.D6_FACES.
COMBAT_FACES = ["skull", "skull", "skull", "white_shield", "white_shield", "black_shield"]
D6_FACES = ["1", "6", "2", "5", "3", "4"]

TOP = 0.5      # a face de cima do cubo
RELIEF = 0.012  # quanto o símbolo sobe da face

IVORY = lambda: mat("die_ivory", srgb("efe9da"), 0.35)
RED = lambda: mat("die_red", srgb("b31d18"), 0.35)
INK = lambda: mat("die_ink", srgb("161312"), 0.4)
PIP = lambda: mat("die_pip", srgb("f6f3ea"), 0.35)


def cube(m):
	bpy.ops.mesh.primitive_cube_add(size=1.0)
	o = bpy.context.active_object
	mod = o.modifiers.new("bevel", "BEVEL")
	mod.width = 0.09
	mod.segments = 4
	mod.limit_method = "NONE"
	_done(o, m)


def flat_shape(points, z, thick, m):
	"""Polígono 2D (no plano XY) com espessura, apoiado em z."""
	# anti-horário, para a normal (e a espessura) apontar para fora da face
	area = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(points, points[1:] + points[:1]))
	if area < 0:
		points = points[::-1]
	me = bpy.data.meshes.new("shape")
	me.from_pydata([(x, y, z) for x, y in points], [], [list(range(len(points)))])
	o = bpy.data.objects.new("shape", me)
	bpy.context.collection.objects.link(o)
	bpy.context.view_layer.objects.active = o
	mod = o.modifiers.new("solid", "SOLIDIFY")
	mod.thickness = thick
	mod.offset = 1.0
	return _done(o, m, smooth=False)


def disc(x, y, z, r, thick, m, sx=1.0, sy=1.0):
	bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=r, depth=thick, location=(x, y, z + thick / 2))
	o = bpy.context.active_object
	o.scale = (sx, sy, 1.0)
	return _done(o, m, smooth=False)


def shield_points(w, h, n=14):
	"""Escudo: topo reto, laterais retas até o meio e ponta arredondada embaixo."""
	top, mid, bottom = h / 2, h * 0.05, -h / 2
	pts = [(-w / 2, top), (w / 2, top), (w / 2, mid)]
	for i in range(1, n):
		a = i / n * math.pi / 2
		pts.append((w / 2 * math.cos(a), mid - (mid - bottom) * math.sin(a)))
	pts.append((0.0, bottom))
	for i in range(n - 1, 0, -1):
		a = i / n * math.pi / 2
		pts.append((-w / 2 * math.cos(a), mid - (mid - bottom) * math.sin(a)))
	pts.append((-w / 2, mid))
	return pts


# Símbolos desenhados na face de cima (+Z), com o "alto" do desenho em +Y.

def sym_skull(body):
	z = TOP - 0.004
	disc(0, 0.05, z, 0.2, RELIEF, INK(), sy=0.95)                       # crânio
	flat_shape([(-0.12, -0.08), (0.12, -0.08), (0.1, -0.26), (-0.1, -0.26)], z, RELIEF, INK())  # maxilar
	for sx in (-1, 1):                                                  # órbitas
		disc(sx * 0.085, 0.03, z + 0.002, 0.06, RELIEF, body)
	flat_shape([(0, -0.05), (0.035, -0.12), (-0.035, -0.12)], z + 0.002, RELIEF, body)  # nariz
	for x in (-0.06, 0.0, 0.06):                                        # dentes
		flat_shape([(x - 0.014, -0.17), (x + 0.014, -0.17), (x + 0.014, -0.25), (x - 0.014, -0.25)],
			z + 0.002, RELIEF, body)


def sym_white_shield(body):
	z = TOP - 0.004
	flat_shape(shield_points(0.5, 0.62), z, RELIEF, INK())              # contorno
	flat_shape(shield_points(0.4, 0.52), z + 0.002, RELIEF, PIP())
	blue = mat("die_blue", srgb("2b55c4"), 0.4)
	flat_shape([(-0.025, 0.2), (0.025, 0.2), (0.025, -0.2), (-0.025, -0.2)], z + 0.004, RELIEF, blue)
	flat_shape([(-0.14, 0.08), (0.14, 0.08), (0.14, 0.03), (-0.14, 0.03)], z + 0.004, RELIEF, blue)


def sym_black_shield(body):
	z = TOP - 0.004
	flat_shape(shield_points(0.5, 0.62), z, RELIEF, INK())


PIPS = {
	1: [(0, 0)],
	2: [(-1, 1), (1, -1)],
	3: [(-1, 1), (0, 0), (1, -1)],
	4: [(-1, 1), (1, 1), (-1, -1), (1, -1)],
	5: [(-1, 1), (1, 1), (0, 0), (-1, -1), (1, -1)],
	6: [(-1, 1), (1, 1), (-1, 0), (1, 0), (-1, -1), (1, -1)],
}


def sym_pips(value):
	def draw(body):
		for px, py in PIPS[value]:
			disc(px * 0.22, py * 0.22, TOP - 0.004, 0.075, RELIEF, PIP())
	return draw


def on_face(draw, body, normal):
	"""Desenha o símbolo na face de cima e gira as peças novas para a face `normal`."""
	first = len(_parts)
	draw(body)
	n = Vector(normal)
	rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
	if n.z < -0.5:
		rot = Matrix.Rotation(math.pi, 4, "X")
	for o in _parts[first:]:
		o.matrix_world = rot @ o.matrix_world


def make_die(face_keys, body_fn):
	def build():
		body = body_fn()
		cube(body)
		for key, normal in zip(face_keys, FACE_NORMALS):
			if key == "skull":
				draw = sym_skull
			elif key == "white_shield":
				draw = sym_white_shield
			elif key == "black_shield":
				draw = sym_black_shield
			else:
				draw = sym_pips(int(key))
			on_face(draw, body, normal)
	return build


DICE = {"combat": make_die(COMBAT_FACES, IVORY), "d6": make_die(D6_FACES, RED)}


def run(only=None, do_export=True):
	return build_all(DICE, SCENE, OUT_DIR, only, do_export, spacing=0.5)
