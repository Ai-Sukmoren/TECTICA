"""Fits the first-person hands to each gun's real surface.

    godot --headless --path . -s res://tools/probe_hand_contact.gd -- sweep.json
    python tools/fit_hand_contacts.py sweep.json

For every gun / attachment variant the probe exports the gun triangles, each palm
(centre and the way it faces) and the finger joints over a sweep of curl amounts,
all in weapon space. This script:
  1. raises the shooting hand to the highest hold where its fingers wrap the grip;
  2. slides each palm along the way it faces until its skin rests on the gun
     (a knife handle is seated in the fist instead);
  3. per finger, takes the smallest curl at which the finger's skin meets the gun.
It writes scripts/characters/fps_hand_contacts.gd, which FPSArmRig reads.
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "scripts/characters/fps_hand_contacts.gd"
FINGERS = ["Index", "Middle", "Ring", "Little", "Thumb"]
PRESS = 0.0015      # skin sinks this far into the gun: no visible air on faceted models
MAX_SHIFT = 0.045   # a larger palm move means the profile itself is wrong: report it
NEAR = 0.16         # only triangles this close to the palm can touch the hand
# A high, firm pistol-grip hold: each lower finger's knuckle sits this far behind
# the grip's front strap (it closes round the grip, not round the trigger guard or
# magwell above it, nor into air below). Straight-wrist stocks have no pistol grip.
WRAP = (0.015, 0.055)   # (max air before the grip, max grip depth) ahead of a knuckle
GRIP_HALF = 0.025       # half-width scanned: takes in the grip's side faces
FINGER_CLEAR = 0.01     # top of a finger above its bone centre line
STRAIGHT_WRIST = {"mosin", "marlin"}


def point_tri_dist(p, a, b, c):
    """Distance from each point (n,3) to the nearest of the triangles (m,3)."""
    ab, ac = b - a, c - a
    n = np.cross(ab, ac)
    nl = np.linalg.norm(n, axis=1)
    ok = nl > 1e-9
    a, b, c, ab, ac, n, nl = a[ok], b[ok], c[ok], ab[ok], ac[ok], n[ok], nl[ok]
    nh = n / nl[:, None]
    out = np.empty(len(p))
    for k, q in enumerate(p):
        ap = q - a
        dist = (ap * nh).sum(1)
        proj = ap - dist[:, None] * nh
        d00 = (ab * ab).sum(1); d01 = (ab * ac).sum(1); d11 = (ac * ac).sum(1)
        d20 = (proj * ab).sum(1); d21 = (proj * ac).sum(1)
        den = d00 * d11 - d01 * d01
        v = (d11 * d20 - d01 * d21) / den
        w = (d00 * d21 - d01 * d20) / den
        inside = (v >= 0) & (w >= 0) & (v + w <= 1)
        best = np.where(inside, np.abs(dist), np.inf)
        for e0, e1 in ((a, b), (b, c), (c, a)):
            e = e1 - e0
            t = np.clip(((q - e0) * e).sum(1) / (e * e).sum(1), 0, 1)
            best = np.minimum(best, np.linalg.norm(q - (e0 + t[:, None] * e), axis=1))
        out[k] = best.min() if len(best) else np.inf
    return out


def ray_hit(origin, direction, a, b, c):
    """Nearest positive hit distance of a ray against triangles (Moller-Trumbore)."""
    e1, e2 = b - a, c - a
    pv = np.cross(direction, e2)
    det = (e1 * pv).sum(1)
    ok = np.abs(det) > 1e-12
    inv = np.where(ok, 1.0 / np.where(ok, det, 1), 0)
    tv = origin - a
    u = (tv * pv).sum(1) * inv
    qv = np.cross(tv, e1)
    v = (direction * qv).sum(1) * inv
    t = (e2 * qv).sum(1) * inv
    hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
    return t[hit].min() if hit.any() else None


def finger_points(pts):
    """Skin-test points on the middle and distal phalanges. The first phalanx lies
    along the grip even when straight, so it says nothing about how far to wrap."""
    p = np.array(pts)
    samples = [p[1] + (p[2] - p[1]) * f for f in (0.5, 0.75)]
    samples += [p[2] + (p[3] - p[2]) * f for f in (0.0, 0.34, 0.67, 1.0)]
    return np.array(samples)


def closest_point(q, a, b, c):
    """Nearest surface point to q over the triangles, sampled on a fine barycentric grid
    of the few closest triangles (exact enough at millimetre scale)."""
    centre = (a + b + c) / 3
    order = np.argsort(np.linalg.norm(centre - q, axis=1))[:64]
    best, best_d = None, np.inf
    for i in order:
        d = point_tri_dist(q[None], a[i:i + 1], b[i:i + 1], c[i:i + 1])[0]
        if d < best_d:
            best_d, best = d, i
    if best is None:
        return None, np.inf
    g = np.linspace(0, 1, 41)
    u, v = np.meshgrid(g, g)
    keep = (u + v) <= 1
    pts = a[best] + np.outer(u[keep], b[best] - a[best]) + np.outer(v[keep], c[best] - a[best])
    k = np.argmin(np.linalg.norm(pts - q, axis=1))
    return pts[k], best_d


def surface_samples(faces, per=12, seed=0):
    rng = np.random.default_rng(seed)
    u = rng.random((len(faces), per, 2))
    flip = u.sum(2) > 1
    u[flip] = 1 - u[flip]
    a, b, c = faces[:, None, 0], faces[:, None, 1], faces[:, None, 2]
    return (a + u[..., :1] * (b - a) + u[..., 1:] * (c - a)).reshape(-1, 3)


def grip_run(base, pts):
    """At a finger knuckle's height, the solid the finger closes round: the unbroken
    run of material (grip sides, 5 mm bins) going forward from beside the knuckle.
    Returns (gap before it, its end) in metres ahead of the knuckle, or None."""
    row = pts[(np.abs(pts[:, 0]) < GRIP_HALF) & (np.abs(pts[:, 1] - base[1]) < 0.004)]
    ahead = base[2] - row[:, 2]                      # +: toward the muzzle
    ahead = ahead[(ahead > -0.01) & (ahead < 0.10)]
    if not len(ahead):
        return None
    bins = np.unique(np.floor((ahead + 0.01) / 0.005).astype(int))
    start = bins[0]
    end = start
    for b in bins[1:]:
        if b > end + 1:
            break
        end = b
    return start * 0.005 - 0.01, (end + 1) * 0.005 - 0.01


def wraps_grip(base, pts):
    """A finger wraps the grip when material starts beside its knuckle and is no deeper
    than a grip (a longer run is the trigger guard / magwell / receiver above it)."""
    run = grip_run(base, pts)
    return run is not None and run[0] <= WRAP[0] and run[1] <= WRAP[1]


def high_grip(gun, pts):
    """Weapon-space lift for the shooting hand: the highest hold at which the middle,
    ring and little fingers all wrap the grip's front strap (a high, firm grip)."""
    if gun["melee"] or gun["trigger"] is None or gun["model"] in STRAIGHT_WRIST:
        return np.zeros(3), ""
    bases = [np.array(gun["sweep"][0]["hands"][1][f][0]) for f in (1, 2, 3)]
    # Climb from below the grip; the first band where all three wrap is the grip.
    # Stop at its top: higher bands are receiver parts that only look grip-sized.
    # Single 2.5 mm steps can miss from surface-sampling noise, so a band ends only
    # after 5 mm with no full wrap.
    best, best_count, misses = None, -1, 0
    for dy in np.arange(-0.03, 0.06001, 0.0025):
        lift = np.array([0.0, dy, 0.0])
        count = sum(wraps_grip(b + lift, pts) for b in bases)
        if best_count == 3 and count < 3:
            misses += 1
            if misses > 2:
                break
            continue
        misses = 0
        if count >= best_count:
            best, best_count = dy, count
    if best_count < 3:
        return np.zeros(3), f"R no height wraps all three fingers (best {best_count}), kept"
    # Knuckle heights are bone centres: keep the finger's own thickness under the guard.
    return np.array([0.0, best - FINGER_CLEAR, 0.0]), ""


