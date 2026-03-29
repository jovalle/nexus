#!/usr/bin/env bash
# =============================================================================
# check-host.sh - Validate and optionally prepare local host prerequisites
# =============================================================================
# Usage:
#   bash scripts/check-host.sh           # validate only
#   bash scripts/check-host.sh --fix     # create missing network and .env
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/helpers.sh"

FIX=false
for arg in "$@"; do
    case "$arg" in
        --fix)
            FIX=true
            ;;
        --help|-h)
            cat <<'EOF'
Usage: check-host.sh [--fix]

Checks:
  - docker CLI availability
  - docker daemon reachability
  - docker compose v2 availability
  - presence of nexus docker network
  - presence of .env file in repo root

Options:
  --fix    Create missing nexus network and .env from .env.example
EOF
            exit 0
            ;;
        *)
            log_err "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

failed=false

log_step "Checking required tooling"
if ! command -v docker >/dev/null 2>&1; then
    log_err "docker not found in PATH"
    failed=true
else
    log_ok "docker CLI found"
fi

if ! docker info >/dev/null 2>&1; then
    log_err "docker daemon is not reachable"
    log_warn "Start Docker and ensure this user can access the daemon"
    failed=true
else
    log_ok "docker daemon reachable"
fi

if ! docker compose version >/dev/null 2>&1; then
    log_err "docker compose v2 not available"
    log_warn "Install docker compose plugin"
    failed=true
else
    log_ok "docker compose available"
fi

log_step "Checking nexus network"
if docker network inspect nexus >/dev/null 2>&1; then
    log_ok "network nexus exists"
else
    if $FIX; then
        log_step "Creating network nexus"
        docker network create nexus --subnet 172.52.0.0/16 --gateway 172.52.0.1 >/dev/null
        log_ok "network nexus created"
    else
        log_warn "network nexus missing"
        log_warn "Run: bash scripts/check-host.sh --fix"
    fi
fi

log_step "Checking environment file"
if [[ -f "${ROOT_DIR}/.env" ]]; then
    log_ok ".env exists"
else
    if $FIX && [[ -f "${ROOT_DIR}/.env.example" ]]; then
        cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
        log_ok "Created .env from .env.example"
        log_warn "Review and edit .env values before running services"
    else
        log_warn ".env not found"
        log_warn "Create it from .env.example"
    fi
fi

if $failed; then
    log_err "Host prerequisite check failed"
    exit 1
fi

log_ok "Host prerequisite check passed"
