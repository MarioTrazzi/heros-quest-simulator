# Monta as miniaturas dos heróis e monstros com primitivos do Blender
# e exporta um .glb por figura em assets/models/figures/<id>.glb.
#
# Rodar dentro do Blender (MCP ou Text Editor):
#   g = {}; exec(open("<projeto>/tools/blender/build_figures.py").read(), g); g["run"]()
# (as funções comuns vêm de hq_common.py, na mesma pasta).
# Cria/recria a cena "Figuras"; não mexe nas outras cenas do arquivo.
#
# Convenções: Z para cima, frente da figura para -Y (vira +Z no Godot,
# virado para a câmera inicial). Pés em z = 0; altura de um humano ~0,9.
# O Godot põe a base preta, o anel e o nome; o modelo é só a figura.

import math
import os

HERE = os.path.join(os.environ.get("HQ_PROJECT", "/Users/mariotrazzigmail.com/Documents/GitHub/heros-quest-simulator"), "tools", "blender")
exec(open(os.path.join(HERE, "hq_common.py")).read(), globals())

OUT_DIR = os.path.join(PROJECT, "assets", "models", "figures")
SCENE = "Figuras"

# ---------------------------------------------------------------- peças

def legs(hip_z, foot_x, r, m, boot=None, boot_h=0.1):
	for s in (-1, 1):
		limb((s * foot_x, 0, boot_h if boot else 0.0), (s * foot_x * 0.8, 0, hip_z), r, m)
		if boot:
			limb((s * foot_x, -0.02, 0.0), (s * foot_x, -0.02, boot_h), r * 1.25, boot)
			ball((s * foot_x, -0.05, 0.03), r * 1.2, boot, sy=1.5, sz=0.6)


def arm(shoulder, hand, r, m, hand_m=None, hand_r=None):
	limb(shoulder, hand, r, m)
	ball(shoulder, r * 1.25, m)
	ball(hand, hand_r or r * 1.1, hand_m or SKIN())


def sword(hand, length, m_blade, m_hilt, up=True, tilt=0.0, width=0.035):
	"""Espada na mão; up=True aponta para cima (ligeiramente para frente)."""
	hx, hy, hz = hand
	d = 1 if up else -1
	tip = (hx + tilt, hy - 0.08 * d, hz + length * d)
	base = (hx, hy, hz + 0.05 * d)
	limb((hx, hy, hz - 0.07 * d), base, 0.018, m_hilt)          # cabo
	limb((hx - 0.07, hy, hz + 0.05 * d), (hx + 0.07, hy, hz + 0.05 * d), 0.016, m_hilt)  # guarda
	b = limb(base, tip, width, m_blade, r2=0.006, seg=4)
	b.scale = (1.0, 0.3, 1.0)
	return b


def axe(hand, m_head, m_haft, length=0.45):
	hx, hy, hz = hand
	limb((hx, hy, hz - 0.12), (hx, hy, hz + length), 0.02, m_haft)
	head = box((hx + 0.07, hy, hz + length - 0.06), (0.14, 0.025, 0.14), m_head, bevel=0.01)
	return head


def staff(hand, m, top, length=0.95, top_m=None):
	hx, hy, hz = hand
	limb((hx, hy, 0.02), (hx, hy, hz + length * 0.45), 0.018, m)
	if top == "orb":
		ball((hx, hy, hz + length * 0.45 + 0.04), 0.05, top_m or m)
	elif top == "skull":
		ball((hx, hy, hz + length * 0.45 + 0.05), 0.055, top_m or WHITE(), sz=1.1)


def shield(center, r, m, rim):
	bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=r, depth=0.04, location=center,
		rotation=(math.pi / 2, 0, 0))
	_done(bpy.context.active_object, m)
	ring(center, r, 0.015, rim, rot=(math.pi / 2, 0, 0))
	ball((center[0], center[1] - 0.03, center[2]), r * 0.25, rim)


def eyes(z, y, x, r, m):
	mirror(ball, (x, y, z), r, m)


# ---------------------------------------------------------------- heróis

