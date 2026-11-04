#!/usr/bin/env python3
"""prender: full render of the Quarto site in N parallel worker copies (Quarto 1.6.32), merged into _site.

  prender.py [--jobs N] [--only PATH ...]      (run from the project root)

Why copies: several `quarto render` processes in ONE project race on _site/search.json, listings.json
and .quarto/. Each worker gets its own copy of the sources, renders whole top-level folders,
then the outputs are merged; search.json is the union of the workers' entries. Pages with a
`listing:` (they read other pages' rendered HTML) are rendered again once at the end on the
merged site. Deterministic: the folder split depends only on file counts.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time
from concurrent.futures import ThreadPoolExecutor

SKIP_TOP = {"_site", ".quarto", ".git", "_freeze", "_extensions", "_templates", "site_libs"}

def inputs(root):
    out = []
    for d, dirs, files in os.walk(root):
        rel = os.path.relpath(d, root)
        parts = [] if rel == "." else rel.split(os.sep)
        if parts and (parts[0] in SKIP_TOP or any(p.startswith((".", "_")) for p in parts)):
            dirs[:] = []; continue
        for f in files:
            if f.endswith((".qmd", ".ipynb")) and not f.startswith(("_", ".")):
                out.append(os.path.normpath(os.path.join(rel, f)))
    return sorted(out)

def has_listing(path):
    with open(path, encoding="utf-8") as fh:
        t = fh.read()
    m = re.match(r"---\n(.*?)\n---", t, re.S)
    return bool(m and re.search(r"^listing:", m.group(1), re.M))

def copy_src(root, dst):
    ign = shutil.ignore_patterns("_site", ".quarto", ".git")
    shutil.copytree(root, dst, ignore=ign, symlinks=True)

def run(cwd, target, log):
    r = subprocess.run(["quarto", "render", target], cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
    if r.returncode:
        raise SystemExit("prender: quarto render %s failed in %s" % (target, cwd))

def sync(src, dst):
    """make dst identical to src (keeps the dst directory itself, so a server on it keeps working)"""
    os.makedirs(dst, exist_ok=True)
    want = set()
    for d, _, files in os.walk(src):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), src); want.add(rel)
            t = os.path.join(dst, rel); os.makedirs(os.path.dirname(t), exist_ok=True)
            shutil.copy2(os.path.join(d, f), t)
    for d, _, files in os.walk(dst):
        for f in files:
            rel = os.path.relpath(os.path.join(d, f), dst)
            if rel not in want:
                os.remove(os.path.join(dst, rel))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--only", nargs="+", help="render just these pages (e.g. navpatch representatives) and copy their HTML back")
    a = ap.parse_args()
    root = os.getcwd(); t0 = time.time()
    files = inputs(root)
    if a.only:
        return only(root, a.only, a.jobs, a.keep)
    groups = {}
    for f in files:
        groups.setdefault(f.split(os.sep)[0] if os.sep in f else f, []).append(f)
    bins = [[0, []] for _ in range(a.jobs)]
    for k, v in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        b = min(bins, key=lambda b: b[0]); b[0] += len(v); b[1].append(k)
    tmp = tempfile.mkdtemp(prefix="prender-")
    workers = []
    for i, b in enumerate(bins):
        w = os.path.join(tmp, "w%d" % i); copy_src(root, w); workers.append((w, b[1]))
    print("prender: %d inputs, %d workers: %s" % (len(files), a.jobs, " | ".join(",".join(b[1]) for b in bins)), flush=True)

    def work(wb):
        w, targets = wb
        with open(w + ".log", "w") as log:
            for t in targets:
                run(w, t, log)
    with ThreadPoolExecutor(a.jobs) as ex:
        list(ex.map(work, workers))
    t1 = time.time(); print("prender: pass 1 %.0fs" % (t1 - t0), flush=True)

    # merge: copy every worker's _site; search.json = union (stable order)
    merged = os.path.join(workers[0][0], "_site.merged"); os.makedirs(merged)
    search = {}
    for w, _ in workers:
        s = os.path.join(w, "_site")
        if not os.path.isdir(s):
            continue
        for d, _, fs in os.walk(s):
            for f in fs:
                rel = os.path.relpath(os.path.join(d, f), s)
                if rel == "search.json":
                    for e in json.load(open(os.path.join(d, f), encoding="utf-8")):
                        search.setdefault((e.get("href", ""), e.get("objectID", "")), e)
                    continue
                t = os.path.join(merged, rel); os.makedirs(os.path.dirname(t), exist_ok=True)
                shutil.copy2(os.path.join(d, f), t)
    with open(os.path.join(merged, "search.json"), "w", encoding="utf-8") as fh:
        json.dump([search[k] for k in sorted(search)], fh)
    w0 = workers[0][0]
    shutil.rmtree(os.path.join(w0, "_site")); os.rename(merged, os.path.join(w0, "_site"))

    # pass 2: listing pages (+ index) on the merged site, twice so listings that list each other settle
    late = [f for f in files if has_listing(os.path.join(root, f))] + ["index.qmd"]
    with open(w0 + ".log", "a") as log:
        for f in late:
            run(w0, f, log)
    t2 = time.time(); print("prender: pass 2 (%d listing pages) %.0fs" % (len(late), t2 - t1), flush=True)
    sync(os.path.join(w0, "_site"), os.path.join(root, "_site"))
    if not a.keep:
        shutil.rmtree(tmp)
    print("prender: done in %.0fs" % (time.time() - t0))

def only(root, pages, jobs, keep):
    t0 = time.time(); tmp = tempfile.mkdtemp(prefix="prender-only-")
    parts = [pages[i::jobs] for i in range(jobs) if pages[i::jobs]]
    ws = []
    for i, part in enumerate(parts):
        w = os.path.join(tmp, "w%d" % i); copy_src(root, w)
        if os.path.isdir(os.path.join(root, "_site")):    # listings/search see the current site
            shutil.copytree(os.path.join(root, "_site"), os.path.join(w, "_site"), symlinks=True)
        ws.append((w, part))
    def work(wp):
        w, part = wp
        with open(w + ".log", "w") as log:
            for f in part:
                run(w, f, log)
    with ThreadPoolExecutor(len(ws)) as ex:
        list(ex.map(work, ws))
    for w, part in ws:
        for f in part:
            h = os.path.splitext(f)[0] + ".html"
            shutil.copy2(os.path.join(w, "_site", h), os.path.join(root, "_site", h))
    if not keep:
        shutil.rmtree(tmp)
    print("prender: %d page(s) in %.0fs" % (len(pages), time.time() - t0))

if __name__ == "__main__":
    main()
