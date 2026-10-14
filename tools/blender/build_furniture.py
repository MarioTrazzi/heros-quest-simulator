# Monta os móveis do HeroQuest (1989) e exporta um .glb por peça em
# assets/models/furniture/<id>.glb.
#
# Rodar dentro do Blender (MCP ou Text Editor):
#   g = {}; exec(open("<projeto>/tools/blender/build_furniture.py").read(), g); g["run"]()
# Cria/recria a cena "Moveis"; não mexe nas outras cenas do arquivo.
#
# Cada peça ocupa o tamanho "sem giro" do data/furniture.json (L em X, A em Y),
# centrada na origem, com a frente para -Y e as costas para +Y (no HeroScribe,
# rot 0 = virada para baixo, de costas para a parede de cima). O Godot gira
# a peça inteira conforme o rot.

import math
import os
import random

HERE = os.path.join(os.environ.get("HQ_PROJECT", "/Users/mariotrazzigmail.com/Documents/GitHub/heros-quest-simulator"), "tools", "blender")
exec(open(os.path.join(HERE, "hq_common.py")).read(), globals())

OUT_DIR = os.path.join(PROJECT, "assets", "models", "furniture")
SCENE = "Moveis"
MARGIN = 0.06  # folga até a borda do quadrado

DARK_WOOD = lambda: mat("dark_wood", srgb("4a2e1a"), 0.75)
PLANK = lambda: mat("plank", srgb("8a5e36"), 0.8)
STONE = lambda: mat("stone", srgb("8c8780"), 0.95)
STONE_DARK = lambda: mat("stone_dark", srgb("5e5a55"), 0.95)
SOOT = lambda: mat("soot", srgb("1a1714"), 1.0)
CLOTH_RED = lambda: mat("cloth_red", srgb("8a1c1c"), 0.9)
FLAME = lambda: mat("flame", srgb("ffb030"), 0.5, emit=srgb("ff7a10"))
FLAME_CORE = lambda: mat("flame_core", srgb("fff0a0"), 0.5, emit=srgb("ffd040"))
CANDLE = lambda: mat("candle", srgb("efe6c8"), 0.6)
ROPE = lambda: mat("rope", srgb("b89a62"), 1.0)


def candle(x, y, z, h=0.1):
	limb((x, y, z), (x, y, z + h), 0.018, CANDLE())
	ball((x, y, z + h + 0.022), 0.012, FLAME(), sz=1.8)


def skull(x, y, z, r=0.05, rot=0.0):
	ball((x, y, z + r), r, WHITE(), sz=1.05)
	box((x, y - r * 0.4, z + r * 0.35), (r * 1.1, r * 1.0, r * 0.7), WHITE(), bevel=r * 0.15)
	for sx in (-1, 1):
		ball((x + sx * r * 0.38, y - r * 0.82, z + r * 1.1), r * 0.25, BLACK())


def book(x, y, z, w, h, d, color, lean=0.0):
	box((x, y, z + h / 2), (w, d, h), mat("book_" + color, srgb(color), 0.8), rot=(0, lean, 0), bevel=0.004)


def flask(x, y, z, r, color, neck=0.05):
	m = mat("glass_" + color, srgb(color), 0.1, emit=srgb(color))
	ball((x, y, z + r), r, m)
	limb((x, y, z + r * 1.6), (x, y, z + r * 2 + neck), r * 0.3, m)


def table_frame(w, d, h, top_m, leg_m, top_t=0.06):
	"""Tampo + 4 pernas + travessas; devolve a altura do tampo."""
	box((0, 0, h - top_t / 2), (w, d, top_t), top_m, bevel=0.01)
	lx, ly = w / 2 - 0.12, d / 2 - 0.12
	for sx in (-1, 1):
		for sy in (-1, 1):
			box((sx * lx, sy * ly, (h - top_t) / 2), (0.08, 0.08, h - top_t), leg_m, bevel=0.008)
	for sy in (-1, 1):
		box((0, sy * ly, 0.1), (w - 0.3, 0.04, 0.04), leg_m)
	return h


# ---------------------------------------------------------------- móveis