def barbarian():
	fur = mat("fur", srgb("8a6a45"), 0.95)
	hair = mat("blond", srgb("e8c35a"), 0.8)
	legs(0.38, 0.08, 0.055, SKIN(), boot=fur, boot_h=0.14)
	limb((0, 0, 0.32), (0, 0, 0.43), 0.13, fur, r2=0.12)               # tanga de pele
	limb((0, 0, 0.42), (0, 0, 0.66), 0.115, SKIN(), r2=0.15)            # tronco
	limb((0, 0, 0.42), (0, 0, 0.47), 0.122, LEATHER())                  # cinto
	ball((0, -0.12, 0.445), 0.025, GOLD(), sy=0.4)                      # fivela
	ball((0, 0, 0.67), 0.14, SKIN(), sx=1.25, sy=0.85, sz=0.5)          # ombros
	limb((0, 0, 0.68), (0, 0, 0.73), 0.05, SKIN())                      # pescoço
	ball((0, -0.01, 0.8), 0.085, SKIN())
	ball((0, 0.02, 0.83), 0.09, hair, sz=1.05)                          # cabelo
	limb((0, 0.06, 0.82), (0, 0.1, 0.62), 0.06, hair, r2=0.03)          # rabo de cavalo
	eyes(0.81, -0.075, 0.03, 0.012, BLACK())
	# braço direito ergue a espada larga; esquerdo solto
	arm((-0.19, 0, 0.64), (-0.26, -0.08, 0.72), 0.045, SKIN())
	arm((0.19, 0, 0.64), (0.23, -0.02, 0.4), 0.045, SKIN())
	mirror(ring, (0.2, 0, 0.6), 0.05, 0.012, fur)
	sword((-0.26, -0.08, 0.72), 0.6, STEEL(), LEATHER(), tilt=0.06, width=0.045)


def dwarf():
	tunic = mat("dwarf_tunic", srgb("a8551d"), 0.8)
	beard = mat("beard_orange", srgb("d96a1a"), 0.9)
	legs(0.24, 0.085, 0.06, mat("dwarf_pants", srgb("5a4632")), boot=LEATHER(), boot_h=0.1)
	limb((0, 0, 0.2), (0, 0, 0.52), 0.17, tunic, r2=0.16)               # tronco largo
	limb((0, 0, 0.27), (0, 0, 0.32), 0.172, LEATHER())
	box((0, -0.17, 0.295), (0.05, 0.02, 0.04), GOLD())
	ball((0, 0, 0.52), 0.17, tunic, sx=1.2, sy=0.9, sz=0.45)
	ball((0, -0.01, 0.63), 0.1, SKIN())
	ball((0, -0.085, 0.62), 0.03, SKIN())                               # nariz
	cone((0, -0.06, 0.6), (0, -0.11, 0.33), 0.1, beard)                 # barba
	ball((0, -0.07, 0.57), 0.09, beard, sz=0.7)
	eyes(0.655, -0.085, 0.035, 0.012, BLACK())
	ball((0, 0, 0.68), 0.105, STEEL(), sz=0.8)                          # elmo
	ring((0, 0, 0.66), 0.105, 0.015, GOLD())
	cone((0, 0, 0.75), (0, 0, 0.8), 0.03, STEEL())
	arm((-0.2, 0, 0.48), (-0.24, -0.1, 0.36), 0.05, tunic)
	arm((0.2, 0, 0.48), (0.24, -0.08, 0.34), 0.05, tunic)
	axe((-0.24, -0.1, 0.36), STEEL(), WOOD(), length=0.38)


