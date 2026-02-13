# ──────────────────────────────────────────────────────────────────────────────
# Nexus — Docker Compose Service Management
# ──────────────────────────────────────────────────────────────────────────────
# Usage:  just <recipe>          Run a recipe
#         just --list            Show all available recipes
#         just --choose          Pick a recipe interactively (requires fzf)
# ──────────────────────────────────────────────────────────────────────────────

set dotenv-load := true
set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments := true

# Paths (override via .env or environment)
root_dir     := justfile_directory()
services_dir := root_dir / "services"
scripts_dir  := root_dir / "scripts"
archive_dir  := root_dir / "archive"
backup_dir   := root_dir / "backups"
data_path    := env("DATA_PATH", root_dir / "docker")

# Timestamp for file naming
ts := `date +%Y%m%d-%H%M%S`

# Go template escape helpers — Docker --format uses Go templates which
# conflict with just's own {{ }} interpolation. These let us write
# {{ _l }}.Names{{ _r }} to produce the literal {{.Names}}.
_l := "{" + "{"
_r := "}" + "}"

# ANSI color codes for output
RED   := `printf '\033[31m'`
GREEN := `printf '\033[32m'`
YLW   := `printf '\033[33m'`
DIM   := `printf '\033[2m'`
RST   := `printf '\033[0m'`

