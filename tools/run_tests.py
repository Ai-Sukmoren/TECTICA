"""Runs every automated test in tests/ and prints a pass/fail summary.

    python tools/run_tests.py                 # all tests
    python tools/run_tests.py knife town      # only tests whose name contains a word

The Godot executable comes from the GODOT environment variable, or `godot` on
PATH. Tests run headless, except the few that need a real window (listed in
WINDOWED). Two-process multiplayer tests are started as a host + client pair.
Screenshot tools live in tests/previews/ and benchmarks in tests/perf/; they
are not part of this run.
"""
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT") or shutil.which("godot") or "godot"
TIMEOUT = 300

# tests that need a window (rendering) and the user args they take
WINDOWED = {
    "touch_test": ["--resolution", "1688x780", "--", "--touch"],
    "locomotion_stability_test": ["--resolution", "960x540"],
    "camera_motion_test": ["--resolution", "960x540"],
    "aim_stability_test": ["--resolution", "960x540", "--max-fps", "144"],
}
# host + client pairs: [host args, client args]
PAIRS = {
    "multiplayer_test": [["host", "coop"], ["client", "coop"]],
    "join_code_e2e": [["host"], ["client"]],
}


def run(name: str, extra: list) -> tuple:
    headless = name not in WINDOWED
    cmd = [GODOT] + (["--headless"] if headless else []) + ["--path", str(ROOT), "-s", f"res://tests/{name}.gd"]
    cmd += WINDOWED.get(name, []) if not headless else (["--"] + extra if extra else [])
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, encoding="utf-8", errors="replace")
        text = out.stdout + out.stderr
        bad = out.returncode != 0 or "SCRIPT ERROR" in text or "Parse Error" in text
        return (not bad, text)
    except subprocess.TimeoutExpired:
        return (False, "timed out")


def run_pair(name: str) -> tuple:
    host_args, client_args = PAIRS[name]
    base = [GODOT, "--headless", "--path", str(ROOT), "-s", f"res://tests/{name}.gd", "--"]
    # the host's output goes to a file: an unread pipe fills up and stalls it
    log = open(ROOT / ".godot" / f"{name}_host.log", "w", encoding="utf-8", errors="replace")
    host = subprocess.Popen(base + host_args, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(7)
    try:
        client = subprocess.run(base + client_args, capture_output=True, text=True, timeout=90, encoding="utf-8", errors="replace")
        text = client.stdout + client.stderr
    except subprocess.TimeoutExpired:
        text = "client timed out"
    finally:
        time.sleep(3)
        host.kill()
        host.wait()
        log.close()
    ok = "FAIL" not in text and ("PASS" in text or "final hp=" in text) and "SCRIPT ERROR" not in text
    return (ok, text)


def main() -> int:
    words = sys.argv[1:]
    tests = sorted(p.stem for p in (ROOT / "tests").glob("*.gd"))
    if words:
        tests = [t for t in tests if any(w in t for w in words)]
    failed = []
    t0 = time.time()
    for name in tests:
        start = time.time()
        ok, text = run_pair(name) if name in PAIRS else run(name, [])
        print(f"  {'ok  ' if ok else 'FAIL'}  {name:32s} {time.time() - start:5.1f} s", flush=True)
        if not ok:
            failed.append(name)
            for line in text.splitlines():
                if "FAIL" in line or "ERROR" in line:
                    print("        " + line.strip()[:160])
    print(f"\n{len(tests) - len(failed)} / {len(tests)} passed in {time.time() - t0:.0f} s")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