def elf():
	green = mat("elf_green", srgb("3f8a3a"), 0.8)
	dark = mat("elf_dark", srgb("26502a"), 0.8)
	hair = mat("elf_hair", srgb("f0dc8c"), 0.7)
	legs(0.42, 0.06, 0.04, dark, boot=LEATHER(), boot_h=0.16)
	limb((0, 0, 0.36), (0, 0, 0.68), 0.1, green, r2=0.11)
	limb((0, 0, 0.3), (0, 0, 0.46), 0.12, green, r2=0.1)                # saia da túnica
	limb((0, 0, 0.44), (0, 0, 0.48), 0.104, LEATHER())
	ball((0, 0, 0.68), 0.11, green, sx=1.25, sy=0.85, sz=0.45)
	# capa
	c = box((0, 0.09, 0.45), (0.26, 0.02, 0.48), dark, rot=(0.1, 0, 0), bevel=0.008)
	ball((0, -0.01, 0.8), 0.075, SKIN(), sz=1.1)
	ball((0, 0.015, 0.83), 0.08, hair, sz=1.05)
	limb((0, 0.04, 0.82), (0, 0.06, 0.62), 0.06, hair, r2=0.03)
	mirror(cone, (0.07, 0, 0.8), (0.12, 0.02, 0.86), 0.018, SKIN())      # orelhas pontudas
	eyes(0.805, -0.068, 0.027, 0.01, mat("elf_eye", srgb("2a6a3a")))
	arm((-0.16, 0, 0.65), (-0.22, -0.12, 0.5), 0.035, green)
	arm((0.16, 0, 0.65), (0.2, -0.02, 0.42), 0.035, green)
	sword((-0.22, -0.12, 0.5), 0.45, STEEL(), GOLD(), tilt=0.02, width=0.03)


def wizard():
	robe = mat("wizard_robe", srgb("2f4fb8"), 0.8)
	star = mat("star", srgb("f2d36b"), 0.4, 0.5)
	limb((0, 0, 0.0), (0, 0, 0.68), 0.2, robe, r2=0.1)                  # túnica em cone
	ball((0, 0, 0.66), 0.11, robe, sx=1.3, sy=0.9, sz=0.5)
	limb((0, 0, 0.4), (0, 0, 0.44), 0.145, star)                        # faixa
	ball((0, -0.01, 0.76), 0.075, SKIN())
	cone((0, -0.05, 0.75), (0, -0.09, 0.5), 0.07, WHITE())              # barba longa
	eyes(0.775, -0.068, 0.027, 0.01, BLACK())
	limb((0, 0, 0.8), (0, 0, 0.82), 0.16, robe)                         # aba do chapéu
	cone((0, 0, 0.82), (0.04, 0.05, 1.12), 0.1, robe)                   # chapéu pontudo
	for p in ((0.05, -0.09, 0.9), (-0.06, -0.07, 0.96), (0.02, -0.05, 1.03)):
		ball(p, 0.014, star)
	arm((-0.17, 0, 0.62), (-0.25, -0.06, 0.48), 0.045, robe)
	arm((0.17, 0, 0.62), (0.2, -0.08, 0.44), 0.045, robe)
	staff((-0.25, -0.06, 0.48), WOOD(), "orb", length=1.0,
		top_m=mat("orb", srgb("7fd6ff"), 0.2, emit=srgb("3fa0ff")))


# ---------------------------------------------------------------- monstros

def _greenskin(skin, armor, small):
	k = 0.8 if small else 1.0
	legs(0.3 * k, 0.08, 0.05 * k, armor, boot=LEATHER(), boot_h=0.08)
	limb((0, 0.02, 0.28 * k), (0, 0.04, 0.6 * k), 0.13 * k, armor, r2=0.15 * k)  # curvado
	ball((0, 0.04, 0.6 * k), 0.15 * k, armor, sx=1.25, sy=0.9, sz=0.5)
	ball((0, -0.03, 0.68 * k), 0.095 * k, skin, sx=1.1, sz=0.95)
	ball((0, -0.12 * k, 0.66 * k), 0.035 * k, skin)                     # nariz
	eyes(0.7 * k, -0.105 * k, 0.04 * k, 0.016 * k, mat("red_eye", srgb("ff3a1a"), emit=srgb("ff2000")))
	return k