def fit(gun, skin):
    faces = np.array(gun["faces"]).reshape(-1, 3, 3)
    shifts, curls, notes = [], [], []
    grip, why = high_grip(gun, surface_samples(faces))
    if why:
        notes.append(why)
    elif np.abs(grip).max() > 0.002:
        notes.append(f"R high grip up {grip[1]*100:+.1f} cm")
    for side in range(2):
        label = "LR"[side]
        palm = np.array(gun["sides"][side]["palm"])
        normal = np.array(gun["sides"][side]["normal"])
        # Pistols: the support hand wraps the shooting hand, so it moves with it.
        # Knives: the left hand is free and the right palm follows the blade marker.
        if side == 0 and gun["pistol"]:
            shifts.append(grip.round(4).tolist())
        elif side == 0 and gun["melee"]:
            shifts.append([0.0, 0.0, 0.0])
        elif gun["melee"]:
            # Knife: the handle must sit in the fist, its surface on the palm skin.
            pts = faces.reshape(-1, 3)
            handle = pts[np.linalg.norm(pts - palm, axis=1) < 0.07]
            centre = handle.mean(0)
            axis = np.linalg.svd(handle - centre)[2][0]
            rel = handle - centre
            along = rel @ axis
            core = rel[np.abs(along) < 0.03]
            radius = np.median(np.linalg.norm(core - np.outer(core @ axis, axis), axis=1))
            depth = (centre - palm) @ normal
            move = depth - skin["palm"][side] - radius + PRESS
            shifts.append((normal * move).round(4).tolist())
            notes.append(f"R knife handle r {radius*100:.1f} cm, was {depth*100:.1f} cm deep")
        else:
            lift = grip if side == 1 else np.zeros(3)
            palm = palm + lift
            near = faces[np.linalg.norm(faces.mean(1) - palm, axis=1) < NEAR]
            back = 0.06
            t = ray_hit(palm - normal * back, normal, near[:, 0], near[:, 1], near[:, 2])
            if t is not None and t <= back + 0.12:
                direction, move = normal, (t - back) - skin["palm"][side] + PRESS
            else:
                # The palm's line misses the gun: settle on the nearest surface instead.
                q, d = closest_point(palm, near[:, 0], near[:, 1], near[:, 2])
                direction = (q - palm) / max(d, 1e-9)
                move = d - skin["palm"][side] + PRESS
                notes.append(f"{label} palm via nearest surface")
            if abs(move) > MAX_SHIFT:
                notes.append(f"{label} palm move {move*100:.1f} cm clamped")
                move = float(np.clip(move, -MAX_SHIFT, MAX_SHIFT))
            shifts.append((lift + direction * move).round(4).tolist())
        if side == 0 and (gun["pistol"] or gun["melee"]):
            curls.append([-1.0] * 5)
            continue
        shift = np.array(shifts[side])
        origin = np.array(gun["sides"][side]["palm"]) + shift
        near = faces[np.linalg.norm(faces.mean(1) - origin, axis=1) < NEAR]
        a, b, c = near[:, 0], near[:, 1], near[:, 2]
        radius = skin["finger"][side] - PRESS
        row = []
        for fi, finger in enumerate(FINGERS):
            if (side == 1 and finger == "Index" and not gun["melee"]) or (finger == "Thumb" and not gun["melee"]):
                # trigger fit owns the index; on guns the thumb keeps its authored lay
                # along the gun, on a knife it closes over the handle like the fingers
                row.append(-1.0)
                continue
            prev_s, prev_gap, found, straight = None, None, -1.0, False
            for step in gun["sweep"]:
                pts = finger_points(step["hands"][side][fi]) + shift
                gap = point_tri_dist(pts, a, b, c).min() - radius
                if gap <= 0:
                    if prev_gap is None:
                        straight = True
                        notes.append(f"{label} {finger}: touches while straight, kept")
                    else:
                        found = prev_s + (step["curl"] - prev_s) * prev_gap / (prev_gap - gap)
                    break
                prev_s, prev_gap = step["curl"], gap
            if found < 0 and not straight:
                notes.append(f"{label} {finger}: never touches")
            row.append(round(float(found), 3))
        curls.append(row)
    return {"shift": shifts, "curl": curls}, notes


