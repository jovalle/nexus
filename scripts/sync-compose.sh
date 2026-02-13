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

# ── Colors ───────────────────────────────────────────────────────────────────
RED=$'\033[31m'
GREEN=$'\033[32m'
RST=$'\033[0m'

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
# Preserves any extra env_file entries (cross-service deps) from the existing compose.yaml
make_entry() {
    local svc="$1"
    local entry=""
    entry+="  - path: services/${svc}/compose.yaml"
    entry+=$'\n'"    env_file:"
    entry+=$'\n'"      - .env"
    if [[ -f "${SERVICES_DIR}/${svc}/.env" ]]; then
        entry+=$'\n'"      - services/${svc}/.env"
    fi

    # Preserve existing cross-service env_file entries from current compose.yaml
    if [[ -f "$COMPOSE" ]]; then
        local in_block=false
        local in_env=false
        while IFS= read -r line; do
            # Found our service's include block
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*path:[[:space:]]*services/${svc}/compose\.yaml ]]; then
                in_block=true; continue
            fi
            if ! $in_block; then continue; fi

            # Hit a new service block → stop
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*path: ]]; then
                break
            fi

            # Found env_file key
            if [[ "$line" =~ ^[[:space:]]*env_file: ]]; then
                in_env=true; continue
            fi
            if ! $in_env; then continue; fi

            # env_file list entry (must start with "      - " i.e. 6+ spaces + dash)
            if [[ "$line" =~ ^[[:space:]]{4,}-[[:space:]]+ ]]; then
                local env_path
                env_path=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
                # Skip .env and the service's own .env (already added above)
                [[ "$env_path" == ".env" ]] && continue
                [[ "$env_path" == "services/${svc}/.env" ]] && continue
                # Cross-service env_file — preserve it
                entry+=$'\n'"      - ${env_path}"
            else
                break  # End of env_file list
            fi
        done < "$COMPOSE"
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
        echo "${RED}✗${RST} Services on disk but NOT in compose.yaml:" >&2
        echo "$missing" | sed 's/^/    /' >&2
        rc=1
    fi
    if [[ -n "$orphans" ]]; then
        echo "⚠ Services in compose.yaml but NOT on disk:" >&2
        echo "$orphans" | sed 's/^/    /' >&2
        rc=1
    fi
    if [[ $rc -eq 0 ]]; then
        echo "${GREEN}✓${RST} compose.yaml is in sync with services/"
    fi
    return $rc
}

cmd_sync() {
    local disk
    disk=$(get_disk_services)

    echo "Regenerating compose.yaml with $(echo "$disk" | wc -w) services (sorted alphabetically)..."

    # Extract header (everything before 'include:')
    local header
    header=$(sed -n '1,/^include:/p' "$COMPOSE" | head -n -1)

    # Build the new include section
    local includes="include:"
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        includes+=$'\n'"$(make_entry "$svc")"
    done <<< "$disk"

    # Write the new compose.yaml
    {
        echo "$header"
        echo ""
        echo "$includes"
    } > "$COMPOSE"

    echo "${GREEN}✓${RST} compose.yaml updated"
}

cmd_remove_orphans() {
    local disk included orphans removed=0
    disk=$(get_disk_services)
    included=$(get_included_services)
    orphans=$(comm -13 <(echo "$disk") <(echo "$included"))

    if [[ -z "$orphans" ]]; then
        echo "${GREEN}✓${RST} No orphan entries to remove"
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

    echo "${GREEN}✓${RST} Removed $removed orphan(s)"
}