# Shared helpers (source in bash recipes)
helpers := scripts_dir / "helpers.sh"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DEFAULT / HELP                                                            ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Show all available recipes
@default:
    just --list --unsorted

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  SERVICE MANAGEMENT                                                        ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Start a service (or all services)
[group('manage')]
start *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"

    # --- Detect stale/orphan containers (single docker call) ---
    tmpps=$(mktemp)
    docker ps -a --format '{{ _l }}.Names{{ _r }}|{{ _l }}.State{{ _r }}|{{ _l }}.Status{{ _r }}|{{ _l }}.Label "com.docker.compose.project"{{ _r }}' > "$tmpps" 2>/dev/null &
    spin $! "Scanning for stale containers…"

    declare -A _DS=() _DP=()
    while IFS='|' read -r name state status project; do
        [[ -z "$name" ]] && continue
        _DS["$name"]="$state"
        _DP["$name"]="$project"
    done < "$tmpps"
    rm -f "$tmpps"

    mapfile -t expected_services < <(docker compose config --services 2>/dev/null || true)
    conflicts=()
    for name in "${!_DS[@]}"; do
        [[ "$name" =~ ^[0-9a-f]{12}_ ]] && conflicts+=("$name")
    done
    for svc in "${expected_services[@]}"; do
        [[ -z "$svc" ]] && continue
        [[ -z "${_DS[$svc]:-}" ]] && continue
        local_project="${_DP[$svc]:-}"
        if [[ -z "$local_project" || "$local_project" != "nexus" ]]; then
            conflicts+=("$svc")
        fi
    done

    if (( ${#conflicts[@]} > 0 )); then
        echo "╭──────────────────────────────────────────────────────────────╮"
        echo "│  Conflicting containers detected                             │"
        echo "╰──────────────────────────────────────────────────────────────╯"
        for c in "${conflicts[@]}"; do
            echo "  • $c"
        done
        echo ""
        read -rp "Remove these containers and recreate? [Y/n] " ans
        if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
            for c in "${conflicts[@]}"; do
                log_step "Removing $c"
                docker rm -f "$c" >/dev/null 2>&1 || true
            done
            log_ok "Conflicting containers removed"
            echo ""
        fi
    fi

    # --- Normal up flow ---
    if [[ -z "{{ service }}" ]]; then
        log_step "Starting all services…"
        if ! output=$(docker compose up -d --remove-orphans 2>&1); then
            echo "$output"
            log_err "docker compose up failed"
            exit 1
        fi
        started=$(grep -cE ' (Started|Created)' <<< "$output" || true)
        running=$(grep -c ' Running' <<< "$output" || true)
        errors=$(grep -iE 'error|failed' <<< "$output" || true)
        [[ -n "$errors" ]] && echo "$errors"
        log_ok "All services started ($started created, $running already running)"
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        log_step "Starting {{ service }}…"
        docker compose up -d --remove-orphans $SVC_NAMES
        log_ok "{{ service }} started"
    fi

# Stop a service (or all services) — removes containers and networks
[group('manage')]
stop *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    if [[ -z "{{ service }}" ]]; then
        log_step "Stopping all services…"
        docker compose down --timeout 30 --remove-orphans
        log_ok "All services stopped"
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        log_step "Stopping {{ service }}…"
        docker compose stop --timeout 30 $SVC_NAMES
        docker compose rm -f $SVC_NAMES
        log_ok "{{ service }} stopped"
    fi

# Restart a service (or all services)
[group('manage')]
restart *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    if [[ -z "{{ service }}" ]]; then
        log_step "Restarting all services…"
        docker compose restart
        log_ok "All services restarted"
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        log_step "Restarting {{ service }}…"
        docker compose restart $SVC_NAMES
        log_ok "{{ service }} restarted"
    fi

# Recreate a service (pull + force-recreate)
[group('manage')]
recreate service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    log_step "Pulling latest images for {{ service }}…"
    docker compose pull $SVC_NAMES
    log_step "Recreating {{ service }}…"
    docker compose up -d --force-recreate --remove-orphans $SVC_NAMES
    log_ok "{{ service }} recreated"

# Update a service (pull + up) or all services
[group('manage')]
update *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    if [[ -z "{{ service }}" ]]; then
        log_step "Pulling latest images for all services…"
        docker compose pull 2>&1
        log_step "Bringing services up…"
        docker compose up -d --remove-orphans
        log_ok "All services updated"
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        log_step "Pulling latest images for {{ service }}…"
        docker compose pull $SVC_NAMES 2>&1
        log_step "Bringing {{ service }} up…"
        docker compose up -d --remove-orphans $SVC_NAMES
        log_ok "{{ service }} updated"
    fi

# Build and run service from local Dockerfile (requires compose.local.yaml)
[group('manage')]
build-local service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    svc_dir="{{ services_dir }}/{{ service }}"
    local_compose="$svc_dir/compose.local.yaml"
    resolve_service "{{ service }}" "{{ services_dir }}"
    if [[ ! -f "$local_compose" ]]; then
        log_err "No compose.local.yaml found for '{{ service }}'"
        echo "Create $local_compose with build context to use this recipe" >&2
        exit 1
    fi
    # Stop and remove any existing container (may be from different compose project)
    cache_docker_ps
    for svc in $SVC_NAMES; do
        if [[ -n "${DOCKER_STATE[$svc]:-}" ]]; then
            log_step "Removing existing container: $svc"
            docker rm -f "$svc" >/dev/null 2>&1 || true
        fi
    done
    log_step "Building {{ service }} from local Dockerfile…"
    cd "$svc_dir"
    docker compose -p nexus -f compose.yaml -f compose.local.yaml up -d --build --force-recreate --remove-orphans
    log_ok "{{ service }} built and started"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  STATUS & LISTING                                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Show container status for a service (or all)
[group('inspect')]
status *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    if [[ -z "{{ service }}" ]]; then
        # ── Collect data with spinner, then render table ──
        tmpfile=$(mktemp)
        _gather_status() {
            cache_docker_ps
            for dir in {{ services_dir }}/*/; do
                svc=$(basename "$dir")
                [[ "$svc" == .* ]] && continue
                compose="{{ services_dir }}/$svc/compose.yaml"
                [[ -f "$compose" ]] || continue
                mapfile -t svc_containers < <(yq -r '.services | keys | .[]' "$compose" 2>/dev/null)
                svc_count=${#svc_containers[@]}
                if (( svc_count > 1 )); then
                    total_ct=$svc_count; running_ct=0; healthy_ct=0; checks_ct=0; group_uptime="-"
                    for ct in "${svc_containers[@]}"; do
                        ct_state="${DOCKER_STATE[$ct]:-}"
                        ct_status="${DOCKER_STATUS[$ct]:-}"
                        if [[ "$ct_state" == "running" ]]; then
                            ((running_ct++)) || true
                            [[ "$group_uptime" == "-" ]] && group_uptime=$(grep -oP 'Up \K.*' <<< "$ct_status" | sed 's/ (.*//' || echo "-")
                        fi
                        if [[ "$ct_status" == *"(healthy)"* ]]; then
                            ((healthy_ct++)) || true; ((checks_ct++)) || true
                        elif [[ "$ct_status" == *"(unhealthy)"* || "$ct_status" == *"health: starting"* ]]; then
                            ((checks_ct++)) || true
                        fi
                    done
                    if (( running_ct == total_ct )); then sc="\033[32m"; state_display="running"
                    elif (( running_ct > 0 ));       then sc="\033[33m"; state_display="partial"
                    else sc="\033[2m"; state_display="not created"; fi
                    if (( checks_ct > 0 )); then
                        health_display="${healthy_ct}/${total_ct}"
                        if   (( healthy_ct == total_ct )); then hc="\033[32m"
                        elif (( healthy_ct > 0 ));         then hc="\033[33m"
                        else hc="\033[31m"; fi
                    else health_display="-"; hc="\033[0m"; fi
                    printf "${sc}%-22s\033[0m %-12s ${hc}%-10s\033[0m %s\n" \
                        "$svc" "$state_display" "$health_display" "$group_uptime"
                else
                    ct_name="${svc_containers[0]:-$svc}"
                    state="${DOCKER_STATE[$ct_name]:-}"
                    status="${DOCKER_STATUS[$ct_name]:-}"
                    if [[ -n "$state" ]]; then
                        health="-"
                        [[ "$status" == *"(healthy)"* ]]         && health="healthy"
                        [[ "$status" == *"(unhealthy)"* ]]       && health="unhealthy"
                        [[ "$status" == *"health: starting"* ]]  && health="starting"
                        uptime="-"
                        [[ "$state" == "running" ]] && uptime=$(grep -oP 'Up \K.*' <<< "$status" | sed 's/ (.*//' || echo "-")
                        case "$state" in running) sc="\033[32m";; exited) sc="\033[31m";; *) sc="\033[33m";; esac
                        case "$health" in healthy) hc="\033[32m";; unhealthy) hc="\033[31m";; starting) hc="\033[33m";; *) hc="\033[0m";; esac
                        printf "${sc}%-22s\033[0m %-12s ${hc}%-10s\033[0m %s\n" "$svc" "$state" "$health" "$uptime"
                    else
                        printf "\033[2m%-22s %-12s %-10s %s\033[0m\n" "$svc" "not created" "-" "-"
                    fi
                fi
            done
        }
        _gather_status > "$tmpfile" 2>&1 &
        spin $! "Gathering container status…"
        echo "╭──────────────────────────────────────────────────────────────╮"
        echo "│  Nexus — Container Status                                    │"
        echo "╰──────────────────────────────────────────────────────────────╯"
        echo ""
        printf "%-22s %-12s %-10s %s\n" "SERVICE" "STATE" "HEALTH" "UPTIME"
        printf "%-22s %-12s %-10s %s\n" "───────" "─────" "──────" "──────"
        cat "$tmpfile"
        rm -f "$tmpfile"
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        docker compose -f "$SVC_COMPOSE" ps
    fi

# List services, backups, or archives
[group('inspect')]
list *what:
    #!/usr/bin/env bash
    set -euo pipefail
    case "${1:-}" in
        backups)    just _list-backups ;;
        archives)   just _list-archives ;;
        *)          just _list-services "$@" ;;
    esac

