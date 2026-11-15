"""Rigs the static jumpsuit character (jumpsuit_low_poly.glb) for TECTICA.

The source model has no skeleton. This script, run by Blender in the
background, builds a 3ds-Max-biped-named skeleton (the names model_skin.gd
already maps), places the joints from measurements of the meshes, binds the
meshes with automatic weights, straightens the arms into a T-pose (the rest
pose model_skin.gd expects: palms down), turns the character to face forward,
scales it to 1.8 m and exports a GLB.

  blender -b -P tools/rig_jumpsuit.py -- <in.glb> <out.glb> [max_texture_px]
"""
import sys
import math
import bpy
import bmesh
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = args[0], args[1]
MAX_TEX = int(args[2]) if len(args) > 2 else 1024
HEIGHT = 1.8

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scene = bpy.context.scene
meshes = [o for o in scene.objects if o.type == 'MESH']

# --- flatten the hierarchy: every mesh keeps its world transform, empties go ---
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in list(scene.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o)
for o in meshes:
    o.data = o.data.copy() if o.data.users > 1 else o.data
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)

def verts(objs):
    return [v.co.copy() for o in objs for v in o.data.vertices]

def find(prefix):
    return [o for o in meshes if o.name.startswith(prefix)]

body, suit, boots, headset = find("Genesis8Male"), find("Low Poly Jumpsuit"), find("Boots"), find("Low Poly Headset")
allv = verts(meshes)
zmin = min(v.z for v in allv)
zmax = max(v.z for v in allv)
scale = HEIGHT / (zmax - zmin)
headv = [v for v in verts(body) if v.z > zmin + 0.85 * (zmax - zmin)]
cx = sum(v.x for v in headv) / len(headv)
cy = sum(v.y for v in headv) / len(headv)
# feet on the ground, head over the origin, 1.8 m tall, facing -Y (Blender front,
# which the glTF exporter turns into +Z: the way model_skin.gd expects)
xf = Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(scale, 4) @ Matrix.Translation((-cx, -cy, -zmin))
for o in meshes:
    o.data.transform(xf)

H = HEIGHT

def band(vs, z0, z1):
    return [v for v in vs if z0 * H <= v.z <= z1 * H]

def centroid(vs):
    return sum(vs, Vector()) / len(vs)

bodyv, suitv, bootv = verts(body), verts(suit), verts(boots)
side_of = {"L": 1.0, "R": -1.0}   # facing -Y, the character's left is +X

J = {}
# hands (bare skin of the body mesh, below the hips): wrist = top of the hand, tip = bottom
for s, sg in side_of.items():
    hand = [v for v in bodyv if v.z < 0.62 * H and v.x * sg > 0]
    top = max(v.z for v in hand)
    bot = min(v.z for v in hand)
    J[s + "wrist"] = centroid([v for v in hand if v.z > top - 0.25 * (top - bot)])
    J[s + "tip"] = centroid([v for v in hand if v.z < bot + 0.3 * (top - bot)])
    # feet: the boots below ankle height; ankle above the heel half, toe at the front
    foot = [v for v in bootv if v.x * sg > 0]
    ftop = max(v.z for v in foot)
    J[s + "ankle"] = centroid([v for v in foot if v.z > ftop * 0.55])
    toe = [v for v in foot if v.z < ftop * 0.35]
    J[s + "toe"] = min(toe, key=lambda v: v.y)   # front is -Y
    J[s + "toe"] = Vector((J[s + "ankle"].x, J[s + "toe"].y, 0.03))

# shoulders: the widest point of the suit just under the neck, pulled in to the joint
for s, sg in side_of.items():
    sh = [v for v in band(suitv, 0.80, 0.83) if v.x * sg > 0]
    outer = max(sh, key=lambda v: v.x * sg)
    J[s + "shoulder"] = Vector((outer.x - sg * 0.055, centroid(sh).y, 0.815 * H))
    # elbow: the sleeve half-way down, at its centre
    mid_z = (J[s + "shoulder"].z + J[s + "wrist"].z) * 0.5
    arm = [v for v in suitv if abs(v.z - mid_z) < 0.03 * H and v.x * sg > abs(J[s + "shoulder"].x) * 0.85]
    J[s + "elbow"] = centroid(arm) if arm else (J[s + "shoulder"] + J[s + "wrist"]) * 0.5
    # hip joint and knee: centres of the leg cross-sections
    knee = [v for v in band(suitv, 0.27, 0.30) if v.x * sg > 0]
    J[s + "knee"] = centroid(knee)
    J[s + "hip"] = Vector((sg * 0.09, 0.0, 0.52 * H))

# spine and head down the middle of the body
def mid(z):
    b = [v for v in suitv if abs(v.z - z * H) < 0.02 * H and abs(v.x) < 0.15]
    c = centroid(b) if b else Vector((0, 0, z * H))
    return Vector((0.0, c.y, z * H))

