# Texturas do tabuleiro (assadas de materiais procedurais) e modelos de porta.
#
# Rodar dentro do Blender (MCP ou Text Editor):
#   g = {}; exec(open("<projeto>/tools/blender/build_board.py").read(), g); g["run"]()
# Cria/recria a cena "Tabuleiro"; não mexe nas outras cenas do arquivo.
#
# Saída:
#   assets/textures/board/<nome>_albedo.png e <nome>_normal.png
#     floor_room (lajes das salas), floor_corridor (pedras do corredor),
#     wall (tijolos; repete a cada 1 m, o Godot usa triplanar)
#   assets/models/board/door.glb        folha de madeira: dobradiça na origem, vai até +X
#   assets/models/board/secret_door.glb folha de pedra, mesmo encaixe
#   assets/models/board/door_frame.glb  batente: centrado na aresta, ao longo de X

import math
import os

HERE = os.path.join(os.environ.get("HQ_PROJECT", "/Users/mariotrazzigmail.com/Documents/GitHub/heros-quest-simulator"), "tools", "blender")
exec(open(os.path.join(HERE, "hq_common.py")).read(), globals())

TEX_DIR = os.path.join(PROJECT, "assets", "textures", "board")
OUT_DIR = os.path.join(PROJECT, "assets", "models", "board")
SCENE = "Tabuleiro"
TEX_SIZE = 1024

# Medidas que precisam bater com o BoardView.
WALL_HEIGHT = 0.8
DOOR_HEIGHT = 0.7
DOOR_WIDTH = 0.88

# ---------------------------------------------------------------- texturas

def _nodes(m):
	m.use_nodes = True
	nt = m.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
	nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
	coord = nt.nodes.new("ShaderNodeTexCoord")
	return nt, bsdf, coord


def _ramp(nt, src, stops):
	r = nt.nodes.new("ShaderNodeValToRGB")
	els = r.color_ramp.elements
	els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
	els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
	for pos, col in stops[1:-1]:
		e = els.new(pos)
		e.color = (*col, 1)
	nt.links.new(src, r.inputs["Fac"])
	return r


def _math(nt, op, a, b=None, clamp=False):
	n = nt.nodes.new("ShaderNodeMath")
	n.operation = op
	n.use_clamp = clamp
	for i, v in enumerate((a, b)):
		if v is None:
			continue
		if isinstance(v, (int, float)):
			n.inputs[i].default_value = v
		else:
			nt.links.new(v, n.inputs[i])
	return n.outputs[0]


def _mix(nt, fac, c1, c2):
	n = nt.nodes.new("ShaderNodeMix")
	n.data_type = "RGBA"
	for sock, v in ((n.inputs[0], fac), (n.inputs[6], c1), (n.inputs[7], c2)):
		if isinstance(v, (int, float)):
			sock.default_value = v
		elif isinstance(v, tuple):
			sock.default_value = (*v, 1)
		else:
			nt.links.new(v, sock)
	return n.outputs[2]


def _bump(nt, bsdf, height, strength):
	b = nt.nodes.new("ShaderNodeBump")
	b.inputs["Strength"].default_value = strength
	nt.links.new(height, b.inputs["Height"])
	nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])