def gd_value(entry):
    sh = ", ".join("Vector3(%.4f, %.4f, %.4f)" % tuple(s) for s in entry["shift"])
    cu = ", ".join("[" + ", ".join("%.3f" % c for c in row) + "]" for row in entry["curl"])
    return '{"shift": [%s], "curl": [%s]}' % (sh, cu)


def main():
    data = json.loads(Path(sys.argv[1]).read_text())
    skin = data["skin"]
    print("skin depth: palm %s cm, finger %s cm" % (
        [round(x * 100, 2) for x in skin["palm"]], [round(x * 100, 2) for x in skin["finger"]]))
    lines = ["extends RefCounted",
             "## Generated by tools/fit_hand_contacts.py. Do not edit by hand.",
             "## shift: palm offset in weapon space [L, R]; curl: [Index, Middle, Ring, Little, Thumb]",
             "## per hand, -1 keeps the hand-tuned profile amount.",
             "const DATA := {"]
    for key, gun in data["guns"].items():
        entry, notes = fit(gun, skin)
        lines.append('\t"%s": %s,' % (key, gd_value(entry)))
        print(f"{key:16s} shift L {np.round(np.array(entry['shift'][0])*100,1)} R {np.round(np.array(entry['shift'][1])*100,1)} cm"
              f"  curl L {entry['curl'][0]} R {entry['curl'][1]}" + ("  ! " + "; ".join(notes) if notes else ""))
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