def table():
	w, d = 3 - 2 * MARGIN, 2 - 2 * MARGIN
	h = table_frame(w, d, 0.42, PLANK(), DARK_WOOD())
	for i in range(1, 4):                                               # frestas das tábuas
		box((0, -d / 2 + i * d / 4, h + 0.001), (w - 0.04, 0.012, 0.004), DARK_WOOD())
	limb((0.6, -0.2, h), (0.6, -0.2, h + 0.1), 0.045, IRON())           # caneca
	ring((0.66, -0.2, h + 0.05), 0.03, 0.01, IRON(), rot=(math.pi / 2, 0, 0))
	limb((-0.5, 0.15, h), (-0.5, 0.15, h + 0.015), 0.14, mat("pewter", srgb("9a9a92"), 0.4, 0.8))  # prato
	ball((-0.5, 0.15, h + 0.05), 0.05, mat("bread", srgb("c08a4a"), 0.9), sx=1.4, sz=0.7)
	candle(0.0, 0.3, h)


def sorcerers_table():
	w, d = 3 - 2 * MARGIN, 2 - 2 * MARGIN
	h = table_frame(w, d, 0.42, DARK_WOOD(), DARK_WOOD())
	cloth = mat("cloth_purple", srgb("3a1a52"), 0.9)
	box((0, 0, h + 0.004), (w - 0.3, d - 0.2, 0.01), cloth)
	box((0, -d / 2 + 0.15, h - 0.08), (w - 0.3, 0.01, 0.17), cloth)      # pano caído na frente
	glow = mat("rune_glow", srgb("e0b0ff"), 0.4, emit=srgb("b060ff"))
	ring((0, 0, h + 0.012), 0.45, 0.012, glow)                          # círculo arcano
	ring((0, 0, h + 0.012), 0.32, 0.008, glow)
	for i in range(5):                                                  # pentagrama
		a1, a2 = math.radians(90 + i * 144), math.radians(90 + (i + 1) * 144)
		limb((0.32 * math.cos(a1), 0.32 * math.sin(a1), h + 0.012),
			(0.32 * math.cos(a2), 0.32 * math.sin(a2), h + 0.012), 0.007, glow, seg=6)
	ball((0, 0, h + 0.11), 0.09, mat("crystal", srgb("9ad8ff"), 0.05, emit=srgb("4080ff")))  # bola de cristal
	limb((0, 0, h + 0.01), (0, 0, h + 0.04), 0.07, GOLD(), r2=0.05)
	skull(-0.85, 0.3, h + 0.01, 0.07)
	candle(-1.15, -0.45, h, 0.14)
	candle(1.15, -0.45, h, 0.12)
	candle(1.1, 0.5, h, 0.16)
	book(0.8, 0.25, h + 0.01, 0.22, 0.04, 0.3, "6a1a1a")                # grimório aberto
	book(0.8, 0.25, h + 0.05, 0.36, 0.01, 0.28, "e8dcb8")


def alchemists_bench():
	w, d = 3 - 2 * MARGIN, 2 - 2 * MARGIN
	h = table_frame(w, d, 0.42, PLANK(), DARK_WOOD())
	# prateleira nas costas
	for sx in (-1, 1):
		box((sx * (w / 2 - 0.06), d / 2 - 0.12, h + 0.25), (0.06, 0.06, 0.5), DARK_WOOD())
	box((0, d / 2 - 0.12, h + 0.3), (w - 0.1, 0.18, 0.03), DARK_WOOD())
	rnd = random.Random(7)
	colors = ["40d060", "e04040", "4080ff", "e0c040", "c050e0"]
	for i in range(9):
		flask(-1.2 + i * 0.3, d / 2 - 0.12, h + 0.315, 0.035 + rnd.random() * 0.02, colors[i % 5])
	# retorta e alambique
	flask(-0.7, 0.0, h, 0.09, "40d060", neck=0.08)
	limb((-0.7, 0.0, h + 0.26), (-0.4, -0.05, h + 0.2), 0.012, mat("glass_clear", srgb("d0e8f0"), 0.05))
	limb((-0.7, 0.0, h - 0.01), (-0.7, 0.0, h + 0.02), 0.07, IRON())     # fogareiro
	ball((-0.7, 0.0, h + 0.03), 0.03, FLAME())
	# almofariz e pilão
	limb((0.2, -0.3, h), (0.2, -0.3, h + 0.08), 0.06, STONE(), r2=0.08)
	limb((0.22, -0.3, h + 0.05), (0.3, -0.28, h + 0.16), 0.015, STONE())
	# balança
	limb((0.8, 0.05, h), (0.8, 0.05, h + 0.25), 0.012, GOLD())
	limb((0.65, 0.05, h + 0.25), (0.95, 0.05, h + 0.25), 0.008, GOLD())
	for sx in (0.65, 0.95):
		limb((sx, 0.05, h + 0.12), (sx, 0.05, h + 0.13), 0.06, GOLD())
	flask(1.15, -0.4, h, 0.05, "e0c040")
	flask(-0.2, 0.25, h, 0.06, "c050e0")
	book(-1.15, -0.35, h, 0.25, 0.05, 0.32, "3a5a2a")


