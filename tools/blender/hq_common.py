# Funções comuns aos scripts do Blender (materiais, primitivos, montagem e
# exportação .glb). Carregado pelos build_*.py com exec(..., globals()).
#
# Convenções: Z para cima, frente da peça para -Y (vira +Z no Godot), apoio
# em z = 0, 1 unidade = 1 quadrado do tabuleiro.

import math
import os

import bpy
from mathutils import Vector

PROJECT = os.environ.get("HQ_PROJECT", "/Users/mariotrazzigmail.com/Documents/GitHub/heros-quest-simulator")

# ---------------------------------------------------------------- materiais

_mats = {}


def mat(name, color, rough=0.7, metal=0.0, emit=None):
	key = "hq_" + name
	if key in _mats:
		return _mats[key]
	m = bpy.data.materials.get(key) or bpy.data.materials.new(key)
	m.use_nodes = True
	bsdf = m.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	if emit:
		bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
		bsdf.inputs["Emission Strength"].default_value = 3.0
	m.diffuse_color = (*color, 1.0)
	_mats[key] = m
	return m


def srgb(h):
	"""Cor hex em sRGB → linear (o Principled trabalha em linear)."""
	h = h.lstrip("#")
	c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
	return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


SKIN = lambda: mat("skin", srgb("e0a47a"), 0.6)
STEEL = lambda: mat("steel", srgb("b8bcc4"), 0.3, 0.9)
IRON = lambda: mat("iron", srgb("4a4d55"), 0.4, 0.8)
GOLD = lambda: mat("gold", srgb("d9a83a"), 0.3, 1.0)
LEATHER = lambda: mat("leather", srgb("6b4423"), 0.8)
WOOD = lambda: mat("wood", srgb("7a5230"), 0.8)
BLACK = lambda: mat("black", srgb("141414"), 0.5)
WHITE = lambda: mat("white", srgb("f2efe6"), 0.6)

# ---------------------------------------------------------------- primitivos

_parts = []


def _done(obj, m, smooth=True):
	if m is not None:
		obj.data.materials.append(m)
	if smooth:
		for p in obj.data.polygons:
			p.use_smooth = True
	_parts.append(obj)
	return obj


def ball(center, r, m, sx=1.0, sy=1.0, sz=1.0, seg=16):
	bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=r, location=center)
	o = bpy.context.active_object
	o.scale = (sx, sy, sz)
	return _done(o, m)


def box(center, size, m, rot=(0, 0, 0), bevel=0.0):
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=center, rotation=rot)
	o = bpy.context.active_object
	o.scale = size
	if bevel > 0:
		bpy.ops.object.transform_apply(scale=True, location=False, rotation=False)
		mod = o.modifiers.new("bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
	return _done(o, m, smooth=False)


def _orient(o, a, b):
	a, b = Vector(a), Vector(b)
	d = b - a
	o.location = (a + b) / 2
	o.rotation_mode = "QUATERNION"
	o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
	return d.length


def limb(a, b, r, m, r2=None, seg=12):
	"""Cilindro (ou tronco de cone) ligando os pontos a e b."""
	d = (Vector(b) - Vector(a)).length
	bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r, radius2=r if r2 is None else r2, depth=d)
	o = bpy.context.active_object
	_orient(o, a, b)
	return _done(o, m)


def cone(a, b, r, m, seg=12):
	return limb(a, b, r, m, r2=0.0, seg=seg)


def ring(center, r, thick, m, rot=(0, 0, 0)):
	bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=thick, major_segments=20,
		minor_segments=6, location=center, rotation=rot)
	return _done(bpy.context.active_object, m)


def mirror(fn, *args, **kw):
	"""Chama fn duas vezes, espelhando em X os pontos (tuplas de 3)."""
	fn(*args, **kw)
	flip = lambda v: (-v[0], v[1], v[2]) if isinstance(v, tuple) and len(v) == 3 else v
	fn(*[flip(a) for a in args], **{k: flip(v) for k, v in kw.items()})



# ---------------------------------------------------------------- montagem

def fresh_scene(name):
	old = bpy.data.scenes.get(name)
	if old:
		for o in list(old.objects):
			bpy.data.objects.remove(o, do_unlink=True)
		bpy.data.scenes.remove(old)
	bpy.data.orphans_purge(do_recursive=True)                       # malhas das rodadas anteriores
	scene = bpy.data.scenes.new(name)
	bpy.context.window.scene = scene
	return scene


def build_one(fid, builder):
	"""Roda o builder e junta as peças num único objeto com nome fid."""
	_parts.clear()
	builder()
	bpy.ops.object.select_all(action="DESELECT")
	for o in _parts:
		o.select_set(True)
	bpy.context.view_layer.objects.active = _parts[0]
	bpy.ops.object.convert(target="MESH")                               # aplica bevels
	bpy.ops.object.join()
	obj = bpy.context.active_object
	obj.name = fid
	obj.data.name = fid
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
	return obj


def export(obj, path):
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
		export_apply=True, export_yup=True, export_materials="EXPORT", use_active_scene=True)


def build_all(builders, scene_name, out_dir, only=None, do_export=True, spacing=0.8):
	"""Monta cada peça, exporta <out_dir>/<id>.glb e enfileira em X para a prévia."""
	fresh_scene(scene_name)
	bpy.context.scene.cursor.location = (0, 0, 0)
	os.makedirs(out_dir, exist_ok=True)
	built = []
	x = 0.0
	for fid, builder in builders.items():
		if only and fid not in only:
			continue
		obj = build_one(fid, builder)
		if do_export:
			export(obj, os.path.join(out_dir, fid + ".glb"))
		half = obj.dimensions.x / 2.0
		obj.location.x = x + half
		x += half * 2.0 + spacing
		built.append(fid)
	return built



def preview(path, elevation=55.0, res=(1800, 700)):
	"""Renderiza a cena atual (peças enfileiradas em X) numa imagem de prévia."""
	sc = bpy.context.scene
	objs = [o for o in sc.objects if o.type == "MESH"]
	x0 = min(o.location.x - o.dimensions.x / 2 for o in objs)
	x1 = max(o.location.x + o.dimensions.x / 2 for o in objs)
	cam = bpy.data.objects.new("prev_cam", bpy.data.cameras.new("prev_cam"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	cam.data.type = "ORTHO"
	y0 = min(o.location.y - o.dimensions.y / 2 for o in objs)
	y1 = max(o.location.y + o.dimensions.y / 2 for o in objs)
	cam.data.ortho_scale = max(x1 - x0, (y1 - y0 + 1.0) * res[0] / res[1]) * 1.05
	a = math.radians(elevation)
	cam.location = ((x0 + x1) / 2, (y0 + y1) / 2 - 20 * math.cos(a), 20 * math.sin(a) + 0.3)
	cam.rotation_euler = (math.pi / 2 - a, 0, 0)
	for name, rot, e in (("key", (50, 0, -30), 3.5), ("fill", (60, 0, 140), 1.2)):
		light = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
		light.data.energy = e
		light.rotation_euler = [math.radians(v) for v in rot]
		sc.collection.objects.link(light)
	world = bpy.data.worlds.get("prev_world") or bpy.data.worlds.new("prev_world")
	sc.world = world
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.25, 0.25, 0.28, 1)
	sc.render.resolution_x, sc.render.resolution_y = res
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)