def goblin():
	skin = mat("goblin_skin", srgb("7aa83a"), 0.7)
	rags = mat("goblin_rags", srgb("6e5a3a"), 0.95)
	k = _greenskin(skin, rags, small=True)
	mirror(cone, (0.08, -0.02, 0.56), (0.2, 0.03, 0.6), 0.035, skin)    # orelhonas
	arm((-0.15, 0.02, 0.46), (-0.2, -0.12, 0.34), 0.035, skin, skin)
	arm((0.15, 0.02, 0.46), (0.19, -0.04, 0.28), 0.035, skin, skin)
	blade = sword((-0.2, -0.12, 0.34), 0.3, IRON(), LEATHER(), tilt=0.1, width=0.04)


def orc():
	skin = mat("orc_skin", srgb("4f7a2a"), 0.7)
	armor = mat("orc_armor", srgb("5a3a24"), 0.85)
	k = _greenskin(skin, armor, small=False)
	mirror(cone, (0.025, -0.1, 0.62), (0.03, -0.12, 0.69), 0.012, WHITE())  # presas
	mirror(cone, (0.085, -0.02, 0.7), (0.15, 0.0, 0.74), 0.025, skin)
	mirror(ball, (0.19, 0.04, 0.62), 0.07, IRON(), sz=0.6)              # ombreiras
	arm((-0.2, 0.04, 0.58), (-0.26, -0.1, 0.44), 0.045, skin, skin)
	arm((0.2, 0.04, 0.58), (0.25, -0.04, 0.36), 0.045, skin, skin)
	hx, hy, hz = (-0.26, -0.1, 0.44)
	limb((hx, hy, hz - 0.06), (hx, hy, hz + 0.12), 0.018, LEATHER())
	box((hx + 0.02, hy, hz + 0.24), (0.11, 0.02, 0.22), IRON(), rot=(0, 0.15, 0), bevel=0.006)  # cutelo


def fimir():
	skin = mat("fimir_skin", srgb("8a6a9a"), 0.6)
	belly = mat("fimir_belly", srgb("b59ab8"), 0.6)
	legs(0.32, 0.1, 0.07, skin)
	mirror(ball, (0.1, -0.04, 0.03), 0.07, skin, sy=1.4, sz=0.5)
	limb((0, 0.03, 0.28), (0, 0.02, 0.62), 0.16, skin, r2=0.17)
	ball((0, -0.06, 0.42), 0.12, belly, sx=1.1, sy=0.6, sz=1.3)
	ball((0, 0.02, 0.63), 0.17, skin, sx=1.25, sy=0.9, sz=0.55)
	ball((0, -0.04, 0.74), 0.1, skin, sy=1.1)
	ball((0, -0.13, 0.76), 0.035, mat("fimir_eye", srgb("ffe066"), emit=srgb("ffcc00")))  # olho único
	cone((0, -0.03, 0.82), (0, 0.0, 0.92), 0.05, skin)                  # crista
	# cauda grossa até o chão, atrás
	limb((0, 0.12, 0.3), (0, 0.32, 0.08), 0.07, skin, r2=0.03)
	ball((0, 0.33, 0.07), 0.05, IRON())
	arm((-0.21, 0.02, 0.6), (-0.27, -0.12, 0.44), 0.055, skin, skin)
	arm((0.21, 0.02, 0.6), (0.26, -0.04, 0.38), 0.055, skin, skin)
	hx, hy, hz = (-0.27, -0.12, 0.44)
	limb((hx, hy, hz - 0.06), (hx, hy, hz + 0.3), 0.02, WOOD())
	ball((hx, hy, hz + 0.32), 0.07, IRON())                             # maça
	for i in range(6):
		a = i * math.pi / 3
		cone((hx, hy, hz + 0.32), (hx + 0.1 * math.cos(a), hy + 0.1 * math.sin(a), hz + 0.32), 0.02, IRON(), seg=6)


def _chaos_armor():
	return mat("chaos_armor", srgb("1c1c22"), 0.35, 0.8)


