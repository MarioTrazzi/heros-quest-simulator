# Ajusta uma miniatura gerada por IA (GLB do Higgsfield/Tripo) às convenções
# de assets/models/figures: Z para cima, frente para -Y (vira +Z no Godot),
# pés em z = 0, centrada nos pés, na altura pedida, poucas faces e textura
# de até 1024 px. Roda o Blender em segundo plano (não toca no arquivo aberto):
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       --python-exit-code 1 -P tools/blender/fit_ai_figure.py -- \
#       entrada.glb saida.glb ALTURA [--faces 12000] [--turn 0|90|180|270] [--preview x.png]
#
# O Tripo entrega a figura olhando para +X: use --turn -90.
# --measure entrada.glb (sem saída) só mede a altura de um .glb existente.

import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name, default):
	if name in argv:
		i = argv.index(name)
		val = argv[i + 1]
		del argv[i:i + 2]
		return val
	return default


faces = int(opt("--faces", "12000"))
turn = float(opt("--turn", "0"))
preview = opt("--preview", "")
measure = "--measure" in argv
if measure:
	argv.remove("--measure")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objs):
	pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
	lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
	hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
	return lo, hi


if measure:
	lo, hi = bounds(meshes)
	print("MEDIDA", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi))
	sys.exit(0)

out, height = argv[1], float(argv[2])

# Uma malha só, sem pais nem transformações pendentes.
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
	bpy.ops.object.join()
fig = bpy.context.view_layer.objects.active
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for o in list(bpy.context.scene.objects):
	if o != fig:
		bpy.data.objects.remove(o, do_unlink=True)
fig.name = "figure"
fig.rotation_mode = "XYZ"  # o importador do glTF deixa em quaternion
fig.rotation_euler.z += math.radians(turn)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Escala pela altura e apoia os pés em z = 0, centrando pelos pés (a arma
# não puxa o centro para o lado).
lo, hi = bounds([fig])
s = height / (hi.z - lo.z)
fig.scale = (s, s, s)
bpy.ops.object.transform_apply(scale=True)
vs = [v.co for v in fig.data.vertices]
zmin = min(v.z for v in vs)
feet = [v for v in vs if v.z < zmin + height * 0.12]
cx = (min(v.x for v in feet) + max(v.x for v in feet)) / 2
cy = (min(v.y for v in feet) + max(v.y for v in feet)) / 2
for v in fig.data.vertices:
	v.co -= Vector((cx, cy, zmin))

if len(fig.data.polygons) > faces:
	mod = fig.modifiers.new("decimate", "DECIMATE")
	mod.ratio = faces / len(fig.data.polygons)
	bpy.ops.object.modifier_apply(modifier=mod.name)

for img in bpy.data.images:
	w, h = img.size
	if max(w, h) > 1024:
		k = 1024 / max(w, h)
		img.scale(int(w * k), int(h * k))
		img.pack()

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False,
	export_apply=True, export_yup=True, export_materials="EXPORT", export_image_format="JPEG")
print("FIGURA", out, "faces", len(fig.data.polygons), "altura", round(height, 3))

if preview:
	scene = bpy.context.scene
	scene.render.engine = "BLENDER_EEVEE"
	scene.render.resolution_x, scene.render.resolution_y = 900, 600
	scene.render.filepath = preview
	world = bpy.data.worlds.new("w")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
	scene.world = world
	sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
	scene.collection.objects.link(sun)
	# Três cópias lado a lado: frente (-Y), perfil e costas.
	for i, rz in enumerate((0, 90, 180)):
		c = fig.copy()
		c.rotation_mode = "XYZ"
		c.location.x = (i - 1) * height * 0.9
		c.rotation_euler.z = math.radians(rz)
		scene.collection.objects.link(c)
	fig.hide_render = True
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = height * 3.0
	cam.location = (0, -5, height / 2)
	cam.rotation_euler = (math.radians(90), 0, 0)
	scene.collection.objects.link(cam)
	scene.camera = cam
	bpy.ops.render.render(write_still=True)