def tomb():
	w, d = 2 - 2 * MARGIN - 0.2, 3 - 2 * MARGIN - 0.2
	box((0, 0, 0.04), (w + 0.12, d + 0.12, 0.08), STONE_DARK(), bevel=0.01)  # pedestal
	box((0, 0, 0.26), (w, d, 0.36), STONE(), bevel=0.015)
	for sy in (-1, 1):                                                  # frisos laterais
		for sx in (-1, 1):
			box((sx * (w / 2 + 0.005), sy * d * 0.25, 0.26), (0.01, d * 0.35, 0.22), STONE_DARK())
	box((0, 0, 0.48), (w + 0.08, d + 0.08, 0.08), STONE(), bevel=0.02)   # tampa
	box((0, 0, 0.53), (w - 0.1, d - 0.1, 0.03), STONE(), bevel=0.01)
	# espada de pedra entalhada na tampa (ponta para os pés, frente = -Y)
	box((0, 0.1, 0.555), (0.07, d * 0.62, 0.025), STONE_DARK(), bevel=0.006)
	box((0, d * 0.32, 0.555), (0.36, 0.06, 0.025), STONE_DARK(), bevel=0.006)
	ball((0, d * 0.42, 0.565), 0.04, STONE_DARK())
	skull(0, -d * 0.35, 0.545, 0.06)


def rack():
	w, d = 2 - 2 * MARGIN - 0.3, 3 - 2 * MARGIN - 0.1
	for sx in (-1, 1):                                                  # longarinas
		box((sx * w / 2, 0, 0.38), (0.1, d, 0.1), DARK_WOOD(), bevel=0.01)
		for sy in (-1, 1):
			box((sx * w / 2, sy * (d / 2 - 0.08), 0.19), (0.1, 0.1, 0.38), DARK_WOOD(), bevel=0.01)
	for i in range(7):                                                  # ripas do leito
		box((0, -d / 2 + 0.55 + i * 0.27, 0.39), (w - 0.1, 0.12, 0.03), PLANK())
	for sy in (-1, 1):                                                  # rolos e manivelas
		y = sy * (d / 2 - 0.2)
		limb((-w / 2 - 0.08, y, 0.48), (w / 2 + 0.08, y, 0.48), 0.06, PLANK())
		for sx in (-1, 1):
			limb((sx * w / 2, y, 0.38), (sx * w / 2, y, 0.48), 0.04, DARK_WOOD())
		for k in range(4):
			a = k * math.pi / 2
			limb((w / 2 + 0.1, y, 0.48), (w / 2 + 0.1, y + 0.17 * math.cos(a), 0.48 + 0.17 * math.sin(a)), 0.014, DARK_WOOD())
		for sx in (-0.15, 0.15):                                        # cordas até o centro
			limb((sx, y, 0.5), (sx * 0.6, y * 0.55, 0.43), 0.012, ROPE())
	for sx in (-0.15, 0.15):
		ring((sx * 0.6, 0.0, 0.43), 0.04, 0.01, IRON(), rot=(0, math.pi / 2, 0))
		limb((sx * 0.6, -0.04, 0.43), (sx * 0.6, 0.04 - d * 0.0, 0.43), 0.008, IRON())


def _back_y(depth):
	"""Centro em Y de uma peça de profundidade depth encostada na parede (+Y)."""
	return 0.5 - MARGIN / 2 - depth / 2