def chaos_warrior():
	arm_m = _chaos_armor()
	trim = mat("chaos_trim", srgb("8a1a1a"), 0.5, 0.4)
	legs(0.38, 0.09, 0.065, arm_m, boot=arm_m, boot_h=0.12)
	limb((0, 0, 0.34), (0, 0, 0.68), 0.14, arm_m, r2=0.17)
	limb((0, 0, 0.32), (0, 0, 0.42), 0.15, trim, r2=0.13)
	ball((0, 0, 0.68), 0.16, arm_m, sx=1.3, sy=0.85, sz=0.5)
	for s in (-1, 1):                                                   # ombreiras com espinhos
		ball((s * 0.22, 0, 0.68), 0.09, arm_m, sz=0.7)
		cone((s * 0.22, 0, 0.72), (s * 0.28, 0, 0.84), 0.025, IRON(), seg=6)
	ball((0, 0, 0.82), 0.1, arm_m, sz=1.15)                             # elmo fechado
	box((0, -0.095, 0.82), (0.1, 0.01, 0.015), mat("chaos_glow", srgb("ff3010"), emit=srgb("ff2000")))
	for s in (-1, 1):                                                   # chifres
		limb((s * 0.07, 0, 0.88), (s * 0.14, 0, 0.94), 0.025, WHITE(), r2=0.018)
		cone((s * 0.14, 0, 0.94), (s * 0.15, 0, 1.04), 0.018, WHITE())
	arm((-0.22, 0, 0.62), (-0.27, -0.1, 0.48), 0.055, arm_m, IRON())
	arm((0.22, 0, 0.62), (0.25, -0.1, 0.46), 0.055, arm_m, IRON())
	sword((-0.27, -0.1, 0.48), 0.5, IRON(), trim, tilt=0.05, width=0.045)
	shield((0.27, -0.16, 0.46), 0.14, arm_m, trim)


def chaos_warlock():
	robe = mat("warlock_robe", srgb("5a1a6a"), 0.8)
	inner = mat("warlock_inner", srgb("2a0a30"), 0.8)
	limb((0, 0, 0.0), (0, 0, 0.68), 0.21, robe, r2=0.11)
	limb((0, -0.005, 0.0), (0, -0.01, 0.5), 0.17, inner, r2=0.08)
	ball((0, 0, 0.67), 0.13, _chaos_armor(), sx=1.3, sy=0.9, sz=0.5)
	ball((0, 0, 0.8), 0.095, _chaos_armor(), sz=1.15)
	box((0, -0.09, 0.8), (0.09, 0.01, 0.015), mat("warlock_glow", srgb("c040ff"), emit=srgb("a020ff")))
	for s in (-1, 1):
		limb((s * 0.06, 0, 0.86), (s * 0.1, -0.02, 0.98), 0.022, GOLD(), r2=0.01)
	box((0, 0.11, 0.44), (0.3, 0.02, 0.62), inner, rot=(0.12, 0, 0), bevel=0.008)  # capa
	arm((-0.18, 0, 0.62), (-0.25, -0.08, 0.5), 0.05, robe, _chaos_armor())
	arm((0.18, 0, 0.62), (0.22, -0.14, 0.62), 0.05, robe, _chaos_armor())
	ball((0.22, -0.18, 0.7), 0.04, mat("warlock_fire", srgb("ff60ff"), emit=srgb("d040ff")))
	staff((-0.25, -0.08, 0.5), IRON(), "skull", length=1.0)


