#!/usr/bin/env bash
# pokegents installer — browser dashboard, no shell rc mutation.
set -euo pipefail

POKEGENTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POKEGENTS_DATA="${POKEGENTS_DATA:-$HOME/.pokegents}"
INSTALL_CWD="${POKEGENTS_INSTALL_CWD:-$PWD}"
SHIM_DIR="${POKEGENTS_SHIM_DIR:-$HOME/.local/bin}"
SHIM_PATH="$SHIM_DIR/pokegents"
COMPAT_SHIM_PATH="$SHIM_DIR/pokegent"

log() { printf '%s\n' "$*"; }
warn() { printf '⚠ %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

log "Installing pokegents from $POKEGENTS_ROOT"
log "Data directory: $POKEGENTS_DATA"
log "Default project cwd: $INSTALL_CWD"
log ""

if ! have python3; then
  echo "python3 is required for the installer" >&2
  exit 1
fi

mkdir -p "$POKEGENTS_DATA"/{profiles,projects,roles,history,running,status,messages,logs,grid-profiles,activity,activity-lastread,ephemeral,ephemeral-pending,agents}
log "✓ Data directories ready"

if [[ ! -f "$POKEGENTS_DATA/config.json" ]]; then
  cat > "$POKEGENTS_DATA/config.json" <<JSON
{
  "port": 7834,
  "dashboard_open_mode": "browser",
  "default_interface": "chat",
  "default_backend": "claude",
  "default_project": "current",
  "default_role": "builder",
  "skip_permissions": true,
  "iterm2_restore_profile": "Default",
  "editor_open_command": "code {path}",
  "browser_open_command": "open -a \"Google Chrome\" {url}"
}
JSON
  log "✓ Default config installed"
else
  log "· Config already exists; onboarding can repair preferences"
fi

if [[ ! -f "$POKEGENTS_DATA/backends.json" ]]; then
  cat > "$POKEGENTS_DATA/backends.json" <<JSON
{
  "version": 2,
  "backends": {
    "claude": {
      "name": "Claude",
      "type": "claude-acp",
      "default": true,
      "default_model": "sonnet-4-6",
      "models": {
        "sonnet-4-6": { "name": "Sonnet 4.6", "model": "claude-sonnet-4-6" },
        "opus-4-7": { "name": "Opus 4.7", "model": "claude-opus-4-7" },
        "opus-4-6": { "name": "Opus 4.6 (1M)", "model": "claude-opus-4-6[1m]" },
        "haiku-4-5": { "name": "Haiku 4.5", "model": "haiku" }
      }
    },
    "codex": {
      "name": "Codex",
      "type": "codex-acp",
      "default_model": "default",
      "models": {
        "default": { "name": "Provider default", "model": "" }
      },
      "env": {}
    }
  }
}
JSON
  log "✓ Default provider backends installed"
fi

install_role() {
  local name="$1" title="$2" emoji="$3" prompt="$4"
  local path="$POKEGENTS_DATA/roles/$name.json"
  [[ -f "$path" ]] && return 0
  cat > "$path" <<JSON
{
  "title": $(json_escape "$title"),
  "emoji": $(json_escape "$emoji"),
  "system_prompt": $(json_escape "$prompt"),
  "skip_permissions": null
}
JSON
}

install_role lead "Lead" "🧭" "You are the lead agent for this project. Hold the big picture: decompose work, make architectural calls, and write specs before code gets written. Use the brainstorming skill to produce design specs in \`docs/superpowers/specs/\`, and the writing-plans skill to produce implementation plans in \`docs/superpowers/plans/\`. Delegate execution to the Builder via MCP messaging; do not write production code yourself unless the change is trivially small. Push back on scope creep — your job is to keep the project coherent."
install_role builder "Builder" "🔨" "You are the builder agent. Implement features and fixes from the Lead's specs and plans. Use test-driven-development and verification-before-completion skills rigorously: write tests first, run them, and never claim done without verification output. Follow existing codebase patterns. When you finish a task, report changed files and the exact verification commands you ran. Coordinate via MCP before editing shared hotspots and never revert another agent's work without checking with them."
install_role reviewer "Reviewer" "🔍" "You are the reviewer agent. Read code adversarially — look for over-engineering, dead code, premature abstraction, security holes, and inconsistency with existing patterns. Use the simplify and security-review skills. Be specific and actionable: cite file:line and propose the concrete change. Rank findings by severity. You read code; you do not run the app — that is QA's job."
install_role qa "QA" "🧪" "You are the QA agent. Verify behavior end-to-end by running the app, not by reading code. Exercise the golden path AND edge cases. Hunt for regressions in adjacent features. Read logs, network traffic, and UI state. Report bugs with reproduction steps, expected vs. actual behavior, and severity. You do not fix bugs — you find them and hand off to Builder or Debugger."
install_role designer "Designer" "🎨" "You are the designer agent. Own UI and UX decisions: layouts, mockups, visual hierarchy, motion, accessibility. Use Claude Preview or Chrome MCP to test visual changes in a real browser. Touch styling and markup; coordinate with Builder for anything that requires logic changes. Consider responsive behavior and theme contrast. When proposing a design, show the alternatives you considered and why you picked the one you did."
install_role researcher "Researcher" "📚" "You are the researcher agent. Take on multi-hour investigations: external docs, web research, deep codebase archaeology, cross-cutting analysis. Output structured summaries with citations and evidence — never recommend changes the evidence doesn't support. You are distinct from the Explore subagent: Explore is for \"where is X?\" lookups inside one conversation; you handle questions whose findings need to outlive a single agent's context."
install_role debugger "Debugger" "🐛" "You are the debugger agent. Use the systematic-debugging skill. Your sole focus is root cause — not workarounds. When invoked, reproduce the issue, isolate variables, and identify what is actually broken. Read logs, traces, and instrumentation. Report root cause and a proposed fix; hand the fix to Builder unless explicitly asked to ship it yourself. Bias toward \"why is this happening?\" over \"how do I make this go away?\""
log "✓ Default roles ready"

if [[ ! -f "$POKEGENTS_DATA/projects/current.json" ]]; then
  cat > "$POKEGENTS_DATA/projects/current.json" <<JSON
{
  "title": $(json_escape "$(basename "$INSTALL_CWD")"),
  "color": [100, 180, 255],
  "iterm2_profile": "",
  "cwd": $(json_escape "$INSTALL_CWD"),
  "add_dirs": [],
  "context_prompt": ""
}
JSON
  log "✓ Default project installed: current → $INSTALL_CWD"
else
  log "· Default project already exists"
fi

chmod +x "$POKEGENTS_ROOT"/hooks/*.sh 2>/dev/null || true

mkdir -p "$SHIM_DIR"
cat > "$SHIM_PATH" <<SHIM
#!/usr/bin/env zsh
set -e
export POKEGENTS_ROOT=$(printf '%q' "$POKEGENTS_ROOT")
export POKEGENTS_DATA=\${POKEGENTS_DATA:-$(printf '%q' "$POKEGENTS_DATA")}
if [[ ! -f "\$POKEGENTS_ROOT/pokegent.sh" ]]; then
  echo "pokegents install is missing pokegent.sh at \$POKEGENTS_ROOT" >&2
  exit 1
fi
source "\$POKEGENTS_ROOT/pokegent.sh"
if [[ \$# -eq 0 ]]; then
  pokegent dashboard open
elif [[ "\$1" == "launch" ]]; then
  shift
  pokegent "\$@"
else
  pokegent "\$@"
fi
SHIM
chmod +x "$SHIM_PATH"
ln -sf "$SHIM_PATH" "$COMPAT_SHIM_PATH"
log "✓ CLI shim installed: $SHIM_PATH"
log "✓ Compatibility alias installed: $COMPAT_SHIM_PATH"

# Developer/source fallback: build dashboard only when explicitly requested.
if [[ ! -x "$POKEGENTS_ROOT/dashboard/pokegents-dashboard" || ! -d "$POKEGENTS_ROOT/dashboard/web/dist" || ! -d "$POKEGENTS_ROOT/dashboard/acp-fork/dist" ]]; then
  if [[ "${POKEGENTS_DEV_BUILD:-}" == "1" ]] && have go && have npm; then
    log ""
    log "Building dashboard for source checkout..."
    (cd "$POKEGENTS_ROOT/dashboard" && CGO_CFLAGS="-DSQLITE_ENABLE_FTS5" go build -o pokegents-dashboard .) && log "✓ Dashboard server built"
    "$POKEGENTS_ROOT/scripts/fetch-pokesprite-assets.sh" && (cd "$POKEGENTS_ROOT/dashboard/web" && npm ci --silent && npm run build) && log "✓ Dashboard web built"
    (cd "$POKEGENTS_ROOT/dashboard/acp-fork" && npm ci --silent && if [[ -f tsconfig.json ]]; then npm run build; else test -f dist/index.js; fi) && log "✓ ACP adapter ready"
  else
    warn "Dashboard binary/assets are missing. Install from a release artifact, or run with POKEGENTS_DEV_BUILD=1 for source builds."
  fi
fi

log ""
log "Install complete. No shell rc files were modified."
if [[ ":$PATH:" != *":$SHIM_DIR:"* ]]; then
  log "Add $SHIM_DIR to PATH later if desired, or run directly:"
  log "  $SHIM_PATH"
fi

log "Open the browser dashboard with:"
log "  $SHIM_PATH dashboard open"
log ""
log "If the server is not already running, start it first with:"
log "  $SHIM_PATH dashboard start"
