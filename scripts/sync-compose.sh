#!/usr/bin/env bash
# =============================================================================
# sync-compose.sh — Keep root compose.yaml in sync with services/*/compose.yaml
# =============================================================================
# Modes:
#   --check          Exit 1 if out of sync (for pre-commit / CI)
#   --sync           Add missing services, report orphans
#   --remove-orphans Remove orphan entries from compose.yaml
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE="${ROOT_DIR}/compose.yaml"
SERVICES_DIR="${ROOT_DIR}/services"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Get service dirs that have a compose.yaml
get_disk_services() {
    for dir in "${SERVICES_DIR}"/*/; do
        svc=$(basename "$dir")
        [[ "$svc" == .* ]] && continue
        [[ -f "${dir}compose.yaml" ]] || continue
        echo "$svc"
    done | sort
}

# Get service dirs referenced in root compose.yaml include: paths
get_included_services() {
    grep -oP 'path:\s*services/\K[^/]+' "$COMPOSE" | sort -u
}

diff_services() {
    local disk included missing orphans
    disk=$(get_disk_services)
    included=$(get_included_services)
    missing=$(comm -23 <(echo "$disk") <(echo "$included"))
    orphans=$(comm -13 <(echo "$disk") <(echo "$included"))
    echo "$missing" "$orphans"
}

# Build an include entry for a service
make_entry() {
    local svc="$1"
    local entry=""
    entry+="  - path: services/${svc}/compose.yaml"
    if [[ -f "${SERVICES_DIR}/${svc}/.env" ]]; then
        entry+=$'\n'"    env_file:"
        entry+=$'\n'"      - .env"
        entry+=$'\n'"      - services/${svc}/.env"
    else
        entry+=$'\n'"    env_file:"
        entry+=$'\n'"      - .env"
    fi
    echo "$entry"
}

# ── Modes ────────────────────────────────────────────────────────────────────

cmd_check() {
    local disk included missing orphans rc=0
    disk=$(get_disk_services)
    included=$(get_included_services)
    missing=$(comm -23 <(echo "$disk") <(echo "$included"))
    orphans=$(comm -13 <(echo "$disk") <(echo "$included"))

    if [[ -n "$missing" ]]; then
        echo "✗ Services on disk but NOT in compose.yaml:" >&2
        echo "$missing" | sed 's/^/    /' >&2
        rc=1
    fi
    if [[ -n "$orphans" ]]; then
        echo "⚠ Services in compose.yaml but NOT on disk:" >&2
        echo "$orphans" | sed 's/^/    /' >&2
        rc=1
    fi
    if [[ $rc -eq 0 ]]; then
        echo "✓ compose.yaml is in sync with services/"
    fi
    return $rc
}

cmd_sync() {
    local disk included missing orphans added=0
    disk=$(get_disk_services)
    included=$(get_included_services)
    missing=$(comm -23 <(echo "$disk") <(echo "$included"))
    orphans=$(comm -13 <(echo "$disk") <(echo "$included"))

    # Add missing services before the final blank line / EOF
    if [[ -n "$missing" ]]; then
        echo "Adding missing services to compose.yaml:"
        # Build the block to append
        local block=""
        block+=$'\n'"  # --- Added by sync $(date +%Y-%m-%d) ---"
        while IFS= read -r svc; do
            [[ -z "$svc" ]] && continue
            block+=$'\n'"$(make_entry "$svc")"
            echo "  + $svc"
            ((added++)) || true
        done <<< "$missing"

        # Append before EOF (after last non-empty line)
        # Remove trailing blank lines, append block, add final newline
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$COMPOSE"
        echo "$block" >> "$COMPOSE"
        echo "" >> "$COMPOSE"
        echo "✓ Added $added service(s)"
    else
        echo "✓ No missing services"
    fi

    # Report orphans
    if [[ -n "$orphans" ]]; then
        echo ""
        echo "⚠ Orphan entries (in compose.yaml but no services/ dir):"
        echo "$orphans" | sed 's/^/    /'
        echo ""
        echo "  Run 'just sync --remove-orphans' to clean these up"
    fi
}

cmd_remove_orphans() {
    local disk included orphans removed=0
    disk=$(get_disk_services)
    included=$(get_included_services)
    orphans=$(comm -13 <(echo "$disk") <(echo "$included"))

    if [[ -z "$orphans" ]]; then
        echo "✓ No orphan entries to remove"
        return 0
    fi

    echo "Removing orphan entries from compose.yaml:"
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        # Remove the include block for this service:
        #   - path: services/<svc>/compose.yaml
        #     env_file:          (optional)
        #       - .env           (optional)
        #       - services/...   (optional)
        # Use awk to find and skip these lines
        awk -v svc="$svc" '
        BEGIN { skip = 0 }
        /^  - path: services\// {
            if (index($0, "services/" svc "/compose.yaml")) {
                skip = 1
                next
            }
        }
        skip && /^    / { next }
        skip && !/^    / { skip = 0 }
        !skip { print }
        ' "$COMPOSE" > "${COMPOSE}.tmp"
        mv "${COMPOSE}.tmp" "$COMPOSE"
        echo "  - $svc"
        ((removed++)) || true
    done <<< "$orphans"

    # Clean up empty comment-only sections (lines like "  # --- Added by sync ... ---" with nothing after)
    # and duplicate blank lines
    awk 'NF || !prev_blank { print; prev_blank = !NF } NF { prev_blank = 0 }' "$COMPOSE" > "${COMPOSE}.tmp"
    mv "${COMPOSE}.tmp" "$COMPOSE"

    echo "✓ Removed $removed orphan(s)"
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --check)          cmd_check ;;
    --sync)           cmd_sync ;;
    --remove-orphans) cmd_remove_orphans ;;
    *)
        echo "Usage: $(basename "$0") [--check | --sync | --remove-orphans]" >&2
        exit 1
        ;;
esac
