"""Cut the game's weapon sounds out of real CC0 recordings.

Gunshots: The Free Firearm Sound Library (Still North Media, CC0, via OpenGameArt). Each variant is one shot from a
close ("near") recording, for the punch, layered with the same gun's shot from a distance ("mid") for the outdoor
tail, then shaped (fade, gentle saturation) and normalised. Suppressed shots are close shots filtered and cut short.
Reload foley: "Gun reload sounds" (Joaken, CC0, via OpenGameArt), split at its clicks.

  python build_sfx.py <firearm library dir> <reload dir> <out dir>
"""
import os
import subprocess
import sys

import numpy as np

RATE = 48000
OUT_RATE = 44100

lib, reload_dir, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def onsets(x, min_gap=0.5, floor_db=-14.0):
    hop = int(RATE * 0.002)
    env = np.abs(x[: len(x) // hop * hop]).reshape(-1, hop).max(axis=1)
    db = 20 * np.log10(env + 1e-9)
    top = db.max()
    found, last = [], -1e9
    for i in range(1, len(db)):
        t = i * hop / RATE
        if db[i] > top + floor_db and db[i] - db[max(0, i - 3)] > 15 and t - last > min_gap:
            found.append(t)
            last = t
    return found


_cache = {}


def shot(rel, k):
    """Shot k of a recording, from 3 ms before its onset to the end of the file."""
    if rel not in _cache:
        x = load(os.path.join(lib, rel))
        _cache[rel] = (x, onsets(x))
    x, on = _cache[rel]
    s = max(0, int((on[k % len(on)] - 0.003) * RATE))
    return x[s:]


def fit(x, n):
    y = np.zeros(n, dtype=np.float32)
    y[: min(n, len(x))] = x[:n]
    return y


def one_pole_lp(x, hz):
    a = np.exp(-2 * np.pi * hz / RATE)
    from scipy.signal import lfilter
    return lfilter([1 - a], [1, -a], x).astype(np.float32)


def highpass(x, hz):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(2, hz, "highpass", fs=RATE, output="sos"), x).astype(np.float32)


def lowpass(x, hz):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(4, hz, "lowpass", fs=RATE, output="sos"), x).astype(np.float32)


def shape(x, length, fade_from=0.55, drive=2.2, peak_db=-1.0):
    n = int(length * RATE)
    y = fit(x, n)
    f0 = int(n * fade_from)
    y[f0:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n - f0))).astype(np.float32)
    y = highpass(y, 35.0)
    y /= max(1e-6, np.abs(y).max())
    y = np.tanh(drive * y) / np.tanh(drive)   # gentle saturation: a fuller body under the same peak
    return y * (10 ** (peak_db / 20.0))


def write(name, y):
    path = os.path.join(out, name + ".ogg")
    raw = (np.clip(y, -1, 1).astype(np.float32)).tobytes()
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-ar", str(OUT_RATE), "-c:a", "libvorbis", "-q:a", "6", path], input=raw, check=True)
    print("  %-22s %.2fs" % (name + ".ogg", len(y) / RATE))