def stones_material(name, scale, light, dark, grout, edge=0.04, rough_scale=8.0):
	"""Pedras irregulares (Voronoi) com rejunte: lajes ou calçamento."""
	m = bpy.data.materials.new("tex_" + name)
	nt, bsdf, coord = _nodes(m)
	vor = nt.nodes.new("ShaderNodeTexVoronoi")
	vor.feature = "DISTANCE_TO_EDGE"
	vor.voronoi_dimensions = "2D"
	vor.inputs["Scale"].default_value = scale
	vor.inputs["Randomness"].default_value = 0.85
	nt.links.new(coord.outputs["UV"], vor.inputs["Vector"])
	cell = nt.nodes.new("ShaderNodeTexVoronoi")                      # cor por pedra
	cell.voronoi_dimensions = "2D"
	cell.inputs["Scale"].default_value = scale
	cell.inputs["Randomness"].default_value = 0.85
	nt.links.new(coord.outputs["UV"], cell.inputs["Vector"])
	noise = nt.nodes.new("ShaderNodeTexNoise")
	noise.inputs["Scale"].default_value = rough_scale
	noise.inputs["Detail"].default_value = 8.0
	nt.links.new(coord.outputs["UV"], noise.inputs["Vector"])
	# máscara do rejunte: 0 no rejunte, 1 na pedra (borda suave)
	stone = _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", vor.outputs["Distance"], edge * 0.5), 1.0 / (edge * 0.5), clamp=True)
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	nt.links.new(cell.outputs["Color"], sep.inputs["Color"])
	tone = _ramp(nt, sep.outputs["Red"], [(0.0, dark), (1.0, light)])
	dirty = _mix(nt, _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", noise.outputs["Fac"], 0.35, clamp=True), 1.6), tone.outputs["Color"], tuple(v * 0.55 for v in dark))
	color = _mix(nt, stone, grout, dirty)
	nt.links.new(color, bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.9
	height = _math(nt, "ADD", _math(nt, "MULTIPLY", stone, 0.8), _math(nt, "MULTIPLY", noise.outputs["Fac"], 0.2))
	_bump(nt, bsdf, height, 0.6)
	return m


def brick_material(name):
	"""Tijolos de pedra: 4 fileiras e 2 blocos por metro (repete a cada 1 m)."""
	m = bpy.data.materials.new("tex_" + name)
	nt, bsdf, coord = _nodes(m)
	brick = nt.nodes.new("ShaderNodeTexBrick")
	brick.offset = 0.5
	brick.offset_frequency = 2
	brick.inputs["Scale"].default_value = 1.0
	brick.inputs["Brick Width"].default_value = 0.5
	brick.inputs["Row Height"].default_value = 0.25
	brick.inputs["Mortar Size"].default_value = 0.012
	brick.inputs["Mortar Smooth"].default_value = 0.3
	brick.inputs["Bias"].default_value = 0.0
	brick.inputs["Color1"].default_value = (*srgb("958c7e"), 1)
	brick.inputs["Color2"].default_value = (*srgb("625b52"), 1)
	brick.inputs["Mortar"].default_value = (*srgb("3a3632"), 1)
	nt.links.new(coord.outputs["UV"], brick.inputs["Vector"])
	noise = nt.nodes.new("ShaderNodeTexNoise")
	noise.inputs["Scale"].default_value = 12.0
	noise.inputs["Detail"].default_value = 8.0
	nt.links.new(coord.outputs["UV"], noise.inputs["Vector"])
	color = _mix(nt, _math(nt, "MULTIPLY", _math(nt, "SUBTRACT", noise.outputs["Fac"], 0.3, clamp=True), 1.4), brick.outputs["Color"], srgb("4a453f"))
	nt.links.new(color, bsdf.inputs["Base Color"])
	bsdf.inputs["Roughness"].default_value = 0.92
	height = _math(nt, "ADD", _math(nt, "SUBTRACT", 1.0, brick.outputs["Fac"]), _math(nt, "MULTIPLY", noise.outputs["Fac"], 0.15))
	_bump(nt, bsdf, height, 0.5)
	return m


def bake(material, name):
	"""Assa cor (albedo) e normal do material num plano 1×1 e salva os PNGs."""
	bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
	plane = bpy.context.active_object
	plane.name = "bake_" + name
	plane.data.materials.append(material)
	nt = material.node_tree
	for kind in ("albedo", "normal"):
		img_name = "%s_%s" % (name, kind)
		old = bpy.data.images.get(img_name)
		if old:
			bpy.data.images.remove(old)
		img = bpy.data.images.new(img_name, TEX_SIZE, TEX_SIZE, alpha=False, float_buffer=False)
		if kind == "normal":
			img.colorspace_settings.name = "Non-Color"
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = img
		for n in nt.nodes:
			n.select = False
		tex.select = True
		nt.nodes.active = tex
		bpy.ops.object.select_all(action="DESELECT")
		plane.select_set(True)
		bpy.context.view_layer.objects.active = plane
		if kind == "albedo":
			bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=0)
		else:
			bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=0)
		img.filepath_raw = os.path.join(TEX_DIR, img_name + ".png")
		img.file_format = "PNG"
		img.save()
		nt.nodes.remove(tex)
	return plane


