"""Screenshot CLI benchmark for macOS: snip vs screencapture, Peekaboo and python-mss.

Every round runs each tool once in shuffled order, so a load spike hits all tools alike, and each run is a
fresh process (what an agent pays per screenshot). Tools that aren't installed are skipped.

    python3 Benchmarks/bench.py                      # 20 rounds of screen, region and window
    python3 Benchmarks/bench.py --rounds 50 screen
    SNIP=.build/release/SnipCLI PEEKABOO=/path/to/peekaboo MSS_PYTHON=venv/bin/python python3 Benchmarks/bench.py

Window shots target the frontmost normal window from `snip windows` (or WINDOW=<id>).
"""
import argparse, os, random, shutil, statistics as st, subprocess, sys, tempfile, time

out = tempfile.mkdtemp(prefix="snip-bench-")
snip = os.environ.get("SNIP") or shutil.which("snip")
peekaboo = os.environ.get("PEEKABOO") or shutil.which("peekaboo")
mss_python = os.environ.get("MSS_PYTHON")
if not mss_python and subprocess.run([sys.executable, "-c", "import mss"], capture_output=True).returncode == 0:
    mss_python = sys.executable

region = (100, 100, 800, 600)
rs = ",".join(map(str, region))
window = os.environ.get("WINDOW")
if not window and snip:
    lines = subprocess.run([snip, "windows"], capture_output=True, text=True).stdout.splitlines()
    window = lines[0].split("\t")[0] if lines else None

mss_screen = f"import mss\nwith mss.MSS() as s: s.shot(mon=1, output='{out}/mss.png')"
mss_region = (f"import mss, mss.tools\nwith mss.MSS() as s:\n img = s.grab({{'left': {region[0]}, 'top': {region[1]}, "
              f"'width': {region[2]}, 'height': {region[3]}}})\n mss.tools.to_png(img.rgb, img.size, output='{out}/mss.png')")

def tools(scenario):
    t = {}
    if scenario == "screen":
        if snip: t["snip"] = [snip, "shot", "-o", f"{out}/snip.png"]
        t["screencapture"] = ["screencapture", "-x", f"{out}/sc.png"]
        if peekaboo: t["peekaboo"] = [peekaboo, "see", "--mode", "screen", "--no-elements", "--retina", "--no-remote", "-o", f"{out}/pb.png"]
        if mss_python: t["mss (1x only)"] = [mss_python, "-c", mss_screen]
    elif scenario == "region":
        if snip: t["snip"] = [snip, "shot", "--region", rs, "-o", f"{out}/snip.png"]
        t["screencapture"] = ["screencapture", "-x", f"-R{rs}", f"{out}/sc.png"]
        if peekaboo: t["peekaboo"] = [peekaboo, "see", "--mode", "area", "--region", rs, "--no-elements", "--retina", "--no-remote", "-o", f"{out}/pb.png"]
        if mss_python: t["mss (1x only)"] = [mss_python, "-c", mss_region]
    elif scenario == "window" and window:
        if snip: t["snip"] = [snip, "shot", "--window", window, "-o", f"{out}/snip.png"]
        t["screencapture"] = ["screencapture", "-x", "-o", f"-l{window}", f"{out}/sc.png"]
        if peekaboo: t["peekaboo"] = [peekaboo, "see", "--window-id", window, "--no-elements", "--retina", "--no-remote", "-o", f"{out}/pb.png"]
    return t

def run(cmd):
    start = time.perf_counter()
    try:
        ok = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30).returncode == 0
    except subprocess.TimeoutExpired:
        ok = False
    return (time.perf_counter() - start) * 1000 if ok else None

parser = argparse.ArgumentParser()
parser.add_argument("--rounds", type=int, default=20)
parser.add_argument("scenarios", nargs="*", default=["screen", "region", "window"])
args = parser.parse_args()

chip = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
macos = subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip()
print(f"{chip}, macOS {macos}, {args.rounds} interleaved rounds, fresh process per shot")
for scenario in args.scenarios:
    candidates = tools(scenario)
    if not candidates:
        continue
    for cmd in candidates.values():
        run(cmd)  # warm up disk caches once
    times = {name: [] for name in candidates}
    failures = {name: 0 for name in candidates}
    load = []
    for _ in range(args.rounds):
        order = list(candidates.items())
        random.shuffle(order)
        for name, cmd in order:
            ms = run(cmd)
            if ms is None:
                failures[name] += 1
            else:
                times[name].append(ms)
        load.append(os.getloadavg()[0])
    print(f"\n{scenario} (load average {st.median(load):.1f})")
    print(f"  {'tool':16s} {'median':>8s} {'p10':>7s} {'p90':>7s}  failed")
    ranked = sorted((st.median(t), name) for name, t in times.items() if t)
    for med, name in ranked:
        t = sorted(times[name])
        print(f"  {name:16s} {med:6.0f} ms {t[len(t) // 10]:5.0f} ms {t[len(t) * 9 // 10]:5.0f} ms  {failures[name]}")
    for name, t in times.items():
        if not t:
            print(f"  {name:16s} every run failed")
