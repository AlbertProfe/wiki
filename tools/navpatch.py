#!/usr/bin/env python3
"""navpatch: apply a navbar/sidebar-only _quarto.yml change to every page of a rendered _site
without re-rendering it. Deterministic; prototype for wiki.sh (Quarto 1.6.32).

  navpatch.py plan  SITE              -> prints one representative .html per distinct header/sidebar
  navpatch.py apply SITE OLDREPS NEWREPS
      SITE    : _site to patch in place (old nav)
      OLDREPS : dir holding copies of the representative pages BEFORE re-render (same rel paths)
      NEWREPS : dir holding the representative pages re-rendered with the new config
Pages whose block matches no representative are printed as NEED-RENDER (wiki.sh renders them).
"""
import difflib, hashlib, os, posixpath, re, sys

BLOCKS = [("header", re.compile(r'<header id="quarto-header"'), "</header>"),
          ("sidebar", re.compile(r'<nav id="quarto-sidebar"'), "</nav>")]
URL = re.compile(r'(href|src)="([^"#:?][^"]*)"')

def block(lines, start, end):
    for i, l in enumerate(lines):
        if start.search(l):
            depth = 0
            tag = end[2:-1]
            for j in range(i, len(lines)):
                depth += len(re.findall(r'<%s[\s>]' % tag, lines[j])) - lines[j].count(end)
                if depth <= 0:
                    return i, j + 1
    return None

def canon(line, page):
    d = posixpath.dirname(page)
    def f(m):
        u = m.group(2)
        if re.match(r'^([a-zA-Z][a-zA-Z0-9+.-]*:|//)', u):
            return m.group(0)                     # absolute URL: leave as is
        a = u if u.startswith("/") else "/" + posixpath.normpath(posixpath.join(d, u))
        return '%s="@%s"' % (m.group(1), a)
    return URL.sub(f, line)

def decanon(line, page, absolute):
    d = posixpath.dirname(page)
    def f(m):
        a = m.group(2)
        if absolute:
            return '%s="%s"' % (m.group(1), a)
        r = posixpath.relpath(a.lstrip("/"), d or ".")
        if not r.startswith("."):
            r = "./" + r if d == "" else r
        return '%s="%s"' % (m.group(1), r)
    return re.sub(r'(href|src)="@([^"]*)"', f, line)

def norm(line, page):
    l = canon(line, page)
    l = re.sub(r'(class="[^"]*?) active(?=[ "])', r'\1', l)
    l = re.sub(r'(class="[^"]*sidebar-section[^"]*?) show(?=[ "])', r'\1', l)
    l = l.replace('aria-expanded="true"', 'aria-expanded="false"')
    l = re.sub(r' aria-current="page"', '', l)
    if 'quarto-page-breadcrumbs' in l:            # per-page; must never be copied between pages
        l = '<!--breadcrumbs-->'
    return l

def read(p):
    with open(p, encoding="utf-8", newline="") as fh:
        return fh.read().split("\n")

def pages(site):
    for root, _, files in os.walk(site):
        if "/site_libs" in root:
            continue
        for f in sorted(files):
            if f.endswith(".html"):
                yield posixpath.relpath(os.path.join(root, f), site)

def key(lines, page, name, start, end):
    b = block(lines, start, end)
    if not b:
        return None, None
    n = [norm(l, page) for l in lines[b[0]:b[1]]]
    return hashlib.sha1("\n".join(n).encode()).hexdigest(), b

def plan(site):
    seen = {}
    for p in sorted(pages(site)):
        lines = read(os.path.join(site, p))
        for name, s, e in BLOCKS:
            k, _ = key(lines, p, name, s, e)
            if k and (name, k) not in seen:
                seen[(name, k)] = p
    for p in sorted(set(seen.values())):
        print(p)

def apply(site, oldreps, newreps):
    rules = {}
    for p in pages(oldreps):
        o, n = read(os.path.join(oldreps, p)), read(os.path.join(newreps, p))
        for name, s, e in BLOCKS:
            k, bo = key(o, p, name, s, e)
            if not k or (name, k) in rules:
                continue
            bn = block(n, s, e)
            if not bn:
                continue
            no = [norm(l, p) for l in o[bo[0]:bo[1]]]
            nn = [norm(l, p) for l in n[bn[0]:bn[1]]]
            cn = [canon(l, p) for l in n[bn[0]:bn[1]]]
            ops = difflib.SequenceMatcher(None, no, nn, autojunk=False).get_opcodes()
            rules[(name, k)] = (ops, cn)
    changed = need = 0
    for p in pages(site):
        if os.path.exists(os.path.join(oldreps, p)):
            continue                                  # representatives are real renders
        path = os.path.join(site, p)
        lines = read(path)
        out = lines
        for name, s, e in BLOCKS:
            k, b = key(out, p, name, s, e)
            if not k:
                continue
            if (name, k) not in rules:
                print("NEED-RENDER", p, name); need += 1; continue
            ops, cn = rules[(name, k)]
            if all(t == "equal" for t, *_ in ops):
                continue
            if any(t != "equal" and any('quarto-page-breadcrumbs' in l for l in cn[j1:j2])
                   for t, i1, i2, j1, j2 in ops):
                print("NEED-RENDER", p, name, "(breadcrumbs change)"); need += 1; continue
            blk = out[b[0]:b[1]]
            absolute = bool(re.search(r'href="/[^/]', "\n".join(blk)))
            new = []
            for t, i1, i2, j1, j2 in ops:
                if t == "equal":
                    new += blk[i1:i2]
                else:
                    for l in cn[j1:j2]:
                        l = decanon(l, p, absolute)
                        if re.search(r'href="@?/?%s"' % re.escape(p), canon(l, p).replace("@/", "/")) and "-link" in l:
                            l = re.sub(r'class="([^"]*(?:nav-link|sidebar-link))', r'class="\1 active', l, count=1)
                        new.append(l)
            out = out[:b[0]] + new + out[b[1]:]
        if out is not lines:
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write("\n".join(out))
            changed += 1
    print("patched %d page(s); %d need a real render" % (changed, need))
    return 1 if need else 0

if __name__ == "__main__":
    if sys.argv[1] == "plan":
        plan(sys.argv[2])
    else:
        sys.exit(apply(*sys.argv[2:5]))