def bookcase():
	w, depth, h = 3 - 2 * MARGIN, 0.5, 0.85
	y = _back_y(depth)
	box((0, y + depth / 2 - 0.02, h / 2), (w, 0.04, h), DARK_WOOD())    # fundo
	for sx in (-1, 0, 1):
		box((sx * (w / 2 - 0.03) if sx else 0, y, h / 2), (0.06, depth, h), DARK_WOOD(), bevel=0.008)
	shelves = [0.03, 0.3, 0.57, 0.84]
	for z in shelves:
		box((0, y, z), (w, depth, 0.04), DARK_WOOD(), bevel=0.006)
	box((0, y - 0.02, h + 0.04), (w + 0.06, depth + 0.06, 0.05), DARK_WOOD(), bevel=0.01)  # cornija
	rnd = random.Random(3)
	colors = ["7a1e1e", "1e3a6a", "2e5a2a", "6a4a1a", "4a2a5a", "8a6a2a", "2a2a2a"]
	for zi in range(3):
		for half in (-1, 1):
			x = half * 0.04 if half > 0 else -w / 2 + 0.07
			end = w / 2 - 0.07 if half > 0 else -0.04
			while x < end - 0.06:
				bw = 0.03 + rnd.random() * 0.035
				bh = 0.17 + rnd.random() * 0.07
				if rnd.random() < 0.08:                                 # vão com caveira ou nada
					x += 0.12
					continue
				book(x + bw / 2, y + 0.02, shelves[zi] + 0.02, bw, bh, depth * 0.75,
					colors[rnd.randrange(len(colors))])
				x += bw + 0.004
	skull(0.75, y - 0.05, shelves[2] + 0.02, 0.05)


def cupboard():
	w, depth, h = 3 - 2 * MARGIN - 0.1, 0.55, 0.62
	y = _back_y(depth)
	box((0, y, h / 2 + 0.04), (w, depth, h), PLANK(), bevel=0.012)
	box((0, y, 0.02), (w + 0.04, depth + 0.04, 0.04), DARK_WOOD())
	box((0, y, h + 0.07), (w + 0.06, depth + 0.06, 0.04), DARK_WOOD(), bevel=0.01)
	front = y - depth / 2
	for i in range(3):                                                  # três portas
		x = -w / 3 + i * w / 3
		box((x, front - 0.005, h / 2 + 0.04), (w / 3 - 0.06, 0.02, h - 0.1), DARK_WOOD(), bevel=0.006)
		box((x, front - 0.017, h / 2 + 0.04), (w / 3 - 0.18, 0.01, h - 0.22), PLANK())
		ball((x + (0.3 if i < 2 else -0.3), front - 0.03, h / 2 + 0.04), 0.022, GOLD())
	# potes e garrafas em cima
	rnd = random.Random(11)
	for i in range(7):
		x = -w / 2 + 0.2 + i * (w - 0.4) / 6
		if i % 3 == 1:
			flask(x, y, h + 0.09, 0.04, ["40d060", "e04040", "4080ff"][i % 3])
		else:
			r = 0.05 + rnd.random() * 0.03
			limb((x, y, h + 0.09), (x, y, h + 0.09 + r * 2.2), r, mat("clay", srgb("a8643a"), 0.9), r2=r * 0.7)


def fireplace():
	w, depth, h = 3 - 2 * MARGIN, 0.6, 0.95
	y = _back_y(depth)
	front, back = y - depth / 2, y + depth / 2
	mid = w - 0.64                                                      # largura da boca
	box((0, back - 0.06, 0.32), (mid, 0.12, 0.64), STONE())             # fundo da boca
	box((0, back - 0.125, 0.32), (mid - 0.02, 0.01, 0.6), SOOT())
	box((0, y, 0.006), (mid, depth, 0.012), SOOT())
	for sx in (-1, 1):                                                  # pilares
		box((sx * (w / 2 - 0.16), y, 0.32), (0.32, depth, 0.64), STONE(), bevel=0.015)
	box((0, y - 0.03, 0.68), (w, depth + 0.06, 0.09), STONE_DARK(), bevel=0.015)  # consolo
	cy, cd = y + 0.1, depth - 0.2
	box((0, cy, (0.72 + h) / 2), (w * 0.75, cd, h - 0.72), STONE(), bevel=0.01)  # chaminé
	for i in range(5):                                                  # pedras aparentes
		box((-0.8 + i * 0.4, cy - cd / 2 - 0.004, 0.79 + (i % 2) * 0.08), (0.24, 0.01, 0.05), STONE_DARK())
	box((0, front - 0.02, 0.02), (mid + 0.1, 0.16, 0.04), STONE_DARK()) # soleira
	for a in (-1, 1):                                                   # lenha cruzada
		limb((-0.35, y + a * 0.06, 0.05), (0.35, y - a * 0.06, 0.07), 0.045, WOOD())
	for x, hh, r in ((-0.22, 0.28, 0.08), (0.0, 0.4, 0.1), (0.22, 0.26, 0.07), (0.1, 0.2, 0.06), (-0.1, 0.22, 0.06)):
		cone((x, y, 0.06), (x, y, 0.06 + hh), r, FLAME())               # chamas
		cone((x, y - 0.03, 0.06), (x, y - 0.03, 0.06 + hh * 0.6), r * 0.5, FLAME_CORE())
	ball((0.0, y + 0.02, 0.5), 0.1, IRON(), sz=0.8)                     # caldeirão pendurado
	limb((0.0, y + 0.02, 0.57), (0.0, y + 0.02, 0.64), 0.008, IRON())
	for x in (-1.0, 1.0):
		candle(x, y - 0.12, 0.725, 0.1)
	skull(-0.55, y - 0.15, 0.725, 0.05)