def gargoyle():
	stone = mat("gargoyle_stone", srgb("7a7a80"), 0.95)
	dark = mat("gargoyle_dark", srgb("4a4a50"), 0.95)
	# agachada: coxas para frente, garras no chão
	for s in (-1, 1):
		limb((s * 0.12, -0.04, 0.0), (s * 0.13, -0.1, 0.18), 0.05, stone)
		limb((s * 0.13, -0.1, 0.18), (s * 0.11, 0.06, 0.3), 0.08, stone)
		ball((s * 0.12, -0.08, 0.02), 0.06, dark, sy=1.5, sz=0.5)
	limb((0, 0.06, 0.28), (0, -0.02, 0.62), 0.16, stone, r2=0.18)
	ball((0, -0.02, 0.62), 0.17, stone, sx=1.25, sy=0.9, sz=0.55)
	ball((0, -0.08, 0.74), 0.1, stone, sy=1.15)
	ball((0, -0.18, 0.72), 0.045, dark)                                 # focinho
	eyes(0.77, -0.16, 0.04, 0.018, mat("gargoyle_eye", srgb("ffb020"), emit=srgb("ff9000")))
	for s in (-1, 1):
		limb((s * 0.06, -0.06, 0.82), (s * 0.12, 0.0, 0.9), 0.025, dark, r2=0.012)  # chifres
		cone((s * 0.12, 0.0, 0.9), (s * 0.13, 0.08, 0.98), 0.012, dark)
		# asas: osso + membrana
		limb((s * 0.12, 0.1, 0.66), (s * 0.4, 0.2, 0.98), 0.025, dark)
		w = box((s * 0.3, 0.17, 0.75), (0.32, 0.015, 0.4), dark, rot=(0.2, s * -0.35, s * 0.15))
		arm((s * 0.21, -0.02, 0.6), (s * 0.18, -0.2, 0.32), 0.05, stone, dark)
	limb((0, 0.12, 0.25), (0, 0.32, 0.04), 0.045, stone, r2=0.02)       # cauda
	cone((0, 0.32, 0.04), (0, 0.4, 0.06), 0.035, dark, seg=4)


def skeleton():
	bone = mat("bone", srgb("e8e2cc"), 0.7)
	for s in (-1, 1):
		limb((s * 0.07, 0, 0.02), (s * 0.065, 0, 0.2), 0.022, bone)
		ball((s * 0.065, 0, 0.21), 0.03, bone)
		limb((s * 0.065, 0, 0.21), (s * 0.06, 0, 0.38), 0.025, bone)
		ball((s * 0.07, -0.03, 0.02), 0.03, bone, sy=1.6, sz=0.5)
	ball((0, 0, 0.4), 0.08, bone, sx=1.5, sy=0.8, sz=0.6)              # bacia
	limb((0, 0.02, 0.4), (0, 0.02, 0.72), 0.022, bone)                  # coluna
	for i in range(4):                                                  # costelas
		z = 0.5 + i * 0.05
		ring((0, 0.0, z), 0.09 - i * 0.004, 0.012, bone, rot=(0, 0, 0))
	limb((-0.15, 0, 0.7), (0.15, 0, 0.7), 0.018, bone)                  # clavículas
	ball((0, -0.01, 0.82), 0.085, bone, sz=1.05)
	box((0, -0.04, 0.755), (0.08, 0.06, 0.04), bone, bevel=0.01)        # mandíbula
	eyes(0.835, -0.07, 0.033, 0.024, BLACK())
	arm((-0.15, 0, 0.69), (-0.2, -0.1, 0.48), 0.02, bone, bone, 0.03)
	arm((0.15, 0, 0.69), (0.18, -0.03, 0.42), 0.02, bone, bone, 0.03)
	sword((-0.2, -0.1, 0.48), 0.42, IRON(), LEATHER(), tilt=0.04, width=0.035)


def zombie():
	skin = mat("zombie_skin", srgb("8a9a72"), 0.8)
	rags = mat("zombie_rags", srgb("5a5248"), 0.95)
	legs(0.38, 0.08, 0.05, rags, boot=skin, boot_h=0.06)
	limb((0, 0, 0.32), (0, -0.03, 0.66), 0.12, rags, r2=0.14)
	ball((0, -0.03, 0.66), 0.14, rags, sx=1.25, sy=0.85, sz=0.5)
	ball((0.02, -0.08, 0.77), 0.085, skin, sz=1.05)                     # cabeça tombada
	eyes(0.79, -0.15, 0.03, 0.016, mat("zombie_eye", srgb("d8e070"), emit=srgb("a0c000")))
	box((0.02, -0.155, 0.74), (0.05, 0.01, 0.015), BLACK())
	# braços esticados para frente
	arm((-0.17, -0.03, 0.62), (-0.14, -0.34, 0.6), 0.04, rags, skin)
	arm((0.17, -0.03, 0.62), (0.13, -0.36, 0.56), 0.04, rags, skin)


