#!/usr/bin/env bash
# =============================================================================
# helpers.sh — Shared functions for Nexus justfile recipes
# =============================================================================
# Source this at the top of any recipe that needs service resolution, spinners,
# or cached docker state.
#
#   source "{{ scripts_dir }}/helpers.sh"
#
# Provides:
#   resolve_service <name> <services_dir>   → sets SVC_NAMES, SVC_COMPOSE
#   spin <pid> <message>                    → braille spinner on stderr
#   spin_while <message> <cmd> [args...]    → run cmd with spinner, return its exit code
#   cache_docker_ps                         → populate DOCKER_PS_* associative arrays
#   log_step <message>                      → dim step prefix
#   log_ok <message>                        → green ✓ message
#   log_err <message>                       → red ✗ message
#   log_warn <message>                      → yellow ⚠ message
# =============================================================================

# ── ANSI ─────────────────────────────────────────────────────────────────────
readonly _RED=$'\033[31m'
readonly _GREEN=$'\033[32m'
readonly _YLW=$'\033[33m'
readonly _BLUE=$'\033[34m'
readonly _DIM=$'\033[2m'
readonly _BOLD=$'\033[1m'
readonly _RST=$'\033[0m'

# ── Logging ──────────────────────────────────────────────────────────────────

log_step()  { printf '%b→%b %s\n' "$_DIM" "$_RST" "$*"; }
log_ok()    { printf '%b✓%b %s\n' "$_GREEN" "$_RST" "$*"; }
log_err()   { printf '%b✗%b %s\n' "$_RED" "$_RST" "$*" >&2; }
log_warn()  { printf '%b⚠%b %s\n' "$_YLW" "$_RST" "$*"; }

# ── Service resolution ──────────────────────────────────────────────────────
# Usage: resolve_service <service_name> <services_dir>
# Sets:  SVC_COMPOSE  — full path to compose.yaml
#        SVC_NAMES    — space-separated service names from compose
# Exits with error if compose.yaml not found.

resolve_service() {
    local svc="$1" sdir="$2"
    SVC_COMPOSE="${sdir}/${svc}/compose.yaml"
    if [[ ! -f "$SVC_COMPOSE" ]]; then
        log_err "Service '${svc}' not found"
        exit 1
    fi
    SVC_NAMES=$(yq -r '.services | keys | .[]' "$SVC_COMPOSE")
}

# ── Docker PS cache ──────────────────────────────────────────────────────────
# Populates associative arrays from a single `docker ps -a` call:
#   DOCKER_STATE[container_name]  = running | exited | created | ...
#   DOCKER_STATUS[container_name] = "Up 3 hours (healthy)" | "Exited (0) ..."
#   DOCKER_PROJECT[container_name] = compose project label or ""
#
# Call once at the top of a recipe, then do O(1) lookups.

declare -gA DOCKER_STATE=() DOCKER_STATUS=() DOCKER_PROJECT=()
_DOCKER_PS_CACHED=false

cache_docker_ps() {
    if $_DOCKER_PS_CACHED; then return 0; fi
    local line name state status project
    while IFS='|' read -r name state status project; do
        [[ -z "$name" ]] && continue
        DOCKER_STATE["$name"]="$state"
        DOCKER_STATUS["$name"]="$status"
        DOCKER_PROJECT["$name"]="$project"
    done < <(docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null)
    _DOCKER_PS_CACHED=true
}

# ── Braille spinner ──────────────────────────────────────────────────────────
# spin <pid> <message>
#   Displays a rotating braille spinner on stderr while <pid> is alive.
#   No-op if stderr is not a terminal (CI / piped).
#
# spin_while <message> <cmd> [args...]
#   Runs <cmd> in background, attaches spinner, returns cmd's exit code.
#   Captures cmd's stdout into SPIN_OUTPUT (available after call).

readonly _SPIN_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spin() {
    local pid="$1" msg="$2"
    # Skip if not a terminal
    [[ -t 2 ]] || { wait "$pid" 2>/dev/null; return $?; }

    local i=0 len=${#_SPIN_CHARS}
    # Hide cursor
    printf '\033[?25l' >&2
    trap 'printf "\033[?25h" >&2' RETURN

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b %s' "$_BLUE" "${_SPIN_CHARS:i%len:1}" "$_RST" "$msg" >&2
        ((i++)) || true
        sleep 0.08
    done

    # Clear spinner line
    printf '\r\033[K' >&2
    wait "$pid" 2>/dev/null
    return $?
}

SPIN_OUTPUT=""

spin_while() {
    local msg="$1"; shift
    local tmpout
    tmpout=$(mktemp)
    # Run command in background, capture stdout to tmpfile
    "$@" > "$tmpout" 2>&1 &
    local pid=$!
    local rc=0
    spin "$pid" "$msg" || rc=$?
    SPIN_OUTPUT=$(<"$tmpout")
    rm -f "$tmpout"
    return "$rc"
}

# ── Parallel execution helper ────────────────────────────────────────────────
# run_parallel <max_jobs> <result_dir> <cmd> <args...>
#   Called in a loop — each invocation spawns a background job.
#   Use wait_parallel to collect results.
#
# We use a simpler pattern: just spawn + wait with a job semaphore.

_PARALLEL_PIDS=()

parallel_limit() {
    local max="$1"
    while (( ${#_PARALLEL_PIDS[@]} >= max )); do
        local new_pids=()
        for p in "${_PARALLEL_PIDS[@]}"; do
            if kill -0 "$p" 2>/dev/null; then
                new_pids+=("$p")
            fi
        done
        _PARALLEL_PIDS=("${new_pids[@]}")
        if (( ${#_PARALLEL_PIDS[@]} >= max )); then
            sleep 0.05
        fi
    done
}

parallel_track() {
    _PARALLEL_PIDS+=("$1")
}

parallel_wait() {
    local rc=0
    for p in "${_PARALLEL_PIDS[@]}"; do
        wait "$p" || ((rc++)) || true
    done
    _PARALLEL_PIDS=()
    return "$rc"
}