def weapons_rack():
	w, depth, h = 3 - 2 * MARGIN - 0.1, 0.35, 0.8
	y = _back_y(depth)
	for sx in (-1, 1):
		box((sx * w / 2, y, h / 2), (0.08, 0.08, h), DARK_WOOD(), bevel=0.008)
		box((sx * w / 2, y, 0.03), (0.1, depth, 0.06), DARK_WOOD(), bevel=0.008)
	for z in (0.2, 0.62):
		box((0, y, z), (w, 0.06, 0.05), DARK_WOOD(), bevel=0.006)
	box((0, y - 0.05, 0.05), (w, 0.2, 0.05), DARK_WOOD())                # canaleta do pé
	for i, x in enumerate((-1.05, -0.85, -0.65)):                       # lanças
		limb((x, y - 0.05, 0.06), (x, y - 0.02, 0.95), 0.014, WOOD())
		cone((x, y - 0.02, 0.95), (x, y - 0.02, 1.05), 0.03, STEEL(), seg=4)
	for x in (-0.35, -0.15):                                            # espadas de ponta para baixo
		limb((x, y - 0.05, 0.08), (x, y - 0.05, 0.55), 0.025, STEEL(), r2=0.02, seg=4)
		limb((x - 0.06, y - 0.05, 0.56), (x + 0.06, y - 0.05, 0.56), 0.012, GOLD())
		limb((x, y - 0.05, 0.56), (x, y - 0.05, 0.68), 0.014, LEATHER())
		ball((x, y - 0.05, 0.69), 0.018, GOLD())
	for x in (0.15, 0.4):                                               # machados
		limb((x, y - 0.05, 0.06), (x, y - 0.05, 0.75), 0.016, WOOD())
		box((x + 0.06, y - 0.05, 0.66), (0.12, 0.02, 0.14), STEEL(), bevel=0.008)
	for x, r in ((0.75, 0.16), (1.05, 0.13)):                           # escudos pendurados
		bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=r, depth=0.03,
			location=(x, y - 0.07, 0.45), rotation=(math.pi / 2, 0, 0))
		_done(bpy.context.active_object, CLOTH_RED() if r > 0.15 else mat("shield_blue", srgb("2a4a8a"), 0.7))
		ring((x, y - 0.085, 0.45), r, 0.012, IRON(), rot=(math.pi / 2, 0, 0))
		ball((x, y - 0.09, 0.45), r * 0.25, IRON())


def throne():
	s = 1 - 2 * MARGIN - 0.12
	gold = GOLD()
	box((0, 0, 0.04), (s, s, 0.08), STONE_DARK(), bevel=0.01)            # degrau
	box((0, 0.02, 0.24), (s * 0.8, s * 0.75, 0.3), DARK_WOOD(), bevel=0.012)
	box((0, 0.0, 0.41), (s * 0.7, s * 0.65, 0.05), CLOTH_RED(), bevel=0.02)  # almofada
	box((0, s / 2 - 0.08, 0.6), (s * 0.82, 0.1, 0.95), DARK_WOOD(), bevel=0.012)  # espaldar
	box((0, s / 2 - 0.135, 0.62), (s * 0.6, 0.01, 0.7), CLOTH_RED())
	for sx in (-1, 1):
		box((sx * s * 0.4, 0.0, 0.5), (0.08, s * 0.7, 0.06), DARK_WOOD(), bevel=0.01)  # braços
		ball((sx * s * 0.4, -s * 0.35, 0.52), 0.045, gold)
		cone((sx * s * 0.37, s / 2 - 0.08, 1.07), (sx * s * 0.37, s / 2 - 0.08, 1.2), 0.04, gold)
	ball((0, s / 2 - 0.08, 1.1), 0.07, gold, sy=0.5)
	skull(0, s / 2 - 0.15, 0.98, 0.05)