def mummy():
	wrap = mat("mummy_wrap", srgb("d8c8a0"), 0.95)
	shade = mat("mummy_shade", srgb("a8946a"), 0.95)
	legs(0.38, 0.075, 0.055, wrap)
	limb((0, 0, 0.32), (0, 0, 0.68), 0.12, wrap, r2=0.14)
	ball((0, 0, 0.68), 0.14, wrap, sx=1.25, sy=0.85, sz=0.5)
	ball((0, -0.01, 0.8), 0.085, wrap, sz=1.1)
	for i, z in enumerate((0.38, 0.46, 0.54, 0.62, 0.15, 0.25, 0.77, 0.84)):  # faixas
		r = 0.125 + 0.02 * (z - 0.3) if z > 0.3 else 0.06
		x = 0.0 if z > 0.3 else 0.077 * (1 if i % 2 else -1)
		if z > 0.7:
			r = 0.085
			x = 0.0
		ring((x, 0, z), r, 0.012, shade, rot=(0.15 * (1 if i % 2 else -1), 0, 0))
	eyes(0.815, -0.075, 0.03, 0.016, mat("mummy_eye", srgb("40ff80"), emit=srgb("20ff60")))
	arm((-0.17, 0, 0.64), (-0.14, -0.34, 0.62), 0.045, wrap, wrap)
	arm((0.17, 0, 0.64), (0.13, -0.32, 0.6), 0.045, wrap, wrap)
	box((0.06, 0.02, 0.2), (0.03, 0.01, 0.2), shade, rot=(0, 0.3, 0))  # ponta solta


# ---------------------------------------------------------------- aliados

def sir_ragnar():
	"""Cavaleiro do Imperador, prisioneiro: armadura, tabardo azul, sem arma."""
	tabard = mat("ragnar_tabard", srgb("2a4fa8"), 0.8)
	hair = mat("ragnar_hair", srgb("6a4a2a"), 0.8)
	legs(0.38, 0.08, 0.055, STEEL(), boot=IRON(), boot_h=0.12)
	limb((0, 0, 0.34), (0, 0, 0.68), 0.125, STEEL(), r2=0.15)
	box((0, -0.11, 0.42), (0.2, 0.03, 0.38), tabard, rot=(0.05, 0, 0))          # tabardo
	box((0, 0.11, 0.48), (0.22, 0.03, 0.34), tabard, rot=(-0.05, 0, 0))
	box((0, -0.128, 0.5), (0.05, 0.01, 0.24), GOLD())                           # faixa dourada
	limb((0, 0, 0.4), (0, 0, 0.44), 0.135, LEATHER())
	ball((0, 0, 0.68), 0.15, STEEL(), sx=1.3, sy=0.85, sz=0.5)
	mirror(ball, (0.2, 0, 0.67), 0.075, STEEL(), sz=0.7)                         # ombreiras
	ball((0, -0.01, 0.8), 0.08, SKIN())
	ball((0, 0.02, 0.83), 0.085, hair, sz=0.9)
	cone((0, -0.05, 0.78), (0, -0.07, 0.7), 0.05, hair)                          # barba curta
	eyes(0.81, -0.072, 0.028, 0.011, BLACK())
	# mãos juntas na frente, amarradas
	arm((-0.2, 0, 0.62), (-0.04, -0.14, 0.44), 0.045, STEEL(), SKIN())
	arm((0.2, 0, 0.62), (0.04, -0.14, 0.44), 0.045, STEEL(), SKIN())
	ring((0, -0.14, 0.44), 0.06, 0.014, mat("rope", srgb("b89a62"), 1.0), rot=(0, math.pi / 2, 0))


FIGURES = {
	"barbarian": barbarian, "dwarf": dwarf, "elf": elf, "wizard": wizard,
	"goblin": goblin, "orc": orc, "fimir": fimir, "chaos_warrior": chaos_warrior,
	"chaos_warlock": chaos_warlock, "gargoyle": gargoyle, "skeleton": skeleton,
	"zombie": zombie, "mummy": mummy, "sir_ragnar": sir_ragnar,
}


def run(only=None, do_export=True):
	return build_all(FIGURES, SCENE, OUT_DIR, only, do_export, spacing=0.3)
