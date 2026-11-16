"""Inspect/export the user's FPS arms. Run with Blender --background --python.

Arguments after --: source.blend output.glb [inspect]
"""
import bpy
import sys
from mathutils import Matrix, Vector

src, dst, *mode = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=src)
for obj in bpy.data.objects:
    print("OBJECT", obj.name, obj.type, "dimensions", tuple(obj.dimensions), "matrix", obj.matrix_world)
    if obj.type == "ARMATURE":
        for bone in obj.data.bones:
            print("BONE", bone.name, "parent", bone.parent.name if bone.parent else None,
                  "head", tuple(bone.head_local), "tail", tuple(bone.tail_local), "deform", bone.use_deform)
        for pb in obj.pose.bones:
            if pb.constraints:
                print("CONSTRAINTS", pb.name, [(c.name, c.type) for c in pb.constraints])
    if obj.type == "MESH":
        print("VERTS", len(obj.data.vertices), "GROUPS", [(g.index, g.name) for g in obj.vertex_groups],
              "MODS", [(m.name, m.type) for m in obj.modifiers])
        print("MATERIALS", [m.name if m else None for m in obj.data.materials])
if "inspect" not in mode:
    arm = bpy.data.objects["Armature"]
    mesh = bpy.data.objects["Mid Poly Arm"]
    # Discard authoring controls/camera; Godot drives the deform skeleton directly.
    for obj in list(bpy.data.objects):
        if obj not in (arm, mesh):
            bpy.data.objects.remove(obj, do_unlink=True)
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.matrix_basis = Matrix.Identity(4)
    # Preserve the original skin; consolidate the tiny elbow bridge into the
    # forearm so runtime IK has exactly two rigid-length limb segments.
    for side in ("L", "R"):
        old = mesh.vertex_groups.get("Elbow." + side)
        dest = mesh.vertex_groups["Forearm." + side]
        if old:
            for v in mesh.data.vertices:
                amount = next((g.weight for g in v.groups if g.group == old.index), 0)
                if amount:
                    dest.add([v.index], amount, "ADD")
            mesh.vertex_groups.remove(old)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in arm.data.edit_bones:
        bone.use_connect = False
    for side in ("L", "R"):
        elbow = arm.data.edit_bones["Elbow." + side]
        fore = arm.data.edit_bones["Forearm." + side]
        fore.parent = elbow.parent
        fore.head = elbow.head
        arm.data.edit_bones.remove(elbow)
    for bone in list(arm.data.edit_bones):
        if " IK." in bone.name:
            arm.data.edit_bones.remove(bone)
    bpy.ops.object.mode_set(mode="OBJECT")
    # Author used centimetres. Normalize to metres, and bring the unusually
    # long palm/fingers to an adult ~18 cm hand without stretching joints live.
    hand_scale = 0.82
    wrists = {s: arm.data.bones["Hand." + s].head_local.copy() for s in ("L", "R")}
    hand_names = {s: {"Hand." + s} | {b.name for b in arm.data.bones["Hand." + s].children_recursive}
                  for s in ("L", "R")}
    for v in mesh.data.vertices:
        for side in ("L", "R"):
            influence = sum(g.weight for g in v.groups if mesh.vertex_groups[g.group].name in hand_names[side])
            v.co += (v.co - wrists[side]) * ((hand_scale - 1) * min(1, influence))
    bpy.ops.object.mode_set(mode="EDIT")
    for side in ("L", "R"):
        for name in hand_names[side]:
            bone = arm.data.edit_bones[name]
            bone.head = wrists[side] + (bone.head - wrists[side]) * hand_scale
            bone.tail = wrists[side] + (bone.tail - wrists[side]) * hand_scale
    bpy.ops.object.mode_set(mode="OBJECT")
    valid = {b.name for b in arm.data.bones}
    for vg in list(mesh.vertex_groups):
        if vg.name not in valid:
            count = sum(any(g.group == vg.index and g.weight > 0.0001 for g in v.groups) for v in mesh.data.vertices)
            if count:
                print("REMOVED_LEGACY_GROUP", vg.name, count)
            mesh.vertex_groups.remove(vg)
    # Blend the elbow bridge across both limb bones. Assigning the entire
    # bridge to the forearm creates a hard diagonal fold when the elbow bends.
    for side in ("L", "R"):
        upper = arm.data.bones["Upper Arm." + side]
        lower = arm.data.bones["Forearm." + side]
        joint = lower.head_local
        tangent = ((joint-upper.head_local).normalized() + (lower.tail_local-joint).normalized()).normalized()
        vg_u = mesh.vertex_groups[upper.name]
        vg_l = mesh.vertex_groups[lower.name]
        for v in mesh.data.vertices:
            if (v.co-joint).length > 10.0:
                continue
            limb_weight = sum(g.weight for g in v.groups if g.group in (vg_u.index,vg_l.index))
            if limb_weight < 0.01:
                continue
            t = max(0.0,min(1.0,0.5+(v.co-joint).dot(tangent)/10.0))
            t = t*t*(3-2*t)
            vg_u.add([v.index],limb_weight*(1-t),"REPLACE")
            vg_l.add([v.index],limb_weight*t,"REPLACE")
    # Four normalized influences per vertex, no control-bone skinning.
    for v in mesh.data.vertices:
        weights = sorted([(g.group, g.weight) for g in v.groups if g.weight > 1e-5], key=lambda x: -x[1])[:4]
        if not weights:
            raise RuntimeError("Unweighted arm vertex %d" % v.index)
        total = sum(w for _, w in weights)
        for g in list(v.groups):
            mesh.vertex_groups[g.group].remove([v.index])
        for idx, w in weights:
            mesh.vertex_groups[idx].add([v.index], w / total, "REPLACE")
    # Scale data once: scaling both a parent armature and its child mesh
    # would apply the unit conversion twice to the geometry.
    mesh.data.transform(Matrix.Scale(0.0081, 4))
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in arm.data.edit_bones:
        bone.head *= 0.0081
        bone.tail *= 0.0081
    bpy.ops.object.mode_set(mode="OBJECT")
    for obj in (arm, mesh):
        obj.select_set(True)
    mat = bpy.data.materials.new("FPS arms skin")
    mat.diffuse_color = (0.52, 0.31, 0.20, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = mat.diffuse_color
    bsdf.inputs["Roughness"].default_value = 0.8
    mesh.data.materials.clear()
    mesh.data.materials.append(mat)
    arm.data.pose_position = "REST"
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=False,
                              export_skins=True, export_def_bones=True, use_selection=True)
    print("FPS_EXPORT", dst, "vertices", len(mesh.data.vertices), "bones", len(arm.data.bones))