def bake_all():
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.samples = 8
	sc.cycles.device = "CPU"
	os.makedirs(TEX_DIR, exist_ok=True)
	bake(stones_material("floor_room", 2.6, srgb("c2aa88"), srgb("7e684e"), srgb("3e342a"), edge=0.035), "floor_room")
	bake(stones_material("floor_corridor", 5.0, srgb("9a9894"), srgb("55534f"), srgb("2a2826"), edge=0.05, rough_scale=14.0), "floor_corridor")
	bake(brick_material("wall"), "wall")
	sc.render.engine = "BLENDER_EEVEE"


# ---------------------------------------------------------------- portas

def door():
	"""Folha de tábuas com cintas de ferro e argola; dobradiça em x = 0."""
	w, h, t = DOOR_WIDTH, DOOR_HEIGHT, 0.07
	planks = 5
	for i in range(planks):
		pw = w / planks
		x = pw * (i + 0.5)
		tone = PLANK() if i % 2 == 0 else mat("plank2", srgb("7a5030"), 0.8)
		box((x, 0, h / 2), (pw - 0.008, t, h - 0.01), tone, bevel=0.006)
	for z in (0.14, h - 0.14):                                          # cintas
		for sy in (-1, 1):
			box((w * 0.45, sy * (t / 2 + 0.006), z), (w * 0.88, 0.012, 0.05), IRON())
			for k in range(4):
				ball((0.08 + k * 0.22, sy * (t / 2 + 0.014), z), 0.012, IRON())
	for sy in (-1, 1):                                                  # argolas
		ring((w * 0.82, sy * (t / 2 + 0.03), h * 0.5), 0.04, 0.008, IRON(), rot=(math.pi / 2, 0, 0))
		ball((w * 0.82, sy * (t / 2 + 0.01), h * 0.55), 0.016, IRON())
	for z in (0.14, h - 0.14):                                          # dobradiças
		limb((0.0, 0, z - 0.05), (0.0, 0, z + 0.05), 0.018, IRON())


def secret_door():
	"""Folha de pedra (porta secreta achada): blocos com a mesma cara da parede."""
	w, h, t = DOOR_WIDTH, DOOR_HEIGHT, 0.08
	stone_a, stone_b = mat("door_stone_a", srgb("8e877c"), 0.95), mat("door_stone_b", srgb("6e675e"), 0.95)
	rows = 4
	for r in range(rows):
		rh = h / rows
		blocks = [0.5, 0.5] if r % 2 == 0 else [0.25, 0.5, 0.25]
		x = 0.0
		for i, bw in enumerate(blocks):
			bw *= w
			box((x + bw / 2, 0, rh * (r + 0.5)), (bw - 0.012, t, rh - 0.012), stone_a if (r + i) % 2 else stone_b, bevel=0.01)
			x += bw
	ring((w * 0.8, -t / 2 - 0.03, h * 0.45), 0.035, 0.008, IRON(), rot=(math.pi / 2, 0, 0))


def door_frame():
	"""Batente de pedra: dois umbrais nas pontas da aresta e a verga em cima."""
	jamb_w, depth = 0.12, 0.16
	h = WALL_HEIGHT + 0.04
	for sx in (-1, 1):
		box((sx * 0.5, 0, h / 2), (jamb_w, depth, h), STONE(), bevel=0.012)
		box((sx * 0.5, 0, 0.03), (jamb_w + 0.04, depth + 0.04, 0.06), STONE_DARK(), bevel=0.008)
	box((0, 0, h - 0.05), (1.0 + jamb_w, depth, 0.1), STONE(), bevel=0.012)
	box((0, 0, h - 0.05), (0.16, depth + 0.02, 0.12), STONE_DARK(), bevel=0.01)  # pedra de fecho


STONE = lambda: mat("stone", srgb("8c8780"), 0.95)
STONE_DARK = lambda: mat("stone_dark", srgb("5e5a55"), 0.95)
PLANK = lambda: mat("plank", srgb("8a5e36"), 0.8)

DOORS = {"door": door, "secret_door": secret_door, "door_frame": door_frame}


def run(only=None, do_export=True, textures=True):
	built = build_all(DOORS, SCENE, OUT_DIR, only, do_export, spacing=0.4)
	if textures and do_export:
		bake_all()
	return built
