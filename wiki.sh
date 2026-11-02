#!/usr/bin/env bash
# wiki.sh - one deterministic workflow for albertprofe.dev (Quarto wiki, repo AlbertProfe/wiki)
#
# Same script for every publisher: Grok Bot's box, Albert's Linux VM and the GitHub Action.
# Run `./wiki.sh -h` for the command reference.
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
if [[ -d "$HOME/.local/bin" ]]; then PATH="$HOME/.local/bin:$PATH"; fi

DRY_RUN=0
ENVIRONMENT=""
REPO=""
GIT_DIR_ABS=""

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

Session (box or Albert's VM):
  start                       pull master, create session/YYYY-MM-DD-N (next free N)
  preview [--all] [--tunnel] [files.qmd...]   (preview --stop: stop server + ngrok)
                              render given .qmd files (default: .qmd changed vs master,
                              committed + uncommitted + untracked) into _site;
                              --all = full render; --tunnel = serve _site on ngrok (box only)
  save [--any-message] "msg"  stage content changes (never _site/.quarto/stray CSS),
                              check the message convention, commit, push the session branch
  merge                       rebase session onto origin/master if master moved,
                              fast-forward master, push master (never force)
  publish [--all]             on master: render what changed since the last publish,
                              quarto publish gh-pages --no-render, move tag 'live'.
                              Escalates to a full render automatically when needed.
  ship                        merge + publish + delete the session branch (local + remote)
  status                      branch, dirty files, quarto, environment, commits ahead of live,
                              preview/ngrok state

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
  command -v "$QUARTO" >/dev/null 2>&1 || die "quarto not found on PATH (need $QUARTO_REQUIRED; never install another version)"
  local v; v="$("$QUARTO" --version 2>/dev/null | tr -d '[:space:]')"
  [[ "$v" == "$QUARTO_REQUIRED" ]] || die "quarto is $v, required $QUARTO_REQUIRED. Do not upgrade; fix PATH instead."
  detect_env
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

site_stamp_file()   { echo "$GIT_DIR_ABS/wiki-site-stamp"; }      # commit that _site reflects
preview_dirty_file(){ echo "$GIT_DIR_ABS/wiki-preview-dirty"; }   # pages rendered from session branches

# ----------------------------------------------------------------------------- start
cmd_start() {
  require_not_actions start
  require_clean
  run git checkout "$MAIN_BRANCH"
  run git pull --ff-only origin "$MAIN_BRANCH"
  local day n=1 name
  day="$(date +%F)"
  git fetch --quiet origin || warn "fetch failed; checking remote branches with ls-remote only"
  while :; do
    name="session/$day-$n"
    if git show-ref --verify --quiet "refs/heads/$name" || remote_has_branch "$name"; then
      n=$((n + 1)); continue
    fi
    break
  done
  run git checkout -b "$name"
  ok "session branch $name ready"
}

# ----------------------------------------------------------------------------- preview
changed_qmd_vs_main() {
  {
    git diff --name-only "$MAIN_BRANCH"...HEAD 2>/dev/null || true
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
      --stop)
        info "stopping preview server + ngrok"
        run pkill -f "http.server $PREVIEW_PORT" || true
        run pkill -f "ngrok http $PREVIEW_PORT" || true
        ok "preview stopped"; return 0 ;;
      --all) all=1 ;;
      -*) die "preview: unknown option $1" ;;
      *) files+=("$1") ;;
    esac
    shift
  done
  ensure_extensions
  if (( all )); then
    info "full render into _site (about 10 minutes)"
    run "$QUARTO" render
    (( DRY_RUN )) || git rev-parse HEAD > "$(site_stamp_file)"
    [[ "$(current_branch)" == "$MAIN_BRANCH" ]] || { (( DRY_RUN )) || echo "__FULL__" >> "$(preview_dirty_file)"; }
  else
    if ((${#files[@]} == 0)); then
      mapfile -t files < <(changed_qmd_vs_main)
      ((${#files[@]})) || info "no changed .qmd files vs $MAIN_BRANCH; nothing to render"
    fi
    if git diff --name-only "$MAIN_BRANCH"...HEAD -- _quarto.yml | grep -q . || ! git diff --quiet HEAD -- _quarto.yml; then
      warn "_quarto.yml changed: sidebar/nav only update with ./wiki.sh preview --all"
    fi
    local f
    for f in "${files[@]}"; do
      [[ -f "$f" && "$f" == *.qmd ]] || die "not a .qmd file: $f"
      render_one "$f"
      if (( ! DRY_RUN )) && [[ "$(current_branch)" != "$MAIN_BRANCH" ]]; then
        echo "$f" >> "$(preview_dirty_file)"
      fi
    done
    if ((${#files[@]})); then ok "rendered ${#files[@]} page(s) into _site"; fi
  fi
  if (( tunnel )); then
    [[ "$ENVIRONMENT" == "box" ]] || die "--tunnel only works on the box"
    [[ -x "$PREVIEW_UP" ]] || die "preview script not found: $PREVIEW_UP"
    info "starting preview server + ngrok (detached)"
    if (( DRY_RUN )); then
      run env SITE="$REPO/_site" setsid nohup "$PREVIEW_UP"
    else
      SITE="$REPO/_site" setsid nohup "$PREVIEW_UP" > /tmp/wiki-preview-up.log 2>&1 < /dev/null &
      local code="000"
      for _ in $(seq 1 15); do
        sleep 2
        code="$(curl -s -o /dev/null -w '%{http_code}' -H 'ngrok-skip-browser-warning: 1' "$PREVIEW_URL/" || true)"
        [[ "$code" == "200" ]] && break
      done
      [[ "$code" == "200" ]] || die "preview not reachable (HTTP $code); see /tmp/wiki-preview-up.log"
      ok "preview up: $PREVIEW_URL (HTTP 200)"
    fi
  fi
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
  [[ "$(current_branch)" == "$MAIN_BRANCH" ]] || die "publish runs on $MAIN_BRANCH (now on $(current_branch)). Use ./wiki.sh ship from a session branch."
  require_clean
  git fetch --quiet origin --tags --force   # also in dry-run
  local head; head="$(git rev-parse HEAD)"
  if (( ! DRY_RUN )); then
    [[ "$head" == "$(git rev-parse "origin/$MAIN_BRANCH")" ]] \
      || die "$MAIN_BRANCH is not equal to origin/$MAIN_BRANCH (pull or push first)"
  fi
  local live="" reason="" full=$all
  live="$(git rev-parse -q --verify "refs/tags/$LIVE_TAG^{commit}" || true)"
  (( all )) && reason="--all requested"
  if [[ -z "$live" && $full -eq 0 ]]; then
    die "no '$LIVE_TAG' tag yet: run ./wiki.sh publish --all once to set the baseline"
  fi
  if (( ! full )) && [[ "$ENVIRONMENT" == "github-actions" ]]; then full=1; reason="GitHub Actions has no _site"; fi
  if (( ! full )) && [[ ! -f _site/index.html ]]; then full=1; reason="_site is missing"; fi

  local base="" stamp=""
  if (( ! full )); then
    stamp="$(cat "$(site_stamp_file)" 2>/dev/null || true)"
    if ! git merge-base --is-ancestor "$live" HEAD 2>/dev/null; then full=1; reason="tag $LIVE_TAG is not an ancestor of HEAD"
    elif [[ -z "$stamp" ]] || ! git merge-base --is-ancestor "$stamp" HEAD 2>/dev/null; then
      full=1; reason="_site has no stamp from a $MAIN_BRANCH render (unknown state)"
    else
      # diff from the older of (live, stamp): covers commits published elsewhere and not yet in this _site
      if git merge-base --is-ancestor "$stamp" "$live"; then base="$stamp"; else base="$live"; fi
    fi
  fi

  local pages=() copies=() st p1 p2
  if (( ! full )); then
    info "changes since ${base:0:8} ($(git log -1 --format=%s "$base"))"
    while IFS=$'\t' read -r st p1 p2; do
      case "$st" in
        M*|T*)
          case "$p1" in
            _quarto.yml|_metadata.yml|*.scss|*.css|CNAME|_extensions/*) full=1; reason="$p1 changed" ;;
            _freeze/*|_templates/*|.github/*|wiki.sh|README.md|FLOW.md|.gitignore) ;;
            _*) ;;
            *.qmd) pages+=("$p1") ;;
            images/*) copies+=("$p1") ;;
            *) full=1; reason="$p1 changed (not a page or image)" ;;
          esac ;;
        A*)
          case "$p1" in
            *.qmd) [[ "$p1" == _* ]] || { full=1; reason="page added: $p1"; } ;;
            images/*) copies+=("$p1") ;;
            _freeze/*|_templates/*|.github/*|wiki.sh|README.md|FLOW.md) ;;
            *) full=1; reason="file added: $p1" ;;
          esac ;;
        D*) case "$p1" in _freeze/*|.github/*) ;; *) full=1; reason="file deleted: $p1" ;; esac ;;
        R*|C*) full=1; reason="file renamed: $p1 -> $p2" ;;
        *) full=1; reason="unknown change $st $p1" ;;
      esac
      if (( full )); then break; fi
    done < <(git diff --name-status -M "$base" HEAD)
    # pages rendered from session branches into _site must be re-rendered from master
    if (( ! full )) && [[ -s "$(preview_dirty_file)" ]]; then
      local f
      while IFS= read -r f; do
        if [[ "$f" == "__FULL__" ]]; then full=1; reason="a full preview render happened on a session branch"; break; fi
        if [[ -f "$f" ]]; then pages+=("$f"); else full=1; reason="previewed page no longer on $MAIN_BRANCH: $f"; break; fi
      done < "$(preview_dirty_file)"
    fi
  fi

  ensure_extensions
  if (( full )); then
    info "FULL render (${reason}) - about 10 minutes"
    run "$QUARTO" render
  else
    mapfile -t pages < <(printf '%s\n' "${pages[@]}" | grep . | sort -u || true)
    if ((${#pages[@]} == 0 && ${#copies[@]} == 0)); then
      if [[ "$live" == "$head" ]]; then ok "nothing to publish: $LIVE_TAG is already at HEAD"; return 0; fi
      info "no page or image changes since $LIVE_TAG; only moving the tag"
      run git tag -f "$LIVE_TAG" HEAD
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
    echo "$head" > "$(site_stamp_file)"
    : > "$(preview_dirty_file)"
  fi
  run git tag -f "$LIVE_TAG" HEAD
  run git push -f origin "refs/tags/$LIVE_TAG"      # force only on the tag, never on a branch
  ok "published ${head:0:8} ($(git log -1 --format=%s HEAD)); tag $LIVE_TAG moved"
}

# ----------------------------------------------------------------------------- ship
cmd_ship() {
  require_not_actions ship
  require_session
  local branch; branch="$(current_branch)"
  cmd_merge
  if (( DRY_RUN )); then
    warn "dry-run: still on $branch, so publish is shown as a plan only"
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
  echo "repo         $REPO"
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
  echo "_site stamp  $(cut -c1-8 "$(site_stamp_file)" 2>/dev/null || echo none)"
  if [[ -s "$(preview_dirty_file)" ]]; then
    echo "previewed from session branches (re-rendered on next publish): $(sort -u "$(preview_dirty_file)" | tr '\n' ' ')"
  fi
  if [[ "$ENVIRONMENT" == "box" ]]; then
    local code
    if pgrep -f "ngrok http" >/dev/null 2>&1; then
      code="$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H 'ngrok-skip-browser-warning: 1' "$PREVIEW_URL/" || true)"
      echo "ngrok        up (HTTP $code) $PREVIEW_URL"
    else
      echo "ngrok        down"
    fi
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
