#!/usr/bin/env bash
# wiki.sh - one deterministic workflow for albertprofe.dev (Quarto wiki, repo AlbertProfe/wiki)
#
# Same script for every publisher: Grok Bot's box, Albert's Linux VM and the GitHub Action.
# Run `./wiki.sh -h` for the command reference.
# Worktrees (box): each bot works in its own git worktree, /workspace/wiki-team/repos/wt/<bot>,
# with WIKI_BOT=<bot>; publish is serialised with a flock. The preview lock is only for the one ngrok URL;
# fallback previews (publiclocal, localhost.run) can run in parallel, one per bot. See FLOW.md "Worktrees".
set -euo pipefail

# ----------------------------------------------------------------------------- constants
readonly QUARTO_REQUIRED="1.6.32"
readonly MAIN_BRANCH="master"
readonly LIVE_TAG="live"
# Untracked revealjs theme CSS that Quarto drops into _freeze on render; never commit it.
readonly STRAY_RE='^_freeze/site_libs/revealjs/dist/theme/quarto-[0-9a-f]+\.css$'
# Paths that are never staged by `save`.
readonly NEVER_STAGE_RE='^(_site/|\.quarto/|_publish\.yml$)'
# Commit message convention (see `./wiki.sh -h`).
readonly MSG_SPRINT_RE='^[a-z][a-z0-9]*( [a-z0-9]+)* 20[0-9]{2} sprint ?#[0-9]+( .+)?$'
readonly MSG_TYPED_RE='^(landing|page|lab|book|course|infra|fix|style): [^ ].*$'
readonly MSG_MAX=72
PREVIEW_UP="${WIKI_PREVIEW_UP:-/workspace/wiki-team/landing/preview-up.sh}"
PREVIEW_URL="${WIKI_PREVIEW_URL:-https://unpenetrating-loura-overresolutely.ngrok-free.dev}"
PREVIEW_PORT="${WIKI_PREVIEW_PORT:-8787}"   # must match preview-up.sh
QUARTO="${QUARTO:-quarto}"
WT_ROOT="${WIKI_WT_ROOT:-/workspace/wiki-team/repos/wt}"   # bot worktrees on the box
LOCK_DIR="${WIKI_LOCK_DIR:-}"                                 # default set in preflight
SHARED_SITE="${WIKI_SHARED_SITE:-}"   # team's shared build (box only; default set in preflight; "off" disables)
if [[ -d "$HOME/.local/bin" ]]; then PATH="$HOME/.local/bin:$PATH"; fi

DRY_RUN=0
ENVIRONMENT=""
REPO=""
GIT_DIR_ABS=""
GIT_COMMON_ABS=""
IS_WORKTREE=0      # 1 = running in a linked worktree (a bot folder), not the main clone
MAIN_WT=""         # path of the main clone (first entry of git worktree list)
BOT=""             # who is running: $WIKI_BOT, else the worktree folder name
declare -A HELD_LOCKS=()
# Set by plan_publish: what publish must render to bring a _site built from one tree up to HEAD.
P_FULL=0; P_REASON=""; P_NAVP=0; P_PAGES=(); P_COPIES=()

