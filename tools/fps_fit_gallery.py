"""Make a review gallery/contact sheets from Godot's FPS arm captures."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw

out = Path(sys.argv[1]).resolve()
ids = ["hk33", "aug_a1", "scar_h", "as_val", "uar10", "l96a1", "m700", "mosin", "marlin",
       "mgp7", "gepard", "p90", "g17", "zc57", "vp9", "knife_combat", "karambit", "butterfly"]
states = ["idle", "ads", "inspect", "reload_mag", "reload_action", "cycle", "sprint"]
for state in states:
    files = [(gun, out / f"{gun}_{state}.png") for gun in ids if (out / f"{gun}_{state}.png").exists()]
    if not files:
        continue
    sheet = Image.new("RGB", (640 * 3, 390 * ((len(files) + 2) // 3)), "#111923")
    draw = ImageDraw.Draw(sheet)
    for i, (gun, path) in enumerate(files):
        x, y = i % 3 * 640, i // 3 * 390
        with Image.open(path) as im:
            im.thumbnail((640, 360))
            sheet.paste(im.convert("RGB"), (x, y + 30))
        draw.text((x + 12, y + 8), gun.upper() + " / " + state.upper(), fill="white")
    sheet.save(out / f"all_{state}.jpg", quality=90)

cards = "\n".join(f'<section data-gun="{gun}"><h2>{gun.upper()}</h2>' + "".join(
    f'<figure><a href="{gun}_{state}.png"><img loading="lazy" src="{gun}_{state}.png"></a><figcaption>{state.replace("_", " ")}</figcaption></figure>'
    for state in states if (out / f"{gun}_{state}.png").exists()) + '</section>' for gun in ids)
(out / "index.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>TECTICA FPS arm fit</title>
<style>body{margin:0;background:#0d1219;color:#e7eef7;font:16px system-ui}header{padding:24px;position:sticky;top:0;background:#101a26;z-index:1}h1{margin:0 0 8px}select{padding:8px}main{padding:16px}section{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:32px}h2{width:100%}figure{margin:0;width:min(600px,100%)}img{width:100%;border-radius:8px}figcaption{padding:8px;color:#9bc5ed}a{color:#9bc5ed}</style>
<header><h1>TECTICA · supplied FPS arms</h1><p>Godot Forward+ captures at the rig's FPS eye transform. Click a frame for full size.</p>
<label>Weapon <select id="gun"><option value="all">All weapons</option>''' + "".join(f'<option>{g}</option>' for g in ids) + '''</select></label></header><main>''' + cards + '''</main><script>document.querySelector('select').onchange=e=>document.querySelectorAll('section').forEach(s=>s.hidden=e.target.value!=='all'&&s.dataset.gun!==e.target.value);</script></html>''', encoding="utf-8")
print(out / "index.html")