# Sync a single service: create from template if needed, add to compose.yaml
cmd_sync_service() {
    local svc="$1"
    local svc_dir="${SERVICES_DIR}/${svc}"
    local svc_compose="${svc_dir}/compose.yaml"
    local data_dir="${svc_dir}/data"

    # Check if service directory exists
    if [[ ! -d "$svc_dir" ]]; then
        echo "${RED}✗${RST} Service directory not found: $svc_dir" >&2
        exit 1
    fi

    # Load environment variables from compose.yaml env_file entries
    # First, get the env_file entries for this service from compose.yaml
    local env_files=()
    local in_service=false
    local in_env_file=false

    while IFS= read -r line; do
        # Detect our service's include block
        if [[ "$line" =~ ^\ \ -\ path:\ services/${svc}/compose\.yaml ]]; then
            in_service=true
            continue
        fi
        # Detect next service (exit our block)
        if $in_service && [[ "$line" =~ ^\ \ -\ path: ]]; then
            break
        fi
        # Detect env_file section
        if $in_service && [[ "$line" =~ ^\ \ \ \ env_file: ]]; then
            in_env_file=true
            continue
        fi
        # Collect env file entries
        if $in_service && $in_env_file && [[ "$line" =~ ^\ \ \ \ \ \ -\ (.+)$ ]]; then
            env_files+=("${BASH_REMATCH[1]}")
        fi
        # Exit env_file section if we hit a non-list line
        if $in_service && $in_env_file && [[ ! "$line" =~ ^\ \ \ \ \ \  ]]; then
            in_env_file=false
        fi
    done < "$COMPOSE"

    # Load env files in order (compose.yaml entries first, then service-specific)
    for env_file in "${env_files[@]}"; do
        local env_path="${ROOT_DIR}/${env_file}"
        if [[ -f "$env_path" ]]; then
            set -a
            # shellcheck source=/dev/null
            source "$env_path"
            set +a
        fi
    done

    # Load service-specific .env if not already in env_files
    if [[ -f "${svc_dir}/.env" ]] && [[ ! " ${env_files[*]} " =~ " services/${svc}/.env " ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${svc_dir}/.env"
        set +a
    fi

    # Render all .template files in the service directory (excluding .env.template)
    local templates_rendered=0
    local templates_failed=0
    while IFS= read -r template; do
        [[ -z "$template" ]] && continue
        [[ "$template" == *".env.template" ]] && continue

        local output="${template%.template}"

        # Check for unset variables
        local vars_in_template missing_vars=""
        vars_in_template=$(grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "$template" 2>/dev/null | sort -u || true)
        for var in $vars_in_template; do
            local var_name="${var:2:-1}"  # Strip ${ and }
            if [[ -z "${!var_name:-}" ]]; then
                missing_vars+=" $var"
            fi
        done

        if [[ -n "$missing_vars" ]]; then
            echo "  ${RED}✗${RST} ${template#"$svc_dir"/}"
            echo "    Missing:$missing_vars"
            ((templates_failed++)) || true
            continue
        fi

        if envsubst < "$template" > "$output" 2>/dev/null; then
            chmod 644 "$output"
            echo "  ${GREEN}✓${RST} ${template#"$svc_dir"/}"
            ((templates_rendered++)) || true
        else
            echo "  ${RED}✗${RST} ${template#"$svc_dir"/} (envsubst failed)"
            ((templates_failed++)) || true
        fi
    done < <(find "$svc_dir" -type f -name "*.template" 2>/dev/null)

    if ((templates_rendered > 0 || templates_failed > 0)); then
        if ((templates_failed > 0)); then
            echo "${RED}✗${RST} Templates: $templates_rendered rendered, $templates_failed failed"
        else
            echo "${GREEN}✓${RST} Templates: $templates_rendered rendered"
        fi
    fi

    # Check if compose.yaml exists (may have been generated from template above)
    if [[ ! -f "$svc_compose" ]]; then
        echo "${RED}✗${RST} No compose.yaml found in $svc_dir" >&2
        exit 1
    fi

    # Check if already in compose.yaml
    if grep -q "path: services/${svc}/compose.yaml" "$COMPOSE"; then
        echo "${GREEN}✓${RST} Service '${svc}' already in compose.yaml"
        return 0
    fi

    # Add to compose.yaml (sorted position)
    echo "Adding ${svc} to compose.yaml..."
    local new_entry
    new_entry=$(make_entry "$svc")

    # Find the right position to insert (alphabetically sorted)
    local inserted=false
    local tmpfile="${COMPOSE}.tmp"
    local in_include=false
    local current_service=""

    while IFS= read -r line; do
        # Detect start of include section
        if [[ "$line" == "include:" ]]; then
            in_include=true
            echo "$line" >> "$tmpfile"
            continue
        fi

        # Detect service path entries
        if $in_include && [[ "$line" =~ ^\ \ -\ path:\ services/([^/]+)/compose\.yaml$ ]]; then
            current_service="${BASH_REMATCH[1]}"
            # Insert before this entry if new service comes first alphabetically
            if ! $inserted && [[ "$svc" < "$current_service" ]]; then
                echo "$new_entry" >> "$tmpfile"
                inserted=true
            fi
        fi

        echo "$line" >> "$tmpfile"
    done < "$COMPOSE"

    # If not inserted yet, append at the end of include section
    if ! $inserted; then
        # Append new entry at the end
        echo "$new_entry" >> "$tmpfile"
    fi

    mv "$tmpfile" "$COMPOSE"
    echo "${GREEN}✓${RST} Added '${svc}' to compose.yaml"
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --check)          cmd_check ;;
    --sync)
        if [[ -n "${2:-}" ]]; then
            cmd_sync_service "$2"
        else
            cmd_sync
        fi
        ;;
    --remove-orphans) cmd_remove_orphans ;;
    -h|--help)
        echo "Usage: $(basename "$0") [--check | --sync [service] | --remove-orphans]"
        echo ""
        echo "Options:"
        echo "  --check           Exit 1 if compose.yaml is out of sync"
        echo "  --sync            Regenerate compose.yaml with all services"
        echo "  --sync <service>  Add/update a specific service in compose.yaml"
        echo "  --remove-orphans  Remove orphan entries from compose.yaml"
        exit 0
        ;;
    *)
        echo "Usage: $(basename "$0") [--check | --sync [service] | --remove-orphans]" >&2
        exit 1
        ;;
esac