# class -> [(near recording, shot index, mid recording for the tail, tail gain)], length, drive
SHOTS = {
    "shot_pistol": ([("Walther PPQ/X_39P.wav", 0, "Walther PPQ/X_31P.wav", 0.35),
                     ("Walther PPQ/X_39P.wav", 1, "Walther PPQ/X_31P.wav", 0.35),
                     ("Walther PPQ/X_39P.wav", 2, "Walther PPQ/X_31P.wav", 0.35),
                     ("1911/A_42P.wav", 0, "1911/A_34P.wav", 0.35)], 0.75, 2.4),
    "shot_smg": ([("Carl Gustav M45/G_31P.wav", 0, "Carl Gustav M45/G_20P.wav", 0.3),
                  ("Carl Gustav M45/G_31P.wav", 1, "Carl Gustav M45/G_20P.wav", 0.3),
                  ("Carl Gustav M45/G_31P.wav", 2, "Carl Gustav M45/G_20P.wav", 0.3),
                  ("PPSh/P_30P.wav", 0, "PPSh/P_16P.wav", 0.3),
                  ("PPSh/P_30P.wav", 2, "PPSh/P_16P.wav", 0.3)], 0.6, 2.4),
    "shot_rifle": ([("AR-15/D_32P.wav", 0, "AR-15/D_24P.wav", 0.4),
                    ("AR-15/D_32P.wav", 1, "AR-15/D_24P.wav", 0.4),
                    ("Savage 10 .300 Blackout/T_27P.wav", 0, "AR-15/D_24P.wav", 0.4),
                    ("Savage 10 .300 Blackout/T_27P.wav", 1, "AR-15/D_24P.wav", 0.4)], 0.8, 2.6),
    "shot_loud": ([("SKS/U_14P.wav", 0, "SKS/U_19P.wav", 0.45),
                   ("SKS/U_14P.wav", 1, "SKS/U_19P.wav", 0.45),
                   ("SKS/U_14P.wav", 2, "SKS/U_19P.wav", 0.45),
                   ("SKS/U_14P.wav", 3, "SKS/U_19P.wav", 0.45)], 0.9, 2.6),
    "shot_ak": ([("AK-47/C_28P.wav", 0, "AK-47/C_31P.wav", 0.45),
                 ("AK-47/C_28P.wav", 1, "AK-47/C_31P.wav", 0.45),
                 ("AK-47/C_28P.wav", 2, "AK-47/C_31P.wav", 0.45),
                 ("AK-47/C_28P.wav", 3, "AK-47/C_31P.wav", 0.45)], 0.85, 2.6),
    "shot_sniper": ([("Mosin Nagant/M_21P.wav", 0, "Mosin Nagant/M_26P.wav", 0.6),
                     ("Mosin Nagant/M_21P.wav", 1, "Mosin Nagant/M_26P.wav", 0.6),
                     ("Mosin Nagant/M_21P.wav", 2, "Mosin Nagant/M_26P.wav", 0.6),
                     ("Tikka/W_29P.wav", 0, "Tikka/W_24P.wav", 0.5)], 1.6, 2.8),
    "shot_lever": ([("Marlin 336/I_22P.wav", 0, "Marlin 336/I_17P.wav", 0.55),
                    ("Marlin 336/I_22P.wav", 1, "Marlin 336/I_17P.wav", 0.55),
                    ("Model 1894/L_23P.wav", 0, "Model 1894/L_17P.wav", 0.55)], 1.3, 2.8),
    "shot_shotgun": ([("Nova/O_21P.wav", 0, "Nova/O_17P.wav", 0.5),
                      ("Nova/O_21P.wav", 1, "Nova/O_17P.wav", 0.5),
                      ("Model 12/K_22P.wav", 0, "Model 12/K_17P.wav", 0.5),
                      ("CD/H_21P.wav", 0, "CD/H_16P.wav", 0.5)], 1.2, 2.8),
}

print("gunshots")
for name, (parts, length, drive) in SHOTS.items():
    for i, (near, k, mid, tail) in enumerate(parts):
        n = int(length * RATE)
        a = fit(shot(near, k), n)
        b = fit(shot(mid, 0), n)
        a /= max(1e-6, np.abs(a).max())
        b /= max(1e-6, np.abs(b).max())
        write("%s_%d" % (name, i), shape(a + tail * b, length, drive=drive))

# suppressed: the crack and blast filtered away, the mechanism's clack and a short puff left
print("suppressed")
for i, (near, k) in enumerate([("Walther PPQ/X_39P.wav", 0), ("Walther PPQ/X_39P.wav", 1),
                                ("Carl Gustav M45/G_31P.wav", 0), ("Carl Gustav M45/G_31P.wav", 1)]):
    n = int(0.32 * RATE)
    a = fit(shot(near, k), n)
    a /= max(1e-6, np.abs(a).max())
    body = lowpass(a, 1400.0)
    click = highpass(a, 3500.0) * 0.18
    env = np.exp(-np.arange(n) / RATE * 16.0).astype(np.float32)
    write("shot_suppressed_%d" % i, shape((body + click) * env, 0.32, fade_from=0.4, drive=1.6, peak_db=-6.0))

# reload foley: [file, from s, to s]
print("reload foley")
FOLEY = {
    "mag_out": [("assaultriflereload1_0.wav", 0.10, 0.46), ("gunreload1.wav", 0.02, 0.34)],
    "mag_in": [("assaultriflereload1_0.wav", 1.00, 1.19), ("gunreload1.wav", 0.64, 0.92)],
    "bolt": [("assaultriflereload1_0.wav", 1.185, 1.55), ("gunreload1.wav", 1.25, 1.578)],
}
for name, cuts in FOLEY.items():
    for i, (f, t0, t1) in enumerate(cuts):
        x = load(os.path.join(reload_dir, f))
        seg = x[int(t0 * RATE): int(t1 * RATE)].copy()
        fade = min(len(seg) // 4, int(0.04 * RATE))
        seg[:int(0.003 * RATE)] *= np.linspace(0, 1, int(0.003 * RATE)).astype(np.float32)
        seg[-fade:] *= np.linspace(1, 0, fade).astype(np.float32)
        seg = highpass(seg, 80.0)
        seg /= max(1e-6, np.abs(seg).max())
        write("%s_%d" % (name, i), seg * 10 ** (-3.0 / 20))
