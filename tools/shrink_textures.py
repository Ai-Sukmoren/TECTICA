"""Re-exports a glTF/GLB with every texture scaled down to at most N pixels.

  blender -b -P tools/shrink_textures.py -- <in.glb> <out.glb> [max_px]
"""
import sys
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = args[0], args[1]
MAX = int(args[2]) if len(args) > 2 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for img in bpy.data.images:
    w, h = img.size
    if max(w, h) > MAX:
        f = MAX / max(w, h)
        img.scale(max(1, int(w * f)), max(1, int(h * f)))
        img.pack()
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', export_animations=False)
print("EXPORTED", DST)