# ----------------------------------------------------------------------------- output
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_DIM=$'\e[2m'; C_OFF=$'\e[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""; C_OFF=""
fi
info() { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()   { if (( DRY_RUN )); then printf '%s ok%s (dry-run, would be) %s\n' "$C_GRN" "$C_OFF" "$*"; else printf '%s ok%s %s\n' "$C_GRN" "$C_OFF" "$*"; fi; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%sERROR%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Every command that changes something (files, git, remote, processes) goes through run().
run() {
  if (( DRY_RUN )); then
    printf '%s[dry-run]%s %s\n' "$C_YEL" "$C_OFF" "$(printf '%q ' "$@")"
  else
    printf '%s+ %s%s\n' "$C_DIM" "$(printf '%q ' "$@")" "$C_OFF"
    "$@"
  fi
}

usage() {
  cat <<'EOF'
wiki.sh - workflow for albertprofe.dev (Quarto 1.6.32 only)

Usage: ./wiki.sh [--dry-run] <command> [options]

Worktrees (box): run it from your own folder, e.g.
  cd /workspace/wiki-team/repos/wt/wiki-ops && WIKI_BOT=wiki-ops ./wiki.sh start
  Between sessions a worktree is detached at origin/master; start creates the session branch.
  Locks in /workspace/wiki-team/locks: preview (exclusive ngrok URL on port 8787), publish (merge/publish/ship).
  Fallback previews do not take that lock: each bot gets its own port (8788+) and URL.
  Shared build: every publish on the box saves its _site to /workspace/wiki-team/cache/wiki-site;
  when your own _site would need a FULL render (styles.css, _quarto.yml... changed since you last
  built) publish and preview copy that build in and render only your pages. WIKI_SHARED_SITE=off disables.

Session (box or Albert's VM):
  start                       pull master, create session/YYYY-MM-DD-N (next free N);
                              in a worktree: fetch, branch from origin/master
  preview [--all] [--tunnel] [files.qmd...]   (preview --stop: stop only your preview)
                              render given .qmd files (default: .qmd changed vs master,
                              committed + uncommitted + untracked) into _site;
                              --all = full render; --tunnel = serve this folder's _site
                              (box only). Tries ngrok first (exclusive lock, stable URL).
                              If the ngrok lock is held or ngrok is unhealthy, does not wait:
                              falls through to publiclocal.app, then localhost.run, on a
                              free port (8788+). Several bots can preview at once this way.
                              SSH fallbacks auto-reconnect if the tunnel drops; the public
                              URL may change. status flags a dead tunnel (pid gone or URL
                              not HTTP 200). WIKI_PREVIEW_BACKEND=ngrok|publiclocal|localhost.run
                              forces one.
  save [--any-message] "msg"  stage content changes (never _site/.quarto/stray CSS),
                              check the message convention, commit, push the session branch
  merge                       rebase session onto origin/master if master moved,
                              fast-forward master, push master (never force); in a worktree:
                              push HEAD:master, then detach at origin/master
  publish [--all]             on master (or a worktree detached at origin/master):
                              render what changed since the last publish,
                              quarto publish gh-pages --no-render, move tag 'live'.
                              Escalates to a full render automatically when needed.
  ship                        merge + publish + delete the session branch (local + remote)
  status                      branch, dirty files, quarto, environment, commits ahead of live,
                              preview/tunnel state, worktrees, lock holders

Courses (on a session branch; changes _quarto.yml, so the next publish is full):
  course new <code> <edition> [--from <folder>]   e.g. course new ifcd0021 27
  course archive <code> <edition>                 e.g. course archive ifcd0021 26

Global:
  --dry-run   print every mutating command instead of running it
  -h, --help  this help

Commit messages (checked by `save`; override with --any-message), max 72 chars:
  Sprint work, your usual style:  <course> <year> sprint #<n> [<k>] [note]
      fullstack 2026 sprint #8 3
      scrum agile 2026 sprint#4 6 ponderacions
  Everything else:                <type>: <summary>
      type = landing | page | lab | book | course | infra | fix | style
      landing: rebuild hero with orbiting course chips
      course: new ifcd0021-27
EOF
}

# ----------------------------------------------------------------------------- preflight
detect_env() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then ENVIRONMENT="github-actions"
  elif [[ -d /workspace || "$HOME" == "/home/box" ]]; then ENVIRONMENT="box"
  else ENVIRONMENT="local"; fi
}

preflight() {
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
  cd "$REPO"
  [[ -f _quarto.yml ]] || die "$REPO has no _quarto.yml; run wiki.sh from the wiki repo"
  GIT_DIR_ABS="$(git rev-parse --absolute-git-dir)"
  GIT_COMMON_ABS="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  [[ "$(cd "$GIT_DIR_ABS" && pwd -P)" != "$GIT_COMMON_ABS" ]] && IS_WORKTREE=1
  MAIN_WT="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
  command -v "$QUARTO" >/dev/null 2>&1 || die "quarto not found on PATH (need $QUARTO_REQUIRED; never install another version)"
  local v; v="$("$QUARTO" --version 2>/dev/null | tr -d '[:space:]')"
  [[ "$v" == "$QUARTO_REQUIRED" ]] || die "quarto is $v, required $QUARTO_REQUIRED. Do not upgrade; fix PATH instead."
  detect_env
  BOT="${WIKI_BOT:-$(basename "$REPO")}"
  if (( IS_WORKTREE )) && [[ -n "${WIKI_BOT:-}" && "$WIKI_BOT" != "$(basename "$REPO")" ]]; then
    warn "WIKI_BOT=$WIKI_BOT but this is the $(basename "$REPO") worktree ($REPO): are you in the right folder?"
  fi
  if [[ -z "$LOCK_DIR" ]]; then
    if [[ "$ENVIRONMENT" == "box" ]]; then LOCK_DIR="/workspace/wiki-team/locks"; else LOCK_DIR="$GIT_COMMON_ABS/wiki-locks"; fi
  fi
  if [[ -z "$SHARED_SITE" && "$ENVIRONMENT" == "box" ]]; then
    SHARED_SITE="/workspace/wiki-team/cache/$(basename "${MAIN_WT:-$REPO}")-site"   # e.g. cache/wiki-site
  fi
  [[ "$SHARED_SITE" == "off" ]] && SHARED_SITE=""
  if [[ "$ENVIRONMENT" == "github-actions" && -z "$(git config user.name || true)" ]]; then
    run git config user.name "github-actions[bot]"
    run git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  fi
}

# Only commands that commit or tag need an identity (status, preview, course, dry-runs do not).
require_identity() {
  (( DRY_RUN )) && return 0
  [[ -n "$(git config user.name || true)" && -n "$(git config user.email || true)" ]] \
    || die "git identity missing: git config user.name/user.email"
}

require_not_actions() {
  [[ "$ENVIRONMENT" != "github-actions" ]] || die "'$1' is not allowed in GitHub Actions (publish/status only)"
}

current_branch() { git symbolic-ref --quiet --short HEAD || echo "(detached)"; }

# Base the session is compared with: origin/master in a worktree (it has no master checkout), else master.
base_ref() { if (( IS_WORKTREE )); then echo "origin/$MAIN_BRANCH"; else echo "$MAIN_BRANCH"; fi; }

# "On main": on master, or detached exactly at origin/master (a worktree between sessions).
on_main() {
  local b; b="$(current_branch)"
  [[ "$b" == "$MAIN_BRANCH" ]] && return 0
  [[ "$b" == "(detached)" ]] && [[ "$(git rev-parse HEAD)" == "$(git rev-parse -q --verify "origin/$MAIN_BRANCH" || true)" ]]
}

has_linked_worktrees() { (( $(git worktree list --porcelain | grep -c '^worktree ') > 1 )); }

# ----------------------------------------------------------------------------- locks
# flock locks in $LOCK_DIR, shared by all worktrees. A lock lives as long as the open fd: it is
# released when wiki.sh exits, or (ngrok preview) when the server + ngrok it started exit, because
# they inherit the fd. The lock file's first line says who holds it. Fallback previews do not
# take this lock.
lock_file()  { echo "$LOCK_DIR/$1.lock"; }
lock_owner() { local f; f="$(lock_file "$1")"; if [[ -s "$f" ]]; then head -n1 "$f"; else echo "unknown"; fi; }
lock_is_held() {   # held by any process (including our own children)
  local f fd; f="$(lock_file "$1")"
  [[ -e "$f" ]] && command -v flock >/dev/null 2>&1 || return 1
  [[ -n "${HELD_LOCKS[$1]:-}" ]] && return 0
  exec {fd}<"$f"
  if flock -n "$fd"; then flock -u "$fd"; exec {fd}<&-; return 1; fi
  exec {fd}<&-; return 0
}
take_lock() {   # take_lock <name>: non-blocking; refuses (dies) naming the holder
  local name="$1" f fd
  [[ -n "${HELD_LOCKS[$name]:-}" ]] && return 0          # re-entrant (ship = merge + publish)
  if (( DRY_RUN )); then
    if lock_is_held "$name"; then warn "[dry-run] $name lock is held by: $(lock_owner "$name") (the real run would stop here)"
    else info "[dry-run] would take the $name lock ($(lock_file "$name"))"; fi
    return 0
  fi
  if ! command -v flock >/dev/null 2>&1; then warn "flock not found: running without the $name lock"; return 0; fi
  mkdir -p "$LOCK_DIR"; f="$(lock_file "$name")"
  exec {fd}<>"$f"
  if ! flock -n "$fd"; then
    exec {fd}>&-
    die "the $name lock is held by: $(lock_owner "$name")
Wait until it is released (./wiki.sh status shows it), or ask that bot. Never kill another bot's processes."
  fi
  printf '%s pid=%s worktree=%s since=%s\n' "$BOT" "$$" "$REPO" "$(date '+%F %H:%M %Z')" > "$f"
  HELD_LOCKS[$name]=$fd
}
try_lock() {    # try_lock <name>: like take_lock, but returns 1 instead of dying when it is held
  local name="$1" f fd
  [[ -n "${HELD_LOCKS[$name]:-}" ]] && return 0
  command -v flock >/dev/null 2>&1 || return 0
  mkdir -p "$LOCK_DIR"; f="$(lock_file "$name")"
  exec {fd}<>"$f"
  if ! flock -n "$fd"; then exec {fd}>&-; return 1; fi
  printf '%s pid=%s worktree=%s since=%s\n' "$BOT" "$$" "$REPO" "$(date '+%F %H:%M %Z')" > "$f"
  HELD_LOCKS[$name]=$fd
}
release_lock() {   # release_lock <name>: drop a lock taken with try_lock/take_lock before exit
  local fd="${HELD_LOCKS[$1]:-}"
  [[ -n "$fd" ]] || return 0
  flock -u "$fd" 2>/dev/null || true
  exec {fd}>&-
  unset "HELD_LOCKS[$1]"
}

# Fast-forward the main clone's master to origin/master (best effort; it is only the shared base).
sync_main_clone() {
  (( IS_WORKTREE )) || return 0
  [[ -n "$MAIN_WT" && -d "$MAIN_WT" ]] || return 0
  local b; b="$(git -C "$MAIN_WT" symbolic-ref --quiet --short HEAD || true)"
  if [[ "$b" != "$MAIN_BRANCH" ]]; then warn "main clone $MAIN_WT is on '${b:-detached}', not $MAIN_BRANCH: left as is"; return 0; fi
  git merge-base --is-ancestor "origin/$MAIN_BRANCH" "$MAIN_BRANCH" && return 0   # already up to date
  if [[ -n "$(cd "$MAIN_WT" && dirty_files)" ]]; then warn "main clone $MAIN_WT has local changes: its $MAIN_BRANCH was not fast-forwarded"; return 0; fi
  run git -C "$MAIN_WT" merge --ff-only --quiet "origin/$MAIN_BRANCH" || warn "could not fast-forward $MAIN_BRANCH in $MAIN_WT"
}

# Porcelain status minus the known stray CSS.
dirty_files() {
  git status --porcelain=v1 --untracked-files=all | while IFS= read -r line; do
    local path="${line:3}"
    [[ "${line:0:2}" == "??" && "$path" =~ $STRAY_RE ]] && continue
    printf '%s\n' "$line"
  done
}

require_clean() {
  local d; d="$(dirty_files)"
  [[ -z "$d" ]] || die "working tree not clean:
$d"
}

require_session() {
  local b; b="$(current_branch)"
  [[ "$b" == session/* ]] || die "must be on a session/* branch (now on $b). Run ./wiki.sh start"
}

# Quarto extensions the pages need. They are committed in _extensions/ (pinned, so
# every machine renders the same); as a safety net, install them only when missing. Without them render
# prints raw {{< fa >}} / {{< tweet >}} shortcodes. Lightbox is built into Quarto 1.6 (lightbox: auto), not an extension.
readonly EXTENSIONS=(
  "quarto-ext/fontawesome|https://github.com/quarto-ext/fontawesome/archive/refs/tags/v1.2.0.zip"
  "social-embeds|https://github.com/sellorm/quarto-social-embeds/archive/26c70ec45d574c3bec7b44b8ce6840a82e3ad271.zip"
)
ensure_extensions() {
  local e dir url
  for e in "${EXTENSIONS[@]}"; do
    dir="${e%%|*}"; url="${e#*|}"
    if [[ ! -f "_extensions/$dir/_extension.yml" ]]; then
      info "installing missing Quarto extension $dir"
      run "$QUARTO" add "$url" --no-prompt
    fi
  done
}

remote_has_branch() { [[ -n "$(git ls-remote --heads origin "refs/heads/$1" 2>/dev/null)" ]]; }

site_stamp_file()   { echo "$GIT_DIR_ABS/wiki-site-stamp"; }      # "tree <hash>": source tree _site was fully built from
preview_dirty_file(){ echo "$GIT_DIR_ABS/wiki-preview-dirty"; }   # "<page> <blob>": pages rendered on top of that tree
WIKI_JOBS="${WIKI_JOBS:-4}"                                        # parallel full render (1 = plain quarto render)

# Tree hash of the sources exactly as they are on disk (tracked + untracked, outputs and stray CSS excluded).
source_tree() {
  local idx; idx="$(mktemp)"
  GIT_INDEX_FILE="$idx" git read-tree HEAD
  GIT_INDEX_FILE="$idx" git add -A -- . ':(exclude)_site' ':(exclude).quarto' ':(exclude)_freeze/site_libs' >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git write-tree
  rm -f "$idx"
}
# Tree that _site was built from ("" if unknown). Old stamps held a commit: use its tree.
stamp_tree() {
  local s; s="$(cat "$(site_stamp_file)" 2>/dev/null || true)"
  case "$s" in
    tree\ *) echo "${s#tree }" ;;
    "") echo "" ;;
    *) git rev-parse -q --verify "$s^{tree}" 2>/dev/null || echo "" ;;
  esac
}
# Blob a page was last rendered from on top of the stamp ("" if never).
dirty_blob() { awk -v p="$1" '$1 == p { b = $2 } END { print b }' "$(preview_dirty_file)" 2>/dev/null; }

render_full() {
  if (( WIKI_JOBS > 1 )); then
    info "full render, $WIKI_JOBS parallel workers (about 5 minutes)"
    run python3 tools/prender.py --jobs "$WIKI_JOBS"
  else
    info "full render (about 10 minutes)"
    run "$QUARTO" render
  fi
  if (( ! DRY_RUN )); then
    echo "tree $(source_tree)" > "$(site_stamp_file)"
    : > "$(preview_dirty_file)"
  fi
}

# True when the only _quarto.yml changes between two trees are website.navbar / page-footer (sidebar changes need a full render).
nav_only_change() {
  python3 - "$(git show "$1:_quarto.yml")" "$(cat _quarto.yml)" <<'PY'
import sys, yaml
a, b = (yaml.safe_load(x) or {} for x in sys.argv[1:3])
for y in (a, b):
    # sidebar changes are NOT nav-only: they change prev/next links and breadcrumbs,
    # which the nav patch does not update (tested 2026-11-04), so they get a full render
    for k in ("navbar", "page-footer"):
        (y.get("website") or {}).pop(k, None)
sys.exit(0 if a == b else 1)
PY
}

# Apply a nav-only _quarto.yml change: render one page per distinct header/sidebar, splice the rest.
nav_patch() {
  local reps old; old="$(mktemp -d)"
  mapfile -t reps < <(python3 tools/navpatch.py plan _site)
  info "nav patch: ${#reps[@]} representative page(s), splicing the rest"
  local p; for p in "${reps[@]}"; do install -D -m 0644 "_site/$p" "$old/$p"; done
  run python3 tools/prender.py --jobs "$WIKI_JOBS" --only "${reps[@]/%.html/.qmd}"
  if ! run python3 tools/navpatch.py apply _site "$old" _site; then
    rm -rf "$old"; return 1
  fi
  rm -rf "$old"
}

# ----------------------------------------------------------------------------- shared build
# Team rule 12 (Albert, 2026-11-19): "global changes must be shared, reuse changes from one bot to team".
# Every successful publish on the box copies its _site (plus .quarto idx/listing/xref) to $SHARED_SITE,
# stamped with the source tree it matches (= the published HEAD). When a worktree's own _site would need a
# FULL render (a global file changed since it was built: styles.css, _quarto.yml, *.scss, _extensions...),
# publish/preview check whether the shared build already covers HEAD's global files; if so they copy it in,
# adopt its stamp and render only the pages that differ. Anything that does not match -> full render as before.
# Reads and writes of $SHARED_SITE happen under the publish lock.

# Short hash of the global files of a tree: what forces a full render when it changes.
globals_key() {
  git ls-tree -r "$1" | awk -F'\t' '
    $2 ~ /^(_quarto\.yml|_metadata\.yml|CNAME)$/ || $2 ~ /^_extensions\// || $2 ~ /^tools\/.*\.theme$/ ||
    ($2 ~ /\.s?css$/ && $2 !~ /^(_templates|_freeze|_site)\//)' | git hash-object --stdin | cut -c1-12
}
# Tree the shared build was made from ("" if none, being written, or not of this repo).
shared_tree() {
  [[ -n "$SHARED_SITE" ]] || return 0
  local s t; s="$(head -n1 "$SHARED_SITE/stamp" 2>/dev/null || true)"
  [[ "$s" == "tree "* ]] || return 0
  t="${s#tree }"
  [[ -f "$SHARED_SITE/site/index.html" ]] && git cat-file -e "$t^{tree}" 2>/dev/null && echo "$t"
  return 0
}
shared_who() { sed -n 's/^by //p' "$SHARED_SITE/stamp" 2>/dev/null || true; }
# Make directory $2 identical to $1 (keeps $2 itself, so a preview server on it keeps working).
sync_dir() {
  python3 - "$1" "$2" <<'PY'
import os, shutil, sys
src, dst = sys.argv[1:3]
os.makedirs(dst, exist_ok=True)
want, n, gone = set(), 0, 0
for d, _, files in os.walk(src):
    for f in files:
        rel = os.path.normpath(os.path.relpath(os.path.join(d, f), src)); want.add(rel)
        s, t = os.path.join(src, rel), os.path.join(dst, rel)
        ss = os.stat(s)
        try:
            ts = os.stat(t)
            if ts.st_size == ss.st_size and ts.st_mtime_ns == ss.st_mtime_ns: continue
        except FileNotFoundError:
            pass
        os.makedirs(os.path.dirname(t), exist_ok=True)
        shutil.copy2(s, t); n += 1
for d, _, files in os.walk(dst):
    for f in files:
        rel = os.path.normpath(os.path.relpath(os.path.join(d, f), dst))
        if rel not in want: os.remove(os.path.join(dst, rel)); gone += 1
print(f"  {src} -> {dst}: {n} file(s) copied, {gone} stale output file(s) removed")
PY
}
# After a publish: save this _site as the team's shared build (caller holds the publish lock).
shared_site_save() {
  [[ -n "$SHARED_SITE" ]] || return 0
  local t d; t="$(git rev-parse "$1^{tree}")"
  if (( DRY_RUN )); then info "[dry-run] would save this _site as the team's shared build ($SHARED_SITE, tree ${t:0:8})"; return 0; fi
  info "saving this _site as the team's shared build ($SHARED_SITE)"
  mkdir -p "$SHARED_SITE"
  echo "pending $BOT $(date '+%F %H:%M %Z')" > "$SHARED_SITE/stamp"   # unusable until complete
  sync_dir _site "$SHARED_SITE/site" || return 1
  for d in idx listing xref; do
    if [[ -d ".quarto/$d" ]]; then sync_dir ".quarto/$d" "$SHARED_SITE/quarto/$d" || return 1; fi
  done
  printf 'tree %s\nglobals %s\ncommit %s\nby %s %s\n' "$t" "$(globals_key "$t")" "$(git rev-parse "$1")" "$BOT" "$(date '+%F %H:%M %Z')" > "$SHARED_SITE/stamp"
  ok "shared build = tree ${t:0:8} (globals $(globals_key "$t")); other bots reuse it instead of a full render"
}
# Copy the shared build (tree $1) into this worktree and adopt its stamp (caller holds the publish lock).
shared_site_adopt() {
  local t="$1" d
  if (( DRY_RUN )); then info "[dry-run] would copy the shared build into _site and stamp it tree ${t:0:8}"; return 0; fi
  echo "adopting" > "$(site_stamp_file)"   # if anything fails below, the stamp is unknown -> full render next time
  sync_dir "$SHARED_SITE/site" _site || return 1
  for d in idx listing xref; do
    if [[ -d "$SHARED_SITE/quarto/$d" ]]; then sync_dir "$SHARED_SITE/quarto/$d" ".quarto/$d" || return 1; fi
  done
  [[ "$(shared_tree)" == "$t" ]] || return 1   # changed while copying (should not happen under the lock)
  echo "tree $t" > "$(site_stamp_file)"
  : > "$(preview_dirty_file)"
  ok "_site is now the shared build (tree ${t:0:8})"
}

# plan_publish <base-tree> <head-commit> <use-dirty 0|1>: what must be rendered to bring a _site built from
# <base-tree> (plus, with use-dirty, the pages previewed on top of it) up to <head>. Sets P_*.
plan_publish() {
  local base="$1" head="$2" usedirty="$3" st p1 p2 db
  P_FULL=0; P_REASON=""; P_NAVP=0; P_PAGES=(); P_COPIES=()
  while IFS=$'\t' read -r st p1 p2; do
    db=""; if (( usedirty )); then db="$(dirty_blob "$p1")"; fi
    case "$st" in
      M*|T*)
        case "$p1" in
          _quarto.yml)
            if [[ -n "$db" && "$db" == "$(git rev-parse "$head:_quarto.yml")" ]]; then :   # nav patched at preview
            elif nav_only_change "$base"; then P_NAVP=1
            else P_FULL=1; P_REASON="$p1 changed"; fi ;;
          _metadata.yml|*.scss|*.css|CNAME|_extensions/*) P_FULL=1; P_REASON="$p1 changed" ;;
          _freeze/*|_templates/*|.github/*|wiki.sh|README.md|FLOW.md|.gitignore) ;;
          _*) ;;
          *.qmd) [[ -n "$db" && "$db" == "$(git rev-parse "$head:$p1")" ]] || P_PAGES+=("$p1") ;;
          images/*) P_COPIES+=("$p1") ;;
          *) P_FULL=1; P_REASON="$p1 changed (not a page or image)" ;;
        esac ;;
      A*)
        case "$p1" in
          *.qmd) [[ "$p1" == _* ]] || { P_FULL=1; P_REASON="page added: $p1"; } ;;
          images/*) P_COPIES+=("$p1") ;;
          _freeze/*|_templates/*|.github/*|wiki.sh|README.md|FLOW.md) ;;
          *) P_FULL=1; P_REASON="file added: $p1" ;;
        esac ;;
      D*) case "$p1" in _freeze/*|.github/*) ;; *) P_FULL=1; P_REASON="file deleted: $p1" ;; esac ;;
      R*|C*) P_FULL=1; P_REASON="file renamed: $p1 -> $p2" ;;
      *) P_FULL=1; P_REASON="unknown change $st $p1" ;;
    esac
    if (( P_FULL )); then return 0; fi
  done < <(git diff --name-status -M "$base" "$head^{tree}")
  # pages rendered on top of the stamp from content that is not what HEAD has: render again
  if (( usedirty )) && [[ -s "$(preview_dirty_file)" ]]; then
    local f b
    while read -r f b; do
      if [[ "$f" == "__FULL__" ]]; then P_FULL=1; P_REASON="full preview render recorded by the old wiki.sh"; return 0; fi
      [[ "$f" == *.qmd ]] || continue
      if [[ ! -f "$f" ]]; then P_FULL=1; P_REASON="previewed page no longer on $MAIN_BRANCH: $f"; return 0; fi
      [[ "$(dirty_blob "$f")" == "$(git rev-parse "$head:$f" 2>/dev/null)" ]] || P_PAGES+=("$f")
    done < "$(preview_dirty_file)"
  fi
  return 0
}

# Preview: if this _site predates a global change that the shared build already has, adopt the shared build
# first, so the preview shows the current styles without a full render. Best effort; never fatal.
preview_use_shared() {
  [[ -n "$SHARED_SITE" ]] || return 0
  local shared own src; shared="$(shared_tree)"; [[ -n "$shared" ]] || return 0
  own="$(stamp_tree)"; src="$(source_tree)"
  [[ "$own" == "$shared" ]] && return 0
  [[ "$(globals_key "$shared")" == "$(globals_key "$src")" ]] || return 0               # shared build is not on your global files
  if [[ -n "$own" ]] && git cat-file -e "$own" 2>/dev/null && [[ "$(globals_key "$own")" == "$(globals_key "$src")" ]]; then return 0; fi   # yours already is
  info "your _site predates a global change; the team's shared build (tree ${shared:0:8}, by $(shared_who)) has it"
  if (( DRY_RUN )); then shared_site_adopt "$shared"; return 0; fi
  if ! try_lock publish; then warn "publish lock held by $(lock_owner publish): not copying the shared build now (styles may look old in this preview)"; return 0; fi
  shared_site_adopt "$shared" || warn "copying the shared build failed; run ./wiki.sh preview --all if the preview looks wrong"
  release_lock publish
}

# ----------------------------------------------------------------------------- start
# Next free session/YYYY-MM-DD-N, counting local branches (shared by all worktrees), branches checked
# out in any worktree, remote-tracking branches and what origin has right now.
next_session_name() {
  local day n=1 taken
  day="$(date +%F)"
  taken="$( {
    git for-each-ref --format='%(refname:lstrip=2)' "refs/heads/session/$day-*"
    git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/session/$day-*"
    git worktree list --porcelain | sed -n 's#^branch refs/heads/##p'
    git ls-remote --heads origin 2>/dev/null | sed -n 's#^.*refs/heads/##p'
  } | sort -u )"
  while grep -qxF "session/$day-$n" <<<"$taken"; do n=$((n + 1)); done
  echo "session/$day-$n"
}

cmd_start() {
  require_not_actions start
  require_clean
  local name
  if (( IS_WORKTREE )); then
    take_lock start   # two bots starting at once must not pick the same N
    git fetch --quiet --prune origin || die "git fetch failed"
    sync_main_clone
    name="$(next_session_name)"
    run git switch --quiet --no-track -c "$name" "origin/$MAIN_BRANCH"
  else
    if [[ "$ENVIRONMENT" == "box" ]] && has_linked_worktrees; then
      die "$REPO is the shared main clone; bots work in their own worktree:
  cd $WT_ROOT/<bot> && WIKI_BOT=<bot> ./wiki.sh start"
    fi
    run git checkout "$MAIN_BRANCH"
    run git pull --ff-only origin "$MAIN_BRANCH"
    git fetch --quiet origin || warn "fetch failed; checking remote branches with ls-remote only"
    name="$(next_session_name)"
    run git checkout -b "$name"
  fi
  ok "session branch $name ready in $REPO"
}


preview_url_file() { echo "$LOCK_DIR/preview-$BOT.url"; }

current_preview_field() {
  local key="$1" f; f="$(preview_url_file)"
  if [[ -s "$f" ]]; then awk -F= -v k="$key" '$1==k{print $2; exit}' "$f"; fi
}

current_preview_backend() { current_preview_field backend; }
current_preview_url() {
  local u; u="$(current_preview_field url)"
  if [[ -n "$u" ]]; then printf '%s\n' "$u"; else printf '%s\n' "$PREVIEW_URL"; fi
}

preview_curl_code() {   # preview_curl_code <url> [backend]
  local url="$1" backend="${2:-}"
  if [[ "$backend" == "ngrok" || ( -z "$backend" && "$url" == *ngrok* ) ]]; then
    curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'ngrok-skip-browser-warning: 1' "$url/" || true
  else
    curl -s -m 10 -o /dev/null -w '%{http_code}' "$url/" || true
  fi
}

# Kill a pid and every descendant (script(1) puts ssh in a new session).
kill_tree() {
  local pid="$1" c
  [[ -n "${pid:-}" && "$pid" =~ ^[0-9]+$ ]] || return 0
  for c in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill_tree "$c"
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -- "-$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
    local i
    for i in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || return 0
      sleep 0.15
    done
    kill -9 -- "-$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
  fi
}

stop_pidfile() {
  local f="$1" pid
  [[ -f "$f" ]] || return 0
  pid="$(cat "$f" 2>/dev/null || true)"
  rm -f "$f"
  kill_tree "$pid"
}

# ----------------------------------------------------------------------------- preview
changed_qmd_vs_main() {
  {
    git diff --name-only "$(base_ref)"...HEAD 2>/dev/null || true
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | grep -E '\.qmd$' | grep -Ev '^(_|\.)' | sort -u | while IFS= read -r f; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
}

render_one() { run "$QUARTO" render "$1"; }

cmd_preview() {
  require_not_actions preview
  local tunnel=0 all=0 files=()
  while (($#)); do
    case "$1" in
      --tunnel) tunnel=1 ;;
      --stop) preview_stop; return 0 ;;
      --all) all=1 ;;
      -*) die "preview: unknown option $1" ;;
      *) files+=("$1") ;;
    esac
    shift
  done
  if (( tunnel )); then
    [[ "$ENVIRONMENT" == "box" ]] || die "--tunnel only works on the box"
    [[ -x "$PREVIEW_UP" ]] || die "preview script not found: $PREVIEW_UP"
    [[ "$BOT" =~ ^[A-Za-z0-9._-]+$ ]] || die "WIKI_BOT must be a short name (got ${BOT:-empty})"
    # Restart only this bot's preview. Do not take the ngrok lock here: if it is
    # held, preview-up.sh skips ngrok immediately and uses a fallback on another port.
    if (( ! DRY_RUN )) && [[ -s "$(preview_url_file)" ]]; then
      info "restarting your preview ($BOT) on $REPO/_site"
      kill_preview_processes
    fi
  fi
  ensure_extensions
  if (( all )); then
    render_full
  else
    if ((${#files[@]} == 0)); then
      mapfile -t files < <(changed_qmd_vs_main)
      ((${#files[@]})) || info "no changed .qmd files vs $(base_ref); nothing to render"
    fi
    preview_use_shared
    local st yb; st="$(stamp_tree)"; yb="$(git hash-object _quarto.yml)"
    if [[ -n "$st" ]] && [[ "$(git rev-parse "$st:_quarto.yml")" != "$yb" && "$(dirty_blob _quarto.yml)" != "$yb" ]]; then
      if nav_only_change "$st"; then
        if nav_patch; then
          (( DRY_RUN )) || echo "_quarto.yml $yb" >> "$(preview_dirty_file)"
        else
          warn "nav patch failed: full render"; render_full
        fi
      else
        warn "_quarto.yml changed beyond navbar/footer (sidebar changes need a full render): run ./wiki.sh preview --all"
      fi
    fi
    local f
    for f in "${files[@]}"; do
      [[ -f "$f" && "$f" == *.qmd ]] || die "not a .qmd file: $f"
      render_one "$f"
      (( DRY_RUN )) || echo "$f $(git hash-object "$f")" >> "$(preview_dirty_file)"
    done
    if ((${#files[@]})); then ok "rendered ${#files[@]} page(s) into _site"; fi
  fi
  if (( tunnel )); then
    local log="/tmp/wiki-preview-up-$BOT.log"
    info "starting preview server + tunnel (detached) for $BOT, serving $REPO/_site"
    if (( DRY_RUN )); then
      run env SITE="$REPO/_site" REPO="$REPO" WIKI_BOT="$BOT" WIKI_LOCK_DIR="$LOCK_DIR" WIKI_PREVIEW_PORT="$PREVIEW_PORT" WIKI_PREVIEW_URL="$PREVIEW_URL" WIKI_PREVIEW_BACKEND="${WIKI_PREVIEW_BACKEND:-}" setsid nohup "$PREVIEW_UP"
    else
      # ngrok, if used, inherits the preview.lock fd from preview-up.sh. Fallbacks do not take that lock.
      SITE="$REPO/_site" REPO="$REPO" WIKI_BOT="$BOT" WIKI_LOCK_DIR="$LOCK_DIR" WIKI_PREVIEW_PORT="$PREVIEW_PORT" \
        WIKI_PREVIEW_URL="$PREVIEW_URL" WIKI_PREVIEW_BACKEND="${WIKI_PREVIEW_BACKEND:-}" \
        setsid nohup "$PREVIEW_UP" > "$log" 2>&1 < /dev/null &
      local up_pid=$! code="000" url="" backend=""
      for _ in $(seq 1 45); do
        sleep 2
        if [[ -s "$(preview_url_file)" ]]; then
          url="$(current_preview_url)"
          backend="$(current_preview_backend)"
          code="$(preview_curl_code "$url" "$backend")"
          [[ "$code" == "200" ]] && break
        elif ! kill -0 "$up_pid" 2>/dev/null; then
          break
        fi
      done
      if [[ "$code" != "200" ]]; then
        kill_preview_processes
        die "preview not reachable (HTTP $code); see $log"
      fi
      ok "preview up: $url (HTTP 200, backend ${backend:-unknown}, bot $BOT); stop it with ./wiki.sh preview --stop"
    fi
  fi
}

kill_preview_processes() {
  # Only this bot's pidfiles and --bot=$BOT command lines. Never a generic ssh or another bot's server.
  # Stop file first so a reconnecting supervisor does not bring the tunnel back.
  local stopf="$LOCK_DIR/preview-$BOT.stop" tpid
  : > "$stopf"
  if [[ -f "$LOCK_DIR/preview-$BOT.tunnel.pid" ]]; then
    tpid="$(cat "$LOCK_DIR/preview-$BOT.tunnel.pid" 2>/dev/null || true)"
    if [[ "${tpid:-}" =~ ^[0-9]+$ ]]; then
      kill "$tpid" 2>/dev/null || true
    fi
  fi
  stop_pidfile "$LOCK_DIR/preview-$BOT.ngrok.pid"
  stop_pidfile "$LOCK_DIR/preview-$BOT.tunnel.pid"
  stop_pidfile "$LOCK_DIR/preview-$BOT.http.pid"
  # Matches both `preview-tunnel-ssh --bot=X` and script -c `preview-tunnel-ssh' --bot=X`.
  run pkill -f "preview-tunnel-ssh.*--bot=${BOT}( |$)" || true
  rm -f "$(preview_url_file)" "$stopf"
}

# Stop only this bot's preview. Another bot may keep ngrok or its own fallback running.
preview_stop() {
  info "stopping your preview ($BOT)"
  kill_preview_processes
  if (( ! DRY_RUN )); then
    local _w
    for _w in $(seq 1 10); do
      pgrep -f "preview-tunnel-ssh.*--bot=${BOT}( |$)" >/dev/null 2>&1 || break
      sleep 0.3
    done
    # If we had ngrok, wait a moment for the exclusive lock to drop; if someone else holds it, leave it.
    if lock_is_held preview && [[ "$(lock_owner preview | cut -d' ' -f1)" == "$BOT" ]]; then
      for _w in $(seq 1 10); do lock_is_held preview || break; sleep 0.3; done
      if lock_is_held preview && [[ "$(lock_owner preview | cut -d' ' -f1)" == "$BOT" ]]; then
        warn "ngrok/preview lock still held by: $(lock_owner preview)"
      fi
    fi
  fi
  ok "preview stopped"
}

# ----------------------------------------------------------------------------- save
check_message() {
  local msg="$1" first
  first="${msg%%$'\n'*}"
  (( ${#first} <= MSG_MAX )) || die "commit message first line is ${#first} chars (max $MSG_MAX). Use --any-message to override."
  if [[ "$first" =~ $MSG_SPRINT_RE || "$first" =~ $MSG_TYPED_RE ]]; then return 0; fi
  die "commit message does not follow the convention:
  '$first'
expected one of:
  <course> <year> sprint #<n> [<k>] [note]   e.g. fullstack 2026 sprint #8 3
  <type>: <summary>                         type = landing|page|lab|book|course|infra|fix|style
override with: ./wiki.sh save --any-message \"...\""
}

# Warn when the message's sprint number differs from the staged Sprint Backlog heading.
check_sprint_number() {
  local msg="$1" n_msg n_page f
  [[ "$msg" =~ sprint\ ?#0*([0-9]+) ]] || return 0
  n_msg="${BASH_REMATCH[1]}"
  while IFS= read -r f; do
    [[ "$f" == *backlog-sprint*.qmd ]] || continue
    n_page="$(git show ":$f" | grep -oE 'Sprint#0*[0-9]+' | head -n1 | grep -oE '[1-9][0-9]*$' || true)"
    if [[ -n "$n_page" && "$n_page" != "$n_msg" ]]; then
      warn "message says sprint #$n_msg but $f is at Sprint#$(printf '%02d' "$n_page")"
    fi
  done < <(git diff --cached --name-only)
}

cmd_save() {
  require_identity
  require_not_actions save
  local any=0 msg=""
  while (($#)); do
    case "$1" in
      --any-message) any=1 ;;
      -*) die "save: unknown option $1" ;;
      *) [[ -z "$msg" ]] || die "save: give the message as one quoted argument"; msg="$1" ;;
    esac
    shift
  done
  [[ -n "$msg" ]] || die 'save: missing message, e.g. ./wiki.sh save "fullstack 2026 sprint #8 3"'
  require_session
  (( any )) || check_message "$msg"
  local branch; branch="$(current_branch)"
  # 1) tracked changes (modified + deleted)
  run git add -u -- .
  # 2) new files, minus never-stage paths and the stray CSS
  local new=() f
  while IFS= read -r f; do
    [[ "$f" =~ $STRAY_RE || "$f" =~ $NEVER_STAGE_RE ]] && continue
    new+=("$f")
  done < <(git ls-files --others --exclude-standard)
  if ((${#new[@]})); then run git add -- "${new[@]}"; fi
  if (( ! DRY_RUN )); then
    if git diff --cached --name-only | grep -Eq "$STRAY_RE|$NEVER_STAGE_RE"; then
      git diff --cached --name-only --diff-filter=A | grep -E "$STRAY_RE" | xargs -r git reset -q --
      git diff --cached --name-only | grep -Eq "$NEVER_STAGE_RE" && die "refusing to commit _site/.quarto/_publish.yml"
    fi
    git diff --cached --quiet && die "nothing to commit"
    info "staged:"; git diff --cached --name-status | sed 's/^/    /'
    check_sprint_number "$msg"
  fi
  run git commit -m "$msg"
  run git push -u origin "$branch"
  ok "saved on $branch"
}

# ----------------------------------------------------------------------------- merge
cmd_merge() {
  require_identity
  require_not_actions merge
  require_session
  require_clean
  take_lock publish   # one bot at a time pushes master / publishes
  local branch; branch="$(current_branch)"
  git fetch --quiet origin   # read-only for origin; also in dry-run so the plan is accurate
  if ! git merge-base --is-ancestor "origin/$MAIN_BRANCH" HEAD; then
    info "$MAIN_BRANCH moved since $branch started: rebasing onto origin/$MAIN_BRANCH"
    if (( ! DRY_RUN )); then
      if ! git rebase "origin/$MAIN_BRANCH"; then
        git rebase --abort || true
        die "rebase conflict. Nothing changed: $branch is as before. Resolve by hand (git rebase origin/$MAIN_BRANCH), then rerun merge."
      fi
      printf '%s+ git rebase origin/%s%s\n' "$C_DIM" "$MAIN_BRANCH" "$C_OFF"
    else
      run git rebase "origin/$MAIN_BRANCH"
    fi
    if remote_has_branch "$branch"; then
      run git push --force-with-lease origin "$branch"   # session branch only, never master
    fi
  fi
  if (( IS_WORKTREE )); then
    # master is checked out in the main clone, so push the rebased session straight to it.
    # No force: the remote refuses anything that is not a fast-forward.
    run git push origin "HEAD:refs/heads/$MAIN_BRANCH"
    sync_main_clone
    run git checkout --quiet --detach "origin/$MAIN_BRANCH"   # between sessions: detached at origin/master
    ok "$branch fast-forwarded into $MAIN_BRANCH and pushed; $(basename "$REPO") is now detached at origin/$MAIN_BRANCH"
    return 0
  fi
  run git checkout "$MAIN_BRANCH"
  run git merge --ff-only "origin/$MAIN_BRANCH"
  run git merge --ff-only "$branch"
  run git push origin "$MAIN_BRANCH"
  ok "$branch fast-forwarded into $MAIN_BRANCH and pushed"
}

# ----------------------------------------------------------------------------- publish
# shellcheck disable=SC2120  # called with no args from ship, with "$@" from main
cmd_publish() {
  require_identity
  local all=0
  while (($#)); do
    case "$1" in --all) all=1 ;; *) die "publish: unknown option $1" ;; esac
    shift
  done
  require_clean
  take_lock publish   # one publish at a time (quarto publish gh-pages + tag live)
  git fetch --quiet origin --tags --force   # also in dry-run
  if (( IS_WORKTREE )); then
    [[ "$(current_branch)" == "(detached)" ]] || die "publish runs in a worktree detached at origin/$MAIN_BRANCH (now on $(current_branch)). Use ./wiki.sh ship from a session branch."
    if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$MAIN_BRANCH")" ]]; then
      git merge-base --is-ancestor HEAD "origin/$MAIN_BRANCH" || die "HEAD is not an ancestor of origin/$MAIN_BRANCH"
      run git checkout --quiet --detach "origin/$MAIN_BRANCH"
    fi
  else
    [[ "$(current_branch)" == "$MAIN_BRANCH" ]] || die "publish runs on $MAIN_BRANCH (now on $(current_branch)). Use ./wiki.sh ship from a session branch."
  fi
  local head; head="$(git rev-parse HEAD)"
  (( IS_WORKTREE )) && head="$(git rev-parse "origin/$MAIN_BRANCH")"   # what the checkout above lands on (also in dry-run)
  if (( ! DRY_RUN )); then
    [[ "$head" == "$(git rev-parse "origin/$MAIN_BRANCH")" ]] \
      || die "$MAIN_BRANCH is not equal to origin/$MAIN_BRANCH (pull or push first)"
  fi
  local live="" reason="" full=$all can_share=1
  live="$(git rev-parse -q --verify "refs/tags/$LIVE_TAG^{commit}" || true)"
  (( all )) && { reason="--all requested"; can_share=0; }
  if [[ -z "$live" && $full -eq 0 ]]; then
    die "no '$LIVE_TAG' tag yet: run ./wiki.sh publish --all once to set the baseline"
  fi
  if (( ! full )) && [[ "$ENVIRONMENT" == "github-actions" ]]; then full=1; reason="GitHub Actions has no _site"; can_share=0; fi
  if (( ! full )) && [[ ! -f _site/index.html ]]; then full=1; reason="_site is missing"; fi

  # _site is pushed whole, so what matters is the tree it was built from (the stamp), not the live tag.
  # A session previewed here and fast-forwarded has stamp == HEAD's tree: nothing to render again.
  local base=""
  if (( ! full )); then
    base="$(stamp_tree)"
    if ! git merge-base --is-ancestor "$live" "$head" 2>/dev/null; then full=1; reason="tag $LIVE_TAG is not an ancestor of HEAD"; can_share=0
    elif [[ -z "$base" ]] || ! git cat-file -e "$base" 2>/dev/null; then
      full=1; reason="_site has no render stamp (unknown state)"
    fi
  fi
  if (( ! full )); then
    info "changes between the tree _site was built from (${base:0:8}) and HEAD"
    plan_publish "$base" "$head" 1
    full=$P_FULL; reason="$P_REASON"
  fi

  # Shared build (team rule 12): your _site needs a full render, but maybe another bot already built
  # and published these global files. Then copy its _site in and render only what differs from it.
  if (( full && can_share )) && [[ -n "$SHARED_SITE" ]]; then
    local shared; shared="$(shared_tree)"
    if [[ -z "$shared" ]]; then
      info "no usable shared build in $SHARED_SITE (none yet, or being written)"
    else
      info "your _site needs a FULL render (${reason}); checking the team's shared build: tree ${shared:0:8} (globals $(globals_key "$shared"), HEAD globals $(globals_key "$head"), by $(shared_who))"
      plan_publish "$shared" "$head" 0
      if (( P_FULL )); then
        info "shared build not reusable (${P_REASON})"
        full=1   # keep your own reason
      else
        info "reusing the shared build: its global files match HEAD; only ${#P_PAGES[@]} page(s) and ${#P_COPIES[@]} image(s) differ"
        if shared_site_adopt "$shared"; then base="$shared"; full=0; reason=""
        else full=1; reason="copying the shared build failed"; fi
      fi
    fi
  fi
  local pages=() copies=() navp=0
  if (( ! full )); then pages=("${P_PAGES[@]}"); copies=("${P_COPIES[@]}"); navp=$P_NAVP; fi

  ensure_extensions
  if (( ! full && navp )); then nav_patch || { full=1; reason="nav patch failed"; }; fi
  if (( full )); then
    info "FULL render (${reason})"
    render_full
  else
    mapfile -t pages < <(printf '%s\n' "${pages[@]}" | grep . | sort -u || true)
    local site_changes=""
    site_changes="$(git diff --name-only "$live" "$head" | grep -Ev '^(\.github/|_templates/|wiki\.sh$|tools/|README\.md$|FLOW\.md$|\.gitignore$)' || true)"
    if ((${#pages[@]} == 0 && ${#copies[@]} == 0)) && [[ -n "$site_changes" ]]; then
      info "_site already matches HEAD (built at preview time): publishing it without rendering"
    elif ((${#pages[@]} == 0 && ${#copies[@]} == 0)); then
      if [[ "$live" == "$head" ]]; then ok "nothing to publish: $LIVE_TAG is already at HEAD"; return 0; fi
      info "no page or image changes since $LIVE_TAG; only moving the tag"
      run git tag -f "$LIVE_TAG" "$head"
      run git push -f origin "refs/tags/$LIVE_TAG"
      return 0
    fi
    info "quick publish: ${#pages[@]} page(s), ${#copies[@]} image(s)"
    local p
    for p in "${pages[@]}"; do render_one "$p"; done
    for p in "${copies[@]}"; do run install -D -m 0644 "$p" "_site/$p"; done
  fi
  run "$QUARTO" publish gh-pages --no-render --no-prompt
  if (( ! DRY_RUN )); then
    echo "tree $(git rev-parse "$head^{tree}")" > "$(site_stamp_file)"
    : > "$(preview_dirty_file)"
  fi
  shared_site_save "$head" || warn "could not update the shared build in $SHARED_SITE (left marked pending, so nobody uses it)"
  run git tag -f "$LIVE_TAG" "$head"
  run git push -f origin "refs/tags/$LIVE_TAG"      # force only on the tag, never on a branch
  ok "published ${head:0:8} ($(git log -1 --format=%s "$head")); tag $LIVE_TAG moved"
}

# ----------------------------------------------------------------------------- ship
cmd_ship() {
  require_not_actions ship
  require_session
  local branch; branch="$(current_branch)"
  cmd_merge
  if (( DRY_RUN )); then
    warn "dry-run: the merge above was only planned, so publish is shown as a plan only"
    printf '%s[dry-run]%s ./wiki.sh publish  (render changes since %s, quarto publish gh-pages --no-render, move %s)\n' "$C_YEL" "$C_OFF" "$LIVE_TAG" "$LIVE_TAG"
  else
    # shellcheck disable=SC2119
    cmd_publish
  fi
  run git branch -d "$branch"
  if remote_has_branch "$branch"; then run git push origin --delete "$branch"; fi
  ok "shipped $branch"
}

# ----------------------------------------------------------------------------- status
cmd_status() {
  local b live d
  b="$(current_branch)"
  echo "repo         $REPO$( (( IS_WORKTREE )) && echo "  (worktree; main clone $MAIN_WT)")"
  echo "bot          $BOT$( [[ -z "${WIKI_BOT:-}" ]] && echo "  (from folder name; set WIKI_BOT=<bot>)")"
  echo "environment  $ENVIRONMENT"
  echo "quarto       $("$QUARTO" --version)"
  echo "branch       $b"
  d="$(dirty_files)"
  if [[ -z "$d" ]]; then echo "working tree clean"; else echo "dirty files:"; printf '%s\n' "$d" | sed 's/^/    /'; fi
  live="$(git rev-parse -q --verify "refs/tags/$LIVE_TAG^{commit}" || true)"
  if [[ -z "$live" ]]; then
    echo "live tag     (none yet - run ./wiki.sh publish --all once)"
  else
    echo "live tag     ${live:0:8} $(git log -1 --format='%s (%cd)' --date=format-local:'%F %H:%M' "$live")"
    echo "ahead of live on $MAIN_BRANCH: $(git rev-list --count "$live..$MAIN_BRANCH" 2>/dev/null || echo '?') commit(s)"
    git log --format='    %h %s' "$live..$MAIN_BRANCH" 2>/dev/null | head -n 20
  fi
  echo "_site stamp  $(cut -c1-13 "$(site_stamp_file)" 2>/dev/null || echo none)  (HEAD tree $(git rev-parse --short HEAD^{tree}))"
  if [[ -n "$SHARED_SITE" ]]; then
    local sh; sh="$(shared_tree)"
    if [[ -n "$sh" ]]; then echo "shared build tree ${sh:0:8} globals $(globals_key "$sh") by $(shared_who)  (yours: globals $( [[ -n "$(stamp_tree)" ]] && git cat-file -e "$(stamp_tree)" 2>/dev/null && globals_key "$(stamp_tree)" || echo '?'))"
    else echo "shared build none yet ($SHARED_SITE)"; fi
  fi
  if [[ -s "$(preview_dirty_file)" ]]; then
    echo "pages rendered on top of the stamp: $(cut -d' ' -f1 "$(preview_dirty_file)" | sort -u | tr '\n' ' ')"
  fi
  if has_linked_worktrees; then
    echo "worktrees:"; git worktree list | sed 's/^/    /'
  fi
  local l
  for l in preview publish; do
    if lock_is_held "$l"; then echo "lock $l: held by $(lock_owner "$l")"; else echo "lock $l: free"; fi
  done
  if [[ "$ENVIRONMENT" == "box" ]]; then
    local f bot backend url port code any=0 tpid http_pid ngpid tun_ok http_ok state
    echo "ngrok lock   $(if lock_is_held preview; then echo "held by $(lock_owner preview)"; else echo free; fi)"
    shopt -s nullglob
    for f in "$LOCK_DIR"/preview-*.url; do
      bot="$(awk -F= '/^bot=/{print $2; exit}' "$f")"
      [[ -n "$bot" ]] || bot="$(basename "$f" .url | sed 's/^preview-//')"
      backend="$(awk -F= '/^backend=/{print $2; exit}' "$f")"
      url="$(awk -F= '/^url=/{print $2; exit}' "$f")"
      port="$(awk -F= '/^port=/{print $2; exit}' "$f")"
      code="$(preview_curl_code "$url" "$backend")"
      tpid="$(cat "$LOCK_DIR/preview-$bot.tunnel.pid" 2>/dev/null || true)"
      http_pid="$(cat "$LOCK_DIR/preview-$bot.http.pid" 2>/dev/null || true)"
      if [[ "$backend" == "ngrok" ]]; then
        ngpid="$(cat "$LOCK_DIR/preview-$bot.ngrok.pid" 2>/dev/null || true)"
        [[ "${ngpid:-}" =~ ^[0-9]+$ ]] && tpid="$ngpid"
      fi
      tun_ok=0 http_ok=0
      [[ "${tpid:-}" =~ ^[0-9]+$ ]] && kill -0 "$tpid" 2>/dev/null && tun_ok=1
      [[ "${http_pid:-}" =~ ^[0-9]+$ ]] && kill -0 "$http_pid" 2>/dev/null && http_ok=1
      if (( ! tun_ok )); then
        state="DOWN (tunnel process gone"
        [[ "$code" != "200" ]] && state+=", public URL HTTP $code"
        (( ! http_ok )) && state+=", http.server gone"
        state+=")"
      elif [[ "$code" != "200" ]]; then
        state="STALE (process up, public URL HTTP $code)"
      else
        state="up"
      fi
      echo "preview      bot=$bot backend=${backend:-unknown} port=${port:--} $state HTTP $code $url"
      any=1
    done
    shopt -u nullglob
    (( any )) || echo "preview      down (no per-bot preview.url files)"
  fi
}

# ----------------------------------------------------------------------------- course
cmd_course() {
  require_not_actions course
  local sub="${1:-}"; shift || true
  case "$sub" in
    new|archive) ;;
    *) die "usage: course new <code> <edition> [--from <folder>] | course archive <code> <edition>" ;;
  esac
  local code="${1:-}" ed="${2:-}"
  [[ "$code" =~ ^[a-z]+[0-9]+[a-z]*$ ]] || die "course: code like ifcd0021 (lowercase), got '$code'"
  [[ "$ed" =~ ^[0-9]+(-[0-9]+)?$ ]] || die "course: edition like 27 or 1-27, got '$ed'"
  shift 2
  local from=""
  while (($#)); do
    case "$1" in --from) from="${2:-}"; shift ;; *) die "course: unknown option $1" ;; esac
    shift
  done
  require_session
  python3 - "$sub" "$code" "$ed" "$from" "$DRY_RUN" <<'PY'
import difflib, os, re, sys, datetime
sub, code, ed, src, dry = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] == "1"
NEW = f"{code}-{ed}"
QY = "_quarto.yml"
lines = open(QY, encoding="utf-8").read().split("\n")

def die(m): print(f"ERROR {m}", file=sys.stderr); sys.exit(1)

def training_range():
    s = next((i for i, l in enumerate(lines) if re.match(r'\s*- id: "?training"?\s*$', l)), None)
    if s is None: die('no sidebar with id "training" in _quarto.yml')
    ind = len(lines[s]) - len(lines[s].lstrip())
    e = s + 1
    while e < len(lines) and (lines[e].strip() == "" or len(lines[e]) - len(lines[e].lstrip()) > ind):
        e += 1
    return s, e

def sections(s, e):
    """[(start, end_exclusive, label, [paths])] for each '- section:' in the training sidebar."""
    out = []
    i = s
    while i < e:
        m = re.match(r'(\s*)- section: "?(.*?)"?\s*$', lines[i])
        if m:
            ind = len(m.group(1)); j = i + 1; paths = []
            while j < e and lines[j].strip() and len(lines[j]) - len(lines[j].lstrip()) > ind:
                pm = re.match(r'\s*- ([^\s:]+\.qmd)\s*$', lines[j])
                if pm: paths.append(pm.group(1))
                j += 1
            out.append((i, j, m.group(2), paths, ind))
            i = j
        else:
            i += 1
    return out

def show_diff(path, old, new):
    sys.stdout.writelines(difflib.unified_diff(old, new, f"a/{path}", f"b/{path}"))

def write(path, text):
    if dry:
        print(f"[dry-run] would write {path} ({text.count(chr(10))} lines)")
        return
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
    print(f"  wrote {path}")

s, e = training_range()
secs = sections(s, e)
arch = next((x for x in secs if x[2].strip().lower() == "archived"), None)

if sub == "new":
    if os.path.exists(NEW): die(f"{NEW}/ already exists")
    if any(p.startswith(NEW + "/") for x in secs for p in x[3]): die(f"{NEW} already in _quarto.yml")
    if not src:
        for x in secs:
            for p in x[3]:
                folder = p.split("/")[0]
                if re.match(rf"^{re.escape(code)}-\d", folder) and folder != NEW:
                    src = folder; break
            if src: break
    if src and not os.path.isdir(src): die(f"--from folder {src} not found")
    print(f"==> new edition {NEW} " + (f"scaffolded from {src}/" if src else "(no previous edition found; minimal pages)"))
    U, PU = NEW.upper(), (src.upper() if src else "")
    names = {"official": f"{code}-{ed}.qmd", "sprint": f"{code}-backlog-sprint-{ed}.qmd",
             "product": f"{code}-backlog-product-{ed}.qmd", "deliveries": f"{code}-deliveries-{ed}.qmd"}
    prev = {}
    if src:
        for f in sorted(os.listdir(src)):
            if not f.endswith(".qmd"): continue
            if f == f"{src}.qmd": prev["official"] = f
            elif "backlog-sprint" in f: prev["sprint"] = f
            elif "backlog-product" in f: prev["product"] = f
            elif "deliveries" in f: prev["deliveries"] = f
    today = datetime.date.today().isoformat()
    note = f"<!-- Scaffolded by wiki.sh course new from {src or 'nothing'} on {today}: fill in every TODO. -->"

    def fix_common(t):
        if src:
            t = t.replace(PU, U)                       # titles: IFCD0021-26 -> IFCD0021-27
            for role, f in prev.items():               # internal links to the 4 pages
                t = t.replace(f"/{src}/{f}", f"/{NEW}/{names[role]}")
        return t

    def split_fm(t):
        m = re.match(r"(---\n.*?\n---\n)(.*)", t, re.S)
        return (m.group(1), m.group(2)) if m else ("", t)

    def table_parts(body):
        ls = body.split("\n")
        for i in range(len(ls) - 1):
            if ls[i].startswith("|") and re.match(r"^\|\s*:?-{2,}", ls[i + 1]):
                ncol = ls[i].count("|") - 1
                cap = next((l for l in ls[i:] if l.startswith(": ") and "table" in l), "")
                return ls[i], ls[i + 1], ncol, cap
        return "| # | Day | Date | Topics | Details Topics |", "| -- | -- | -- | -- | -- |", 5, ""

    def empty_row(ncol, first=("**#01**", "01", "dd/mm/yy")):
        cells = list(first)[:ncol] + [" "] * max(0, ncol - len(first))
        return "| " + " | ".join(cells) + " |"

    def minimal(role):
        title = {"official": "Official Docs", "sprint": "Sprint Backlog", "product": "Product Backlog",
                 "deliveries": "Calendar & Deliveries"}[role]
        cat = "backlog" if role in ("sprint", "product") else "training"
        return f'---\ntitle: "{U} {title}"\ncategories: [{code}, {cat}]\n---\n\n{note}\n\n# TODO\n'

    out = {}
    for role in ("official", "sprint", "product", "deliveries"):
        if role not in prev:
            out[role] = minimal(role); continue
        fm, body = split_fm(open(os.path.join(src, prev[role]), encoding="utf-8").read())
        fm = fix_common(fm)
        if role == "official":
            body = re.sub(r"(?m)^(- Número de registre:).*$", r"\1 **TODO**", body)
            body = re.sub(r"(?m)^(- Període:).*$", r"\1 **TODO** (dd/mm/yyyy-dd/mm/yyyy)", body)
            body = fix_common(body)
        elif role == "sprint":
            ls = body.split("\n")
            h = next((i for i, l in enumerate(ls) if l.startswith("## ")), len(ls))
            hdr, sep, ncol, cap = table_parts(body)
            last_cap = max((i for i, l in enumerate(ls) if l.startswith(": ") and "table" in l), default=None)
            tail = ls[last_cap + 1:] if last_cap is not None else []
            cap = re.sub(r"^: .*? table", ": Backlog course Sprint#01 table", cap) if cap else ": Backlog course Sprint#01 table"
            body = "\n".join(ls[:h] + ["##  ``Sprint#01: TODO`` (TODO dates)", "", hdr, sep, empty_row(ncol), "", cap] + tail)
        elif role == "product":
            ls = body.split("\n")
            h1 = next((i for i, l in enumerate(ls) if l.startswith("# ")), None)
            keep = ls[:h1 + 1] if h1 is not None else ls[:next((i for i, l in enumerate(ls) if l.startswith("## ")), len(ls))]
            hdr, sep, ncol, cap = table_parts(body)
            cap = re.sub(r"^: .*? table", ": Backlog course Month YYYY table", cap) if cap else ": Backlog course Month YYYY table"
            link = f"/{NEW}/{names['product']}#month-yyyy"
            body = "\n".join(keep + ["", '::: {.callout-tip title="Months"}', f"- [Month YYYY]({link})", "", ":::", "",
                                     "::: {.column-page-right}", "", "## Month YYYY", "", "<details>",
                                     "<summary>Month YYYY</summary>", "", hdr, sep, empty_row(ncol), "", cap, "",
                                     "</details>", "", ":::", ""])
        elif role == "deliveries":
            body = re.sub(r"(?m)^(- \*\*Inici-final de curs\*\*:).*$", r"\1 TODO (dd/mm/yyyy-dd/mm/yyyy)", body)
            # only the edition's calendar picture (e.g. /images/ifcd0021-26/calendar.png), not the header image
            body = re.sub(rf"(?mi)^!\[[^\]]*\]\(/images/{re.escape(src)}/[^)]*calendar[^)]*\).*$",
                          f"<!-- TODO calendar image, e.g. ![Calendar](/images/{NEW}/calendar.png) -->", body)
            body = re.sub(r"(?m)^# Calendar 20\d\d[ \t]*$", "# Calendar TODO-year", body)
            body = fix_common(body)
        out[role] = fm + "\n" + note + "\n" + body.lstrip("\n")
    for role in ("official", "sprint", "product", "deliveries"):
        write(f"{NEW}/{names[role]}", out[role])
    # _quarto.yml: new section at the top of the training sidebar (current courses are above "Archived")
    anchor = next((i for i in range(s, e) if re.match(r'\s*- text: "?Training Courses"?\s*$', lines[i])), None)
    if anchor is None: die('no \'- text: "Training Courses"\' in the training sidebar')
    ins = anchor + 1
    if re.match(r'\s*- text: "?---"?\s*$', lines[ins]): ins += 1
    ind = " " * (len(lines[anchor]) - len(lines[anchor].lstrip()))
    block = [f'{ind}- section: "{U} Docs"', f"{ind}  contents:"] + \
            [f"{ind}    - {NEW}/{names[r]}" for r in ("official", "sprint", "product", "deliveries")] + [f'{ind}- text: "---"']
    newlines = lines[:ins] + block + lines[ins:]

elif sub == "archive":
    tgt = next((x for x in secs if any(p.startswith(NEW + "/") for p in x[3])), None)
    if tgt is None: die(f"{NEW} has no section in the training sidebar")
    if arch is None: die('no "Archived" section marker in the training sidebar')
    if tgt[0] > arch[0]:
        print(f"==> {NEW} ('{tgt[2]}') is already below 'Archived'; nothing to do"); sys.exit(0)
    a, b = tgt[0], tgt[1]
    if b < len(lines) and re.match(r'\s*- text: "?---"?\s*$', lines[b]): b += 1   # its divider
    block = lines[a:b]
    rest = lines[:a] + lines[b:]
    # re-find the Archived marker (+ its 'contents:' + divider) in the shortened file
    k = next(i for i, l in enumerate(rest) if re.match(r'\s*- section: "?Archived"?\s*$', l))
    k += 1
    while k < len(rest) and re.match(r"\s*contents:\s*$", rest[k]): k += 1
    if k < len(rest) and re.match(r'\s*- text: "?---"?\s*$', rest[k]): k += 1
    if not re.match(r'\s*- text: "?---"?\s*$', block[-1]):
        block = block + [re.match(r"(\s*)", block[0]).group(1) + '- text: "---"']
    newlines = rest[:k] + block + rest[k:]
    print(f"==> archiving {NEW} ('{tgt[2]}'): moved below 'Archived' in the Training sidebar; pages and URLs stay where they are")
    if os.path.exists("index.qmd"):
        refs = [f"    index.qmd:{i+1}: {l.strip()[:110]}" for i, l in enumerate(open("index.qmd", encoding="utf-8")) if f"/{NEW}/" in l]
        if refs:
            print(f"note: the landing (index.qmd) still links {NEW} in {len(refs)} line(s); update it by hand if needed:")
            print("\n".join(refs))

show_diff(QY, [l + "\n" for l in lines], [l + "\n" for l in newlines])
if dry:
    print(f"[dry-run] would update {QY}")
else:
    open(QY, "w", encoding="utf-8").write("\n".join(newlines))
    print(f"  updated {QY}")
print("==> _quarto.yml changed: preview with ./wiki.sh preview --all; the next publish will be a full render")
PY
}

# ----------------------------------------------------------------------------- main
main() {
  local args=() a
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) args+=("$a") ;;
    esac
  done
  ((${#args[@]})) || { usage; exit 1; }
  local cmd="${args[0]}"
  case "$cmd" in
    start|preview|save|merge|publish|ship|status|course) ;;
    *) usage >&2; die "unknown command: $cmd" ;;
  esac
  preflight
  if (( DRY_RUN )); then warn "dry-run: nothing will be changed"; fi
  "cmd_$cmd" "${args[@]:1}"
}

main "$@"