[private]
_list-services *filter:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"

    # Single docker call, build a set of running container names
    declare -A running_set=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && running_set["$name"]=1
    done < <(docker ps --format '{{ _l }}.Names{{ _r }}' 2>/dev/null)

    tmpfile=$(mktemp)
    total=0; up=0; down=0
    _scan() {
        for dir in {{ services_dir }}/*/; do
            svc=$(basename "$dir")
            [[ "$svc" == .* ]] && continue
            [[ -n "{{ filter }}" ]] && ! grep -qi "{{ filter }}" <<< "$svc" && continue
            compose="{{ services_dir }}/$svc/compose.yaml"
            ((total++)) || true
            if [[ ! -f "$compose" ]]; then
                printf "  \033[2m○ %s\033[0m\n" "$svc"
                ((down++)) || true
                continue
            fi
            # Fast path: try dir name first (matches ~90% of services)
            if [[ -n "${running_set[$svc]:-}" ]]; then
                printf "  \033[32m●\033[0m %s\n" "$svc"
                ((up++)) || true
                continue
            fi
            # Slow path: check yq-resolved container names
            svc_running=false
            while IFS= read -r ct; do
                [[ -n "${running_set[$ct]:-}" ]] && svc_running=true && break
            done < <(yq -r '.services | keys | .[]' "$compose" 2>/dev/null)
            if $svc_running; then
                printf "  \033[32m●\033[0m %s\n" "$svc"
                ((up++)) || true
            else
                printf "  \033[2m○ %s\033[0m\n" "$svc"
                ((down++)) || true
            fi
        done
        echo "---COUNTS:${total}:${up}:${down}"
    }
    _scan > "$tmpfile" 2>&1 &
    spin $! "Scanning services…"

    echo "╭──────────────────────────────────────────────────────────────╮"
    echo "│  Nexus — Services                                            │"
    echo "╰──────────────────────────────────────────────────────────────╯"
    echo ""
    grep -v '^---COUNTS:' "$tmpfile"
    counts=$(grep '^---COUNTS:' "$tmpfile" | tail -1)
    total=$(cut -d: -f2 <<< "$counts")
    up=$(cut -d: -f3 <<< "$counts")
    down=$(cut -d: -f4 <<< "$counts")
    echo ""
    echo "Total: $total  Running: $up  Stopped: $down"
    rm -f "$tmpfile"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  LOGGING                                                                   ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Show recent logs: `just log <service> [lines]`, `just log since <service> <time>`
[group('log')]
log *args:
    #!/usr/bin/env bash
    set -euo pipefail
    case "${1:-}" in
        since)
            service="${2:?Usage: just log since <service> <time>}"
            since="${3:?Usage: just log since <service> <time>}"
            just _log-since "$service" "$since"
            ;;
        "")
            echo "Usage: just log <service> [lines]" >&2
            echo "       just log since <service> <time>" >&2
            exit 1
            ;;
        *)
            service="$1"; shift
            lines="${1:-200}"
            just _log-snapshot "$service" "$lines"
            ;;
    esac

# Show last N lines of logs (non-following)
[private]
_log-snapshot service lines="200":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    docker compose logs --tail={{ lines }} $SVC_NAMES

# Follow (tail) live logs for a service
[group('log')]
tail service *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    docker compose logs -f --tail=100 $SVC_NAMES {{ args }}

# Show logs since a time (e.g. "1h", "30m", "2024-01-01")
[private]
_log-since service since:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    docker compose logs --since={{ since }} --tail=500 $SVC_NAMES

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DEBUGGING                                                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Open a shell inside a running container
[group('debug')]
shell service *shell_cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    cmd="{{ shell_cmd }}"
    if [[ -z "$cmd" ]]; then
        if docker exec "{{ service }}" bash --version &>/dev/null; then
            cmd="bash"
        else
            cmd="sh"
        fi
    fi
    docker exec -it "{{ service }}" $cmd

# Show resource usage for a service (or all)
[group('debug')]
top *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    stats_fmt='table {{ _l }}.Name{{ _r }}\t{{ _l }}.CPUPerc{{ _r }}\t{{ _l }}.MemUsage{{ _r }}\t{{ _l }}.NetIO{{ _r }}\t{{ _l }}.BlockIO{{ _r }}'
    if [[ -z "{{ service }}" ]]; then
        log_step "Collecting resource usage…"
        docker stats --no-stream --format "$stats_fmt" | (read -r header; echo "$header"; sort)
    else
        log_step "Resource usage for {{ service }}"
        docker stats --no-stream "{{ service }}"
    fi

# Inspect a service's compose config (resolved)
[group('debug')]
config service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    docker compose config $SVC_NAMES

# Validate compose file(s) for a service (or all)
[group('debug')]
validate *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    if [[ -z "{{ service }}" ]]; then
        # Collect compose files
        compose_files=()
        svc_names_list=()
        for dir in {{ services_dir }}/*/; do
            svc=$(basename "$dir")
            [[ "$svc" == .* ]] && continue
            compose="{{ services_dir }}/$svc/compose.yaml"
            [[ -f "$compose" ]] || continue
            compose_files+=("$compose")
            svc_names_list+=("$svc")
        done
        total=${#compose_files[@]}
        results_dir=$(mktemp -d)

        # Parallel validation
        log_step "Validating $total compose files…"
        _run_validations() {
            local max_jobs=$(nproc 2>/dev/null || echo 4)
            local i=0
            for idx in "${!compose_files[@]}"; do
                local compose="${compose_files[$idx]}"
                local svc="${svc_names_list[$idx]}"
                (
                    if docker compose -f "$compose" config > /dev/null 2>&1; then
                        echo "OK" > "$results_dir/$svc"
                    else
                        errs=$(docker compose -f "$compose" config 2>&1 | grep -i "error" | head -3 || true)
                        echo "FAIL:$errs" > "$results_dir/$svc"
                    fi
                ) &
                parallel_track $!
                parallel_limit "$max_jobs"
            done
            parallel_wait || true
        }
        _run_validations > /dev/null 2>&1 &
        spin $! "Validating $total compose files…"

        # Display results
        errors=0
        for svc in "${svc_names_list[@]}"; do
            result=$(<"$results_dir/$svc")
            if [[ "$result" == "OK" ]]; then
                printf "  \033[32m✓\033[0m %s\n" "$svc"
            else
                printf "  \033[31m✗\033[0m %s\n" "$svc"
                echo "${result#FAIL:}" | sed 's/^/    /' || true
                ((errors++)) || true
            fi
        done
        rm -rf "$results_dir"
        echo ""
        if [[ $errors -eq 0 ]]; then
            log_ok "All $total compose files valid"
        else
            log_err "$errors service(s) have invalid compose files"
            exit 1
        fi
    else
        resolve_service "{{ service }}" "{{ services_dir }}"
        log_step "Validating {{ service }}…"
        if docker compose -f "$SVC_COMPOSE" config > /dev/null 2>&1; then
            log_ok "{{ service }} compose file is valid"
        else
            log_err "{{ service }} compose file has errors:"
            docker compose -f "$SVC_COMPOSE" config 2>&1
            exit 1
        fi
    fi

# Inspect container details (env, mounts, network, etc.)
[group('debug')]
inspect service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    # Single docker inspect call → parse with jq
    _gather() {
        docker inspect "{{ service }}" 2>/dev/null || echo "[]"
    }
    spin_while "Inspecting {{ service }}…" _gather || true
    json="$SPIN_OUTPUT"
    echo "╭──────────────────────────────────────────────────────────────╮"
    echo "│  {{ service }} — Container Details                          │"
    echo "╰──────────────────────────────────────────────────────────────╯"
    echo ""
    if [[ -z "$json" || "$json" == "[]" ]]; then
        echo "  (container not found or not running)"
        exit 0
    fi
    echo "── Image ──"
    jq -r '.[0].Config.Image // "(unknown)"' <<< "$json" | sed 's/^/  /'
    echo ""
    echo "── Ports ──"
    jq -r '.[0].NetworkSettings.Ports // {} | to_entries[] | "  \(.key) -> \(.value // [] | map("\(.HostIp):\(.HostPort)") | join(", "))"' <<< "$json" 2>/dev/null || echo "  (none)"
    echo "── Mounts ──"
    jq -r '.[0].Mounts[]? | "  \(.Source) -> \(.Destination) (\(.Type))"' <<< "$json" 2>/dev/null || echo "  (none)"
    echo "── Networks ──"
    jq -r '.[0].NetworkSettings.Networks // {} | to_entries[] | "  \(.key): \(.value.IPAddress)"' <<< "$json" 2>/dev/null || echo "  (none)"
    echo "── Environment ──"
    jq -r '.[0].Config.Env[]? | select(test("PASSWORD|SECRET|TOKEN|KEY") | not)' <<< "$json" 2>/dev/null | head -30 | sed 's/^/  /' || echo "  (none)"
    echo "  (secrets redacted)"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  EXPAND — Add New Services                                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Create a new service from template
[group('expand')]
new service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    target="{{ services_dir }}/{{ service }}"
    if [[ -d "$target" ]]; then
        log_err "Service '{{ service }}' already exists at $target"
        exit 1
    fi
    # Check if there's an archived version
    archived="{{ archive_dir }}/{{ service }}"
    if [[ -d "$archived" ]]; then
        log_warn "Found archived version of '{{ service }}'."
        read -p "Restore from archive instead? [y/N] " restore
        if [[ "$restore" =~ ^[Yy]$ ]]; then
            mv "$archived" "$target"
            log_ok "Restored {{ service }} from archive"
            exit 0
        fi
    fi
    log_step "Creating {{ service }} from template…"
    mkdir -p "$target"
    svc="{{ service }}"
    cat > "$target/compose.yaml" << EOF
    # ──────────────────────────────────────────────────────────────────────
    # TODO: Fill in the values marked with <...> below
    # Docs: https://docs.docker.com/reference/compose-file/
    # ──────────────────────────────────────────────────────────────────────
    services:
      ${svc}:
        image: <IMAGE>                       # e.g. grafana/grafana
        container_name: ${svc}
        hostname: ${svc}
        environment:
          TZ: \${TZ:-America/New_York}
          # Add service-specific env vars here
        healthcheck:
          test: ["CMD-SHELL", "<HEALTH_CMD>"]  # e.g. curl -f http://localhost:PORT/health
          interval: 30s
          timeout: 10s
          retries: 3
          start_period: 60s
        labels:
          homepage.group: <CATEGORY>           # e.g. Media, Observability, Gateway
          homepage.name: <DISPLAY_NAME>
          homepage.icon: <ICON>                # see https://github.com/walkxcode/dashboard-icons
          homepage.description: <DESCRIPTION>
          homepage.href: https://${svc}.\${DOMAIN}
          traefik.http.services.${svc}.loadbalancer.server.port: <PORT>
        ports:
          - <HOST_PORT>:<CONTAINER_PORT>
        deploy:
          resources:
            limits:
              cpus: '0.5'
              memory: 512M
            reservations:
              cpus: '0.1'
              memory: 128M
        restart: unless-stopped
        security_opt:
          - no-new-privileges:true
        cap_drop:
          - ALL
        tmpfs:
          - /tmp:rw,noexec,nosuid,size=64m
        volumes:
          - \${DATA_PATH:?data path not defined}/${svc}:/data         # Adjust mount path per docs
        networks:
          - nexus

    networks:
      nexus:
        external: true
    EOF
    # Fix indentation (remove leading 4-space indent from heredoc)
    sed -i 's/^    //' "$target/compose.yaml"
    log_ok "Created {{ service }} at $target/compose.yaml"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $target/compose.yaml — fill in <IMAGE>, <PORT>, etc."
    echo "  2. Add any required env vars to .env"
    echo "  3. Run: just validate {{ service }}"
    echo "  4. Run: just start {{ service }}"

# Duplicate an existing service as a starting point
[group('expand')]
clone source target:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    src="{{ services_dir }}/{{ source }}"
    dst="{{ services_dir }}/{{ target }}"
    if [[ ! -d "$src" ]]; then
        log_err "Source service '{{ source }}' not found"; exit 1
    fi
    if [[ -d "$dst" ]]; then
        log_err "Target '{{ target }}' already exists"; exit 1
    fi
    log_step "Cloning {{ source }} → {{ target }}…"
    cp -r "$src" "$dst"
    sed -i "s/{{ source }}/{{ target }}/g" "$dst/compose.yaml"
    log_ok "Cloned {{ source }} → {{ target }}"
    echo "  Edit {{ services_dir }}/{{ target }}/compose.yaml to customize"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  ARCHIVE — Gracefully Decommission Services                                ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Archive a service: stop gracefully, backup config, move to archive
[group('archive')]
archive service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    src="{{ services_dir }}/{{ service }}"
    dst="{{ archive_dir }}/{{ service }}"
    compose="$src/compose.yaml"
    if [[ ! -d "$src" ]]; then
        log_err "Service '{{ service }}' not found"; exit 1
    fi
    printf '╭%62s╮\n' '' | tr ' ' '─'
    printf '│  %-60s│\n' 'Archiving: {{ service }}'
    printf '╰%62s╯\n' '' | tr ' ' '─'
    echo ""
    # 1. Stop the service gracefully
    if [[ -f "$compose" ]]; then
        log_step "① Stopping {{ service }}…"
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        docker compose stop --timeout 30 $svc_names 2>&1 | sed 's/^/   /' || true
        docker compose rm -f $svc_names 2>&1 | sed 's/^/   /' || true
    fi
    # 2. Backup the config before archiving
    log_step "② Backing up config…"
    mkdir -p "{{ backup_dir }}/retired"
    tar -czf "{{ backup_dir }}/retired/{{ service }}-{{ ts }}.tar.gz" \
        -C "{{ services_dir }}" "{{ service }}" 2>/dev/null || true
    # 3. Move to archive
    log_step "③ Archiving…"
    mkdir -p "{{ archive_dir }}"
    if [[ -d "$dst" ]]; then
        mv "$src" "${dst}-{{ ts }}"
        echo "  (previous archive exists, saved as {{ service }}-{{ ts }})"
    else
        mv "$src" "$dst"
    fi
    # 4. Remove from root compose.yaml
    log_step "④ Updating compose.yaml…"
    "{{ scripts_dir }}/sync-compose.sh" --remove-orphans 2>&1 | sed 's/^/   /'
    echo ""
    log_ok "{{ service }} archived"
    echo "  Config backup: {{ backup_dir }}/retired/{{ service }}-{{ ts }}.tar.gz"
    echo "  Archived to:   {{ archive_dir }}/{{ service }}"
    echo ""
    echo "  To restore: just unarchive {{ service }}"

# Restore an archived service
[group('archive')]
unarchive service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    src="{{ archive_dir }}/{{ service }}"
    dst="{{ services_dir }}/{{ service }}"
    if [[ ! -d "$src" ]]; then
        log_err "No archive found for '{{ service }}'"
        matches=$(ls -d {{ archive_dir }}/{{ service }}-* 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            echo "  Found timestamped archives:"
            echo "$matches" | sed 's/^/    /'
            echo "  Move the desired version to {{ archive_dir }}/{{ service }} and try again"
        fi
        exit 1
    fi
    if [[ -d "$dst" ]]; then
        log_err "Service '{{ service }}' already exists in services/"; exit 1
    fi
    log_step "Restoring {{ service }} from archive…"
    mv "$src" "$dst"
    "{{ scripts_dir }}/sync-compose.sh" --sync 2>&1 | sed 's/^/  /'
    log_ok "Restored {{ service }} from archive"
    echo "  Run: just start {{ service }}"

# List archived services
[private]
_list-archives:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d "{{ archive_dir }}" ]] || [[ -z "$(ls -A {{ archive_dir }} 2>/dev/null)" ]]; then
        echo "No archived services"
        exit 0
    fi
    echo "Archived services:"
    for dir in {{ archive_dir }}/*/; do
        [[ -d "$dir" ]] || continue
        svc=$(basename "$dir")
        mod=$(stat -c %y "$dir" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        printf "  %-25s (archived: %s)\n" "$svc" "$mod"
    done

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  BACKUP                                                                    ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Backup everything: configs, env/secrets, and optionally data
[group('backup')]
backup *args:
    #!/usr/bin/env bash
    set -euo pipefail
    scope="${1:-all}"
    shift 2>/dev/null || true
    case "$scope" in
        config|configs)
            just _backup-configs
            ;;
        env|secrets)
            just _backup-secrets
            ;;
        data)
            just _backup-data "$@"
            ;;
        all)
            just _backup-configs
            just _backup-secrets
            just _backup-data
            echo ""
            source "{{ helpers }}"
            log_ok "Full backup complete → {{ backup_dir }}/"
            ;;
        *)
            echo "Usage: just backup [configs|secrets|data|all]" >&2
            exit 1
            ;;
    esac

# Backup all service compose configs
[private]
_backup-configs:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    dest="{{ backup_dir }}/configs-{{ ts }}.tar.gz"
    mkdir -p "{{ backup_dir }}"
    _do_tar() {
        tar -czf "$dest" \
            -C "{{ root_dir }}" \
            --exclude='services/.template' \
            services/ 2>/dev/null
    }
    _do_tar &
    spin $! "Backing up service configs…"
    size=$(du -sh "$dest" | cut -f1)
    log_ok "Configs backed up ($size) → $dest"

# Backup .env and secrets (encrypted with optional GPG passphrase)
[private]
_backup-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    dest="{{ backup_dir }}/secrets-{{ ts }}.tar.gz"
    mkdir -p "{{ backup_dir }}"
    files=()
    [[ -f "{{ root_dir }}/.env" ]] && files+=(".env")
    [[ -f "{{ root_dir }}/.env.example" ]] && files+=(".env.example")
    # Scan for secret files (filesystem ops only, no subshell needed)
    for dir in {{ services_dir }}/*/; do
        svc=$(basename "$dir")
        [[ "$svc" == .* ]] && continue
        for f in "$dir"*.env "$dir".env "$dir"secrets* "$dir"*.secret; do
            [[ -f "$f" ]] && files+=("$(realpath --relative-to="{{ root_dir }}" "$f")")
        done
    done
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No secret files found"
        exit 0
    fi
    _do_tar() { tar -czf "$dest" -C "{{ root_dir }}" "${files[@]}" 2>/dev/null || true; }
    _do_tar &
    spin $! "Compressing ${#files[@]} secret files…"
    size=$(du -sh "$dest" | cut -f1)
    log_ok "Secrets backed up ($size) → $dest"
    echo ""
    log_warn "This file contains sensitive data. Store securely."
    if command -v gpg &>/dev/null; then
        read -p "  Encrypt with GPG passphrase? [y/N] " encrypt
        if [[ "$encrypt" =~ ^[Yy]$ ]]; then
            gpg --symmetric --cipher-algo AES256 "$dest"
            rm "$dest"
            log_ok "Encrypted → ${dest}.gpg"
        fi
    fi

# Backup persistent data volumes for a service (or all)
[private]
_backup-data *service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    data="{{ data_path }}"
    if [[ ! -d "$data" ]]; then
        log_err "Data path not found: $data"
        echo "  Set DATA_PATH in .env" >&2
        exit 1
    fi
    mkdir -p "{{ backup_dir }}"
    if [[ -n "{{ service }}" ]]; then
        svc_data="$data/{{ service }}"
        if [[ ! -d "$svc_data" ]]; then
            log_err "No data directory for '{{ service }}' at $svc_data"; exit 1
        fi
        dest="{{ backup_dir }}/data-{{ service }}-{{ ts }}.tar.gz"
        log_warn "Stop the service first for a consistent backup: just stop {{ service }}"
        tar -czf "$dest" -C "$data" "{{ service }}" 2>/dev/null &
        spin $! "Backing up {{ service }} data…"
        size=$(du -sh "$dest" | cut -f1)
        log_ok "Data backed up ($size) → $dest"
    else
        dest="{{ backup_dir }}/data-all-{{ ts }}.tar.gz"
        log_warn "For consistent backups, stop services first: just stop"
        tar -czf "$dest" -C "$data" . 2>/dev/null &
        spin $! "Backing up all service data (this may take a while)…"
        size=$(du -sh "$dest" | cut -f1)
        log_ok "All data backed up ($size) → $dest"
    fi

# List existing backups
[private]
_list-backups:
    #!/usr/bin/env bash
    set -euo pipefail
    found=0
    for f in {{ backup_dir }}/*.tar.gz {{ backup_dir }}/*.tar.gz.gpg {{ backup_dir }}/retired/*.tar.gz; do
        [[ -f "$f" ]] && found=1 && break
    done
    if [[ $found -eq 0 ]]; then
        echo "No backups found in {{ backup_dir }}/"
        exit 0
    fi
    echo "╭──────────────────────────────────────────────────────────────╮"
    echo "│  Nexus — Backups                                             │"
    echo "╰──────────────────────────────────────────────────────────────╯"
    echo ""
    printf "%-15s %-8s  %s\n" "TYPE" "SIZE" "FILE"
    printf "%-15s %-8s  %s\n" "────" "────" "────"
    for f in {{ backup_dir }}/*.tar.gz {{ backup_dir }}/*.tar.gz.gpg {{ backup_dir }}/retired/*.tar.gz; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        size=$(du -sh "$f" | cut -f1)
        case "$name" in
            configs-*)  type="configs" ;;
            secrets-*)  type="secrets" ;;
            data-*)     type="data"    ;;
            *)          type="retired" ;;
        esac
        printf "%-15s %-8s  %s\n" "$type" "$size" "$name"
    done

# Restore a backup file
[group('backup')]
restore file:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    backup="{{ file }}"
    if [[ ! -f "$backup" ]]; then
        backup="{{ backup_dir }}/{{ file }}"
    fi
    if [[ ! -f "$backup" ]]; then
        log_err "Backup file not found: {{ file }}"; exit 1
    fi
    log_step "Inspecting backup: $backup"
    echo "  Contents:"
    tar -tzf "$backup" | head -20 | sed 's/^/    /'
    echo ""
    read -p "  Restore to {{ root_dir }}? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "Cancelled"
        exit 0
    fi
    tar -xzf "$backup" -C "{{ root_dir }}"
    log_ok "Restored from $backup"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  SYNC                                                                      ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Check that compose.yaml includes all services (also runs as pre-commit hook)
[private]
_check-sync:
    @"{{ scripts_dir }}/sync-compose.sh" --check

# Add missing services to compose.yaml and report orphans
[group('sync')]
sync *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    args="{{ args }}"
    if [[ "$args" == *"--help"* || "$args" == *"-h"* ]]; then
        "{{ scripts_dir }}/sync-compose.sh" --help
    elif [[ " $args " == *" --remove-orphans "* || "$args" == "--remove-orphans" ]]; then
        log_step "Syncing compose.yaml…"
        "{{ scripts_dir }}/sync-compose.sh" --sync
        log_step "Removing orphans…"
        "{{ scripts_dir }}/sync-compose.sh" --remove-orphans
    elif [[ -n "$args" && "$args" != -* ]]; then
        log_step "Syncing $args…"
        "{{ scripts_dir }}/sync-compose.sh" --sync "$args"
    else
        log_step "Syncing compose.yaml…"
        "{{ scripts_dir }}/sync-compose.sh" --sync
    fi

# Generate config files from .template files (excludes .env.template)
[group('sync')]
templates:
    #!/usr/bin/env bash
    set -euo pipefail

    # Load root .env
    if [[ ! -f "{{ root_dir }}/.env" ]]; then
        source "{{ helpers }}"
        log_err ".env file not found"
        exit 1
    fi
    set -a
    source "{{ root_dir }}/.env"
    set +a

    echo "Generating config files from templates..."
    rendered=0
    failed=0
    total=0

    # Collect templates first
    mapfile -t template_files < <(find "{{ data_path }}" \
        -path "*/syncthing/data/*" -prune -o \
        -path "*/.claude/*" -prune -o \
        -type f -name "*.template" -print 2>/dev/null)
    total=${#template_files[@]}
    current=0

    for template in "${template_files[@]}"; do
        [[ -z "$template" ]] && continue
        [[ "$template" == *".env.template" ]] && continue
        ((current++)) || true

        # Skip templates inside git repositories (submodules/cloned projects)
        template_dir=$(dirname "$template")
        while [[ "$template_dir" != "{{ data_path }}" && "$template_dir" != "/" ]]; do
            if [[ -e "$template_dir/.git" ]]; then
                continue 2  # Skip this template
            fi
            template_dir=$(dirname "$template_dir")
        done

        # Extract service name from path (e.g., /mnt/data/docker/adguard/sync/... -> adguard)
        rel_path="${template#{{ data_path }}/}"
        service_name="${rel_path%%/*}"

        # Source service-specific .env if it exists (in a subshell to isolate vars)
        (
            # Re-source root .env first (subshell starts fresh)
            set -a
            source "{{ root_dir }}/.env"
            # Then overlay service-specific .env
            if [[ -f "{{ services_dir }}/${service_name}/.env" ]]; then
                source "{{ services_dir }}/${service_name}/.env"
            fi
            set +a

            output="${template%.template}"

            # Check for unset variables
            vars_in_template=$(grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' "$template" 2>/dev/null | sort -u || true)
            missing_vars=""
            for var in $vars_in_template; do
                var_name="${var:2:-1}"  # Strip ${ and }
                if [[ -z "${!var_name:-}" ]]; then
                    missing_vars+=" $var"
                fi
            done

            if [[ -n "$missing_vars" ]]; then
                printf '  \033[31m✗\033[0m %s\n' "$template"
                echo "    Missing:$missing_vars"
                exit 1  # Signal failure to parent
            fi

            # Generate output
            if envsubst < "$template" > "$output" 2>/dev/null; then
                chmod 644 "$output"
                printf '  \033[32m✓\033[0m %s\n' "$template"
                exit 0  # Success
            else
                printf '  \033[31m✗\033[0m %s (envsubst failed)\n' "$template"
                exit 1  # Failure
            fi
        )

        if [[ $? -eq 0 ]]; then
            ((rendered++)) || true
        else
            ((failed++)) || true
        fi
    done

    echo ""
    if ((failed > 0)); then
        source "{{ helpers }}"
        log_err "$rendered generated, $failed failed"
        exit 1
    else
        source "{{ helpers }}"
        log_ok "All templates ($rendered) generated successfully"
    fi

# Alias for templates
[group('sync')]
template: templates

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  MAINTENANCE                                                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Clean up Docker resources (dangling images, stopped containers, unused networks)
[group('maintenance')]
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    prune_tmp=$(mktemp)
    docker system prune -f > "$prune_tmp" 2>&1 &
    spin $! "Pruning unused Docker resources…"
    cat "$prune_tmp"
    rm -f "$prune_tmp"
    echo ""
    echo "Disk usage:"
    docker system df
    log_ok "Cleanup complete"

# Setup pre-commit hooks and Docker network
[group('maintenance')]
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    log_step "Setting up development environment…"
    if command -v pre-commit &>/dev/null; then
        pre-commit install
        pre-commit install --hook-type commit-msg
        log_ok "Pre-commit hooks installed"
    else
        log_warn "pre-commit not found (install with: pip install pre-commit)"
    fi
    if ! docker network inspect nexus &>/dev/null; then
        log_step "Creating Docker network 'nexus'…"
        docker network create nexus --subnet 172.52.0.0/16 --gateway 172.52.0.1
        log_ok "Docker network 'nexus' created with subnet 172.52.0.0/16"
    else
        log_ok "Docker network 'nexus' exists"
    fi
    log_ok "Setup complete"

# Update README with service listings
[group('maintenance')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    python_cmd="python3"
    [[ -f "{{ root_dir }}/.venv/bin/python" ]] && python_cmd="{{ root_dir }}/.venv/bin/python"
    if [[ -f "{{ root_dir }}/update-readme.py" ]]; then
        log_step "Updating README.md…"
        "$python_cmd" "{{ root_dir }}/update-readme.py"
        log_ok "README.md updated"
    else
        log_err "update-readme.py not found"; exit 1
    fi

# Check a service, prerequisites, or sync status
[group('maintenance')]
check *what:
    #!/usr/bin/env bash
    set -euo pipefail
    case "${1:-prereqs}" in
        sync)     just _check-sync ;;
        prereqs)  just _check-prereqs ;;
        *)
            # Treat as a service name
            if [[ -d "{{ services_dir }}/$1" ]]; then
                just _check-service "$1"
            else
                echo "Unknown argument '$1'. Not a service or subcommand." >&2
                echo "Usage: just check [<service>|prereqs|sync]" >&2
                exit 1
            fi
            ;;
    esac

# Quick health summary for a single service
[private]
_check-service service:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    compose="$SVC_COMPOSE"
    svc_names="$SVC_NAMES"
    image=$(yq -r '.services[].image // "(build)"' "$compose" | head -1)

    # Single docker inspect call → extract everything with jq
    _gather() {
        docker inspect "{{ service }}" 2>/dev/null || echo "[]"
    }
    spin_while "Checking {{ service }}…" _gather || true
    json="$SPIN_OUTPUT"

    # Color helpers
    red='\033[31m'; grn='\033[32m'; ylw='\033[33m'; dim='\033[2m'; rst='\033[0m'

    if [[ "$json" == "[]" ]]; then
        state="not running"; health="-"; started="-"; restarts="-"
        ports_raw=""; container_ip="-"; health_log=""
    else
        state=$(jq -r '.[0].State.Status // "unknown"' <<< "$json")
        health=$(jq -r 'if .[0].State.Health then .[0].State.Health.Status else "n/a" end' <<< "$json")
        started=$(jq -r '.[0].State.StartedAt // "-"' <<< "$json" | head -c 19)
        restarts=$(jq -r '.[0].RestartCount // 0' <<< "$json")
        container_ip=$(jq -r '[.[0].NetworkSettings.Networks[]] | first | .IPAddress // "n/a"' <<< "$json" 2>/dev/null | head -c 15)
        # Health log entries
        health_log=$(jq -r '.[0].State.Health.Log // [] | .[] | "\(.End[0:19])|exit=\(.ExitCode)"' <<< "$json" 2>/dev/null || true)
    fi

    case "$state" in running) sc="$grn";; exited) sc="$red";; *) sc="$ylw";; esac
    case "$health" in healthy) hc="$grn";; unhealthy) hc="$red";; starting) hc="$ylw";; *) hc="$dim";; esac

    printf '\n'
    if [[ "$health" == "n/a" ]]; then
        printf '  %b{{ service }}%b (%b%s%b)\n' "$sc" "$rst" "$sc" "$state" "$rst"
    else
        printf '  %b{{ service }}%b (%b%s%b) — health: %b%s%b\n' "$sc" "$rst" "$sc" "$state" "$rst" "$hc" "$health" "$rst"
    fi
    printf '\n'
    printf '    %bimage:%b     %s\n' "$dim" "$rst" "$image"
    printf '    %bstarted:%b   %s\n' "$dim" "$rst" "$started"
    printf '    %brestarts:%b  %s\n' "$dim" "$rst" "$restarts"
    printf '    %bip:%b        %s\n' "$dim" "$rst" "${container_ip:-n/a}"

    # Ports (from jq)
    printf '    %bports:%b' "$dim" "$rst"
    if [[ "$json" == "[]" ]]; then
        printf '      (none)\n'
    else
        port_lines=$(jq -r '.[0].NetworkSettings.Ports // {} | to_entries[] | "\(.key)|\(.value // [] | map("\(.HostIp):\(.HostPort)") | join(","))"' <<< "$json" 2>/dev/null || true)
        if [[ -z "$port_lines" ]]; then
            printf '      (none)\n'
        else
            printf '\n'
            while IFS='|' read -r cport host; do
                [[ -z "$cport" ]] && continue
                if [[ -n "$host" && "$host" != ":" && "$host" != "" ]]; then
                    host_bind="${host%%,*}"
                    printf '      %b⇄%b %s → %s\n' "$grn" "$rst" "$host_bind" "$cport"
                else
                    printf '      %b·%b %s %b(container only)%b\n' "$dim" "$rst" "$cport" "$dim" "$rst"
                fi
            done <<< "$port_lines"
        fi
    fi

    # Mounts: defined vs actual (single jq call per container)
    printf '    %bmounts:%b\n' "$dim" "$rst"

    declare -A actual_by_dest
    for svc in $svc_names; do
        svc_json=$(docker inspect "$svc" 2>/dev/null || echo "[]")
        [[ "$svc_json" == "[]" ]] && continue
        while IFS='|' read -r src dest; do
            [[ -z "$dest" ]] && continue
            actual_by_dest["$dest"]="${src}:${dest}"
        done < <(jq -r '.[0].Mounts[]? | "\(.Source)|\(.Destination)"' <<< "$svc_json" 2>/dev/null)
    done

    has_volumes=false
    for svc in $svc_names; do
        svc_vols=$(yq -r ".services[\"$svc\"].volumes[]" "$compose" 2>/dev/null || true)
        [[ -z "$svc_vols" ]] && continue
        has_volumes=true
        if [[ $(echo "$svc_names" | wc -w) -gt 1 ]]; then
            printf '      %b[%s]%b\n' "$dim" "$svc" "$rst"
        fi
        while IFS= read -r vol; do
            [[ -z "$vol" ]] && continue
            dest=$(sed 's/:ro$//' <<< "$vol" | sed 's/:rw$//' | rev | cut -d: -f1 | rev)
            actual="${actual_by_dest[$dest]:-}"
            actual_src="${actual%%:*}"
            if [[ "$vol" == *'${'* ]]; then
                var_name=$(grep -oP '\$\{\K[A-Z_][A-Z0-9_]*' <<< "$vol" | head -1)
                var_value="${!var_name:-}"
                src_part="${vol%%:*}"
                expanded_src=$(envsubst <<< "$src_part" 2>/dev/null || echo "")
                if [[ -n "$actual_src" && "$actual_src" == /* ]]; then
                    printf '      %b✓%b %s\n' "$grn" "$rst" "$vol"
                    printf '        %b→ %s%b\n' "$dim" "$actual_src" "$rst"
                elif [[ -n "$var_value" && -n "$expanded_src" ]]; then
                    printf '      %b✓%b %s\n' "$grn" "$rst" "$vol"
                    printf '        %b→ %s (env)%b\n' "$dim" "$expanded_src" "$rst"
                else
                    printf '      %b⚠%b %s\n' "$ylw" "$rst" "$vol"
                    printf '        %b→ MISSING: %s not set%b\n' "$red" "$rst" "$var_name"
                fi
            else
                printf '      %s\n' "$vol"
            fi
        done <<< "$svc_vols"
    done
    [[ "$has_volumes" == "false" ]] && printf '      (none)\n'

    # Health check log
    if [[ -n "$health_log" ]]; then
        printf '\n    %b── recent health checks ──%b\n' "$dim" "$rst"
        tail -3 <<< "$health_log" | while IFS='|' read -r ts_raw code_raw; do
            ts="${ts_raw:0:19}"
            code="${code_raw#exit=}"
            [[ -z "$ts" ]] && continue
            if [[ "$code" == "0" ]]; then
                printf '      %b✓%b %s\n' "$grn" "$rst" "$ts"
            else
                printf '      %b✗%b %s (exit %s)\n' "$red" "$rst" "$ts" "$code"
            fi
        done
    fi

    # Recent logs
    printf '\n    %b── recent logs ──%b\n' "$dim" "$rst"
    docker compose logs --tail=8 $svc_names 2>/dev/null | sed 's/^/    /' || echo "    (no logs)"
    printf '\n'

# Check prerequisites (docker, compose, direnv, etc.)
[private]
_check-prereqs:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    log_step "Checking prerequisites…"
    ok=true
    for cmd in docker git; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd ($(command -v $cmd))"
        else
            log_err "$cmd"
            ok=false
        fi
    done
    if docker compose version &>/dev/null; then
        log_ok "docker compose ($(docker compose version --short 2>/dev/null))"
    else
        log_err "docker compose"
        ok=false
    fi
    for cmd in just direnv pre-commit python3 fzf jq yq; do
        if command -v "$cmd" &>/dev/null; then
            log_ok "$cmd"
        else
            log_warn "$cmd (optional)"
        fi
    done
    echo ""
    if $ok; then
        log_ok "All required tools present"
    else
        log_err "Missing required tools"
        exit 1
    fi

# Run docker compose command directly for a service
[group('maintenance')]
compose service *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ helpers }}"
    resolve_service "{{ service }}" "{{ services_dir }}"
    docker compose {{ args }} $SVC_NAMES

# Edit a service's compose file in $EDITOR
[group('maintenance')]
edit service:
    ${EDITOR:-vi} "{{ services_dir }}/{{ service }}/compose.yaml"