def treasure_chest():
	w, d, h = 0.66, 0.46, 0.24
	box((0, 0, h / 2), (w, d, h), PLANK(), bevel=0.01)
	bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=d / 2, depth=w, location=(0, 0, h),
		rotation=(0, math.pi / 2, 0))
	lid = _done(bpy.context.active_object, PLANK())
	# corta a metade de baixo da tampa (só a abóbada fica)
	import bmesh
	bm = bmesh.new()
	bm.from_mesh(lid.data)
	# o giro de 90° em Y leva o +X local para baixo
	bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
		plane_no=(1, 0, 0), clear_outer=True)
	bm.to_mesh(lid.data)
	bm.free()
	for x in (-w / 2 + 0.06, 0, w / 2 - 0.06):                          # cintas de ferro
		box((x, 0, h / 2), (0.04, d + 0.012, h + 0.005), IRON())
		bpy.ops.mesh.primitive_torus_add(major_radius=d / 2 + 0.005, minor_radius=0.012,
			major_segments=20, minor_segments=4, location=(x, 0, h), rotation=(0, math.pi / 2, 0))
		_done(bpy.context.active_object, IRON())
	box((0, -d / 2 - 0.012, h - 0.01), (0.08, 0.02, 0.1), GOLD(), bevel=0.005)  # fechadura
	box((0, -d / 2 - 0.022, h - 0.03), (0.015, 0.005, 0.03), BLACK())
	for sx in (-1, 1):                                                  # pés
		for sy in (-1, 1):
			box((sx * (w / 2 - 0.04), sy * (d / 2 - 0.04), 0.01), (0.06, 0.06, 0.02), IRON())
	# moedas saindo pela fresta
	for i, x in enumerate((-0.12, -0.05, 0.03, 0.1)):
		limb((x, -d / 2 + 0.02, h + 0.005 + (i % 2) * 0.01), (x, -d / 2 + 0.03, h + 0.012 + (i % 2) * 0.01), 0.025, GOLD())


def rubble():
	"""Quadrado bloqueado: monte de pedras caídas."""
	rnd = random.Random(5)
	for i in range(16):
		r = 0.08 + rnd.random() * 0.12
		x, y = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
		z = r * 0.6 + (0.25 - math.hypot(x, y)) * 0.6 * rnd.random()
		bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=(x, y, max(z, r * 0.5)))
		o = bpy.context.active_object
		o.scale = (1.0 + rnd.random() * 0.4, 1.0 + rnd.random() * 0.4, 0.7 + rnd.random() * 0.3)
		o.rotation_euler = (rnd.random() * 3, rnd.random() * 3, rnd.random() * 3)
		_done(o, STONE() if i % 3 else STONE_DARK(), smooth=False)
	for i in range(10):                                                 # cascalho
		x, y = rnd.uniform(-0.42, 0.42), rnd.uniform(-0.42, 0.42)
		bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.03 + rnd.random() * 0.03, location=(x, y, 0.02))
		_done(bpy.context.active_object, STONE_DARK(), smooth=False)


def stairway():
	"""Escada que desce (2×2): moldura de pedra e degraus cada vez mais escuros
	até a parede de trás. É baixa (o herói pisa nela)."""
	s = 2 - 2 * MARGIN
	for sx in (-1, 1):                                                  # muretas laterais
		box((sx * (s / 2 - 0.06), 0.06, 0.05), (0.12, s - 0.12, 0.1), STONE(), bevel=0.01)
	box((0, s / 2 - 0.06, 0.05), (s, 0.12, 0.1), STONE(), bevel=0.01)  # parede de trás
	steps = 6
	inner = s - 0.24
	depth = (s - 0.12) / steps
	for i in range(steps):
		k = i / (steps - 1)
		c = tuple(v * (1.0 - 0.85 * k) for v in srgb("9a958c"))
		m = mat("step_%d" % i, c, 0.95)
		y = -s / 2 + depth * (i + 0.5)
		z = 0.035 - k * 0.025
		box((0, y, z / 2), (inner, depth - 0.012, z), m, bevel=0.004)
		box((0, y - depth / 2 + 0.006, z), (inner, 0.012, 0.006), STONE_DARK())  # quina do degrau


FURNITURE = {
	"table": table, "sorcerers_table": sorcerers_table, "alchemists_bench": alchemists_bench,
	"tomb": tomb, "rack": rack, "bookcase": bookcase, "cupboard": cupboard,
	"fireplace": fireplace, "weapons_rack": weapons_rack, "throne": throne,
	"treasure_chest": treasure_chest, "rubble": rubble, "stairway": stairway,
}


def run(only=None, do_export=True):
	return build_all(FURNITURE, SCENE, OUT_DIR, only, do_export, spacing=0.4)