J["pelvis"] = mid(0.555)
J["spine"] = mid(0.61)
J["spine1"] = mid(0.71)
J["neck"] = mid(0.835)
J["head"] = Vector((0.0, J["neck"].y, 0.875 * H))
J["headtop"] = Vector((0.0, J["neck"].y, H))
for k in ("hip",):
    for s in side_of:
        J[s + k].y = J["pelvis"].y
for k, v in sorted(J.items()):
    print("JOINT %-10s %s" % (k, tuple(round(c, 3) for c in v)))

# --- skeleton (biped names: model_skin.gd maps them) ---
arm_data = bpy.data.armatures.new("Armature")
rig = bpy.data.objects.new("Armature", arm_data)
scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None, deform=True):
    b = eb.new(name)
    b.head, b.tail = head, tail
    if (tail - head).length < 1e-4:
        b.tail = head + Vector((0, 0, 0.05))
    b.parent = eb[parent] if parent else None
    b.use_connect = False
    b.use_deform = deform
    return b

bone("bip", Vector((0, 0, 0)), Vector((0, 0, 0.1)), deform=False)
bone("bip Pelvis", J["pelvis"] - Vector((0, 0, 0.08)), J["pelvis"], "bip")
bone("bip Spine", J["pelvis"], J["spine1"], "bip Pelvis")
bone("bip Spine1", J["spine1"], J["neck"], "bip Spine")
bone("bip Neck", J["neck"], J["head"], "bip Spine1")
bone("bip Head", J["head"], J["headtop"], "bip Neck")
bone("bip HeadNub", J["headtop"], J["headtop"] + Vector((0, 0, 0.05)), "bip Head", deform=False)
for s in side_of:
    bone("bip %s Clavicle" % s, J["neck"] - Vector((0, 0, 0.03)), J[s + "shoulder"], "bip Spine1")
    bone("bip %s UpperArm" % s, J[s + "shoulder"], J[s + "elbow"], "bip %s Clavicle" % s)
    bone("bip %s Forearm" % s, J[s + "elbow"], J[s + "wrist"], "bip %s UpperArm" % s)
    bone("bip %s Hand" % s, J[s + "wrist"], J[s + "tip"], "bip %s Forearm" % s)
    bone("bip %s HandNub" % s, J[s + "tip"], J[s + "tip"] + (J[s + "tip"] - J[s + "wrist"]).normalized() * 0.03, "bip %s Hand" % s, deform=False)
    bone("bip %s Thigh" % s, J[s + "hip"], J[s + "knee"], "bip Pelvis")
    bone("bip %s Calf" % s, J[s + "knee"], J[s + "ankle"], "bip %s Thigh" % s)
    bone("bip %s Foot" % s, J[s + "ankle"], J[s + "toe"], "bip %s Calf" % s)
    bone("bip %s Toe0" % s, J[s + "toe"], J[s + "toe"] + Vector((0, -0.05, 0)), "bip %s Foot" % s, deform=False)
bpy.ops.object.mode_set(mode='OBJECT')

# --- bind: automatic (bone heat) weights for the body, suit and boots; the thin
# armour plates (DETAILS) copy the suit's weights under them, since bone heat
# leaves loose plates behind; the headset rides on the head alone ---
details = find("DETAILS")
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    if o not in headset and o not in details:
        o.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
for o in details:
    o.parent = rig
    dt = o.modifiers.new("Weights", 'DATA_TRANSFER')
    dt.object = suit[0]
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.datalayout_transfer(modifier=dt.name)
    bpy.ops.object.modifier_apply(modifier=dt.name)
    m = o.modifiers.new("Armature", 'ARMATURE')
    m.object = rig
for o in headset:
    o.parent = rig
    vg = o.vertex_groups.new(name="bip Head")
    vg.add([v.index for v in o.data.vertices], 1.0, 'REPLACE')
    m = o.modifiers.new("Armature", 'ARMATURE')
    m.object = rig
for o in meshes:
    print("WEIGHTS %s groups=%d" % (o.name, len(o.vertex_groups)))

# --- T-pose: arms straight out to the sides, then make that the rest pose ---
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
for s, sg in side_of.items():
    for name in ("bip %s UpperArm", "bip %s Forearm", "bip %s Hand"):
        pb = rig.pose.bones[name % s]
        bpy.context.view_layer.update()
        cur = (pb.tail - pb.head).normalized()            # armature space, current pose
        want = Vector((sg, 0.0, 0.0))
        rot = cur.rotation_difference(want)
        # express the world-space turn in the bone's own frame
        m = pb.matrix.copy()
        loc = m.translation.copy()
        m = Matrix.Translation(loc) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ m
        pb.matrix = m
        bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for m in o.modifiers:
        if m.type == 'ARMATURE':
            bpy.ops.object.modifier_apply(modifier=m.name)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    m = o.modifiers.new("Armature", 'ARMATURE')
    m.object = rig

# --- smaller textures: the source carries several 4K maps ---
for img in bpy.data.images:
    if img.size[0] > MAX_TEX:
        f = MAX_TEX / img.size[0]
        img.scale(MAX_TEX, max(1, int(img.size[1] * f)))
        img.pack()

bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=False,
                          export_animations=False, export_skins=True)
print("EXPORTED", DST)
