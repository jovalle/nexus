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

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DEFAULT / HELP                                                          ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Show all available recipes
@default:
    just --list --unsorted

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  SERVICE MANAGEMENT                                                      ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Start a service (or all services)
[group('manage')]
up *service:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ service }}" ]]; then
        echo "Starting all services..."
        docker compose up -d --remove-orphans
        echo "✓ All services started"
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        echo "Starting {{ service }} (${svc_names//$'\n'/ })..."
        docker compose up -d --remove-orphans $svc_names
        echo "✓ {{ service }} started"
    fi

# Stop a service (or all services) — removes containers and networks
[group('manage')]
down *service:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ service }}" ]]; then
        echo "Stopping all services..."
        docker compose down --timeout 30 --remove-orphans
        echo "✓ All services stopped"
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        echo "Stopping {{ service }} (${svc_names//$'\n'/ })..."
        docker compose stop --timeout 30 $svc_names
        docker compose rm -f $svc_names
        echo "✓ {{ service }} stopped"
    fi

# Restart a service (or all services)
[group('manage')]
restart *service:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ service }}" ]]; then
        echo "Restarting all services..."
        docker compose restart
        echo "✓ All services restarted"
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        echo "Restarting {{ service }}..."
        docker compose restart $svc_names
        echo "✓ {{ service }} restarted"
    fi

# Recreate a service (pull + force-recreate)
[group('manage')]
recreate service:
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    echo "Recreating {{ service }} (${svc_names//$'\n'/ })..."
    docker compose pull $svc_names
    docker compose up -d --force-recreate --remove-orphans $svc_names
    echo "✓ {{ service }} recreated"

# Update a service (pull + up) or all services
[group('manage')]
update *service:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ service }}" ]]; then
        echo "Updating all services..."
        docker compose pull
        docker compose up -d --remove-orphans
        echo "✓ All services updated"
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        echo "Updating {{ service }}..."
        docker compose pull $svc_names
        docker compose up -d --remove-orphans $svc_names
        echo "✓ {{ service }} updated"
    fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  STATUS & LISTING                                                        ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Show container status for a service (or all)
[group('inspect')]
ps *service:
    #!/usr/bin/env bash
    set -euo pipefail
    go_fmt='{{ _l }}.State{{ _r }}|{{ _l }}.Status{{ _r }}'
    if [[ -z "{{ service }}" ]]; then
        echo "╭──────────────────────────────────────────────────────────────╮"
        echo "│  Nexus — Container Status                                    │"
        echo "╰──────────────────────────────────────────────────────────────╯"
        echo ""
        printf "%-22s %-12s %-10s %s\n" "SERVICE" "STATE" "HEALTH" "UPTIME"
        printf "%-22s %-12s %-10s %s\n" "───────" "─────" "──────" "──────"
        for dir in {{ services_dir }}/*/; do
            svc=$(basename "$dir")
            [[ "$svc" == .* ]] && continue
            compose="{{ services_dir }}/$svc/compose.yaml"
            [[ -f "$compose" ]] || continue
            info=$(docker ps -a --filter "name=^${svc}$" --format "$go_fmt" 2>/dev/null | head -1)
            if [[ -n "$info" ]]; then
                state=$(echo "$info" | cut -d'|' -f1)
                status=$(echo "$info" | cut -d'|' -f2)
                health="-"
                [[ "$status" == *"(healthy)"* ]] && health="healthy"
                [[ "$status" == *"(unhealthy)"* ]] && health="unhealthy"
                [[ "$status" == *"health: starting"* ]] && health="starting"
                uptime="-"
                if [[ "$state" == "running" ]]; then
                    uptime=$(echo "$status" | grep -oP 'Up \K.*' | sed 's/ (.*)//')
                fi
                case "$state" in
                    running)   sc="\033[32m" ;;
                    exited)    sc="\033[31m" ;;
                    *)         sc="\033[33m" ;;
                esac
                case "$health" in
                    healthy)   hc="\033[32m" ;;
                    unhealthy) hc="\033[31m" ;;
                    starting)  hc="\033[33m" ;;
                    *)         hc="\033[0m"  ;;
                esac
                printf "${sc}%-22s\033[0m %-12s ${hc}%-10s\033[0m %s\n" "$svc" "$state" "$health" "$uptime"
            else
                printf "\033[2m%-22s %-12s %-10s %s\033[0m\n" "$svc" "not created" "-" "-"
            fi
        done
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        docker compose -f "$compose" ps
    fi

# List all available services
[group('inspect')]
ls *filter:
    #!/usr/bin/env bash
    set -euo pipefail
    names_fmt='{{ _l }}.Names{{ _r }}'
    running=$(docker ps --format "$names_fmt" 2>/dev/null)
    echo "╭──────────────────────────────────────────────────────────────╮"
    echo "│  Nexus — Services                                            │"
    echo "╰──────────────────────────────────────────────────────────────╯"
    echo ""
    total=0; up=0; down=0
    for dir in {{ services_dir }}/*/; do
        svc=$(basename "$dir")
        [[ "$svc" == .* ]] && continue
        [[ -n "{{ filter }}" ]] && ! echo "$svc" | grep -qi "{{ filter }}" && continue
        compose="{{ services_dir }}/$svc/compose.yaml"
        ((total++)) || true
        if [[ -f "$compose" ]] && echo "$running" | grep -qx "$svc" 2>/dev/null; then
            printf "  \033[32m●\033[0m %s\n" "$svc"
            ((up++)) || true
        else
            printf "  \033[2m○ %s\033[0m\n" "$svc"
            ((down++)) || true
        fi
    done
    echo ""
    echo "Total: $total  Running: $up  Stopped: $down"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  LOGGING                                                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Follow logs for a service (or all running containers)
[group('logs')]
logs service *args:
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    docker compose logs -f --tail=100 $svc_names {{ args }}

# Show last N lines of logs (default 200)
[group('logs')]
logs-tail service lines="200":
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    docker compose logs --tail={{ lines }} $svc_names

# Show logs since a time (e.g. "1h", "30m", "2024-01-01")
[group('logs')]
logs-since service since:
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    docker compose logs --since={{ since }} --tail=500 $svc_names

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  DEBUGGING                                                               ║
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
    stats_fmt='table {{ _l }}.Name{{ _r }}\t{{ _l }}.CPUPerc{{ _r }}\t{{ _l }}.MemUsage{{ _r }}\t{{ _l }}.NetIO{{ _r }}\t{{ _l }}.BlockIO{{ _r }}'
    if [[ -z "{{ service }}" ]]; then
        docker stats --no-stream --format "$stats_fmt" | head -1
        docker stats --no-stream --format "$stats_fmt" | tail -n +2 | sort
    else
        docker stats --no-stream "{{ service }}"
    fi

# Inspect a service's compose config (resolved)
[group('debug')]
config service:
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    docker compose config $svc_names

# Validate compose file(s) for a service (or all)
[group('debug')]
validate *service:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0
    if [[ -z "{{ service }}" ]]; then
        echo "Validating all compose files..."
        for dir in {{ services_dir }}/*/; do
            svc=$(basename "$dir")
            [[ "$svc" == .* ]] && continue
            compose="{{ services_dir }}/$svc/compose.yaml"
            [[ -f "$compose" ]] || continue
            if docker compose -f "$compose" config > /dev/null 2>&1; then
                printf "  \033[32m✓\033[0m %s\n" "$svc"
            else
                printf "  \033[31m✗\033[0m %s\n" "$svc"
                docker compose -f "$compose" config 2>&1 | grep -i "error" | sed 's/^/    /' || true
                ((errors++)) || true
            fi
        done
        echo ""
        if [[ $errors -eq 0 ]]; then
            echo "✓ All compose files valid"
        else
            echo "✗ $errors service(s) have invalid compose files" >&2
            exit 1
        fi
    else
        compose="{{ services_dir }}/{{ service }}/compose.yaml"
        if [[ ! -f "$compose" ]]; then
            echo "✗ Service '{{ service }}' not found" >&2; exit 1
        fi
        if docker compose -f "$compose" config > /dev/null 2>&1; then
            echo "✓ {{ service }} compose file is valid"
        else
            echo "✗ {{ service }} compose file has errors:" >&2
            docker compose -f "$compose" config 2>&1
            exit 1
        fi
    fi

# Inspect container details (env, mounts, network, etc.)
[group('debug')]
inspect service:
    #!/usr/bin/env bash
    set -euo pipefail
    fmt_image='{{ _l }}.Config.Image{{ _r }}'
    fmt_ports='{{ _l }}range $p, $conf := .NetworkSettings.Ports{{ _r }}  {{ _l }}$p{{ _r }} -> {{ _l }}range $conf{{ _r }}{{ _l }}.HostIp{{ _r }}:{{ _l }}.HostPort{{ _r }}{{ _l }}end{{ _r }}{{ _l }}"\n"{{ _r }}{{ _l }}end{{ _r }}'
    fmt_mounts='{{ _l }}range .Mounts{{ _r }}  {{ _l }}.Source{{ _r }} -> {{ _l }}.Destination{{ _r }} ({{ _l }}.Type{{ _r }}){{ _l }}"\n"{{ _r }}{{ _l }}end{{ _r }}'
    fmt_nets='{{ _l }}range $k, $v := .NetworkSettings.Networks{{ _r }}  {{ _l }}$k{{ _r }}: {{ _l }}$v.IPAddress{{ _r }}{{ _l }}"\n"{{ _r }}{{ _l }}end{{ _r }}'
    fmt_env='{{ _l }}range .Config.Env{{ _r }}  {{ _l }}.{{ _r }}{{ _l }}"\n"{{ _r }}{{ _l }}end{{ _r }}'
    echo "╭──────────────────────────────────────────────────────────────╮"
    echo "│  {{ service }} — Container Details                          │"
    echo "╰──────────────────────────────────────────────────────────────╯"
    echo ""
    echo "── Image ──"
    docker inspect "{{ service }}" --format "$fmt_image" 2>/dev/null || echo "  (not running)"
    echo ""
    echo "── Ports ──"
    docker inspect "{{ service }}" --format "$fmt_ports" 2>/dev/null || echo "  (none)"
    echo "── Mounts ──"
    docker inspect "{{ service }}" --format "$fmt_mounts" 2>/dev/null || echo "  (none)"
    echo "── Networks ──"
    docker inspect "{{ service }}" --format "$fmt_nets" 2>/dev/null || echo "  (none)"
    echo "── Environment ──"
    docker inspect "{{ service }}" --format "$fmt_env" 2>/dev/null | grep -v -E '(PASSWORD|SECRET|TOKEN|KEY)=' | head -30 || echo "  (none)"
    echo "  (secrets redacted)"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  EXPAND — Add New Services                                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Create a new service from template
[group('expand')]
new service:
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{ services_dir }}/{{ service }}"
    if [[ -d "$target" ]]; then
        echo "✗ Service '{{ service }}' already exists at $target" >&2
        exit 1
    fi
    # Check if there's an archived version
    archived="{{ archive_dir }}/{{ service }}"
    if [[ -d "$archived" ]]; then
        echo "Found archived version of '{{ service }}'."
        read -p "Restore from archive instead? [y/N] " restore
        if [[ "$restore" =~ ^[Yy]$ ]]; then
            mv "$archived" "$target"
            echo "✓ Restored {{ service }} from archive"
            exit 0
        fi
    fi
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
          - \${DATA_PATH}/${svc}:/data         # Adjust mount path per docs
        networks:
          - nexus

    networks:
      nexus:
        external: true
    EOF
    # Fix indentation (remove leading 4-space indent from heredoc)
    sed -i 's/^    //' "$target/compose.yaml"
    echo "✓ Created {{ service }} at $target/compose.yaml"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $target/compose.yaml — fill in <IMAGE>, <PORT>, etc."
    echo "  2. Add any required env vars to .env"
    echo "  3. Run: just validate {{ service }}"
    echo "  4. Run: just up {{ service }}"

# Duplicate an existing service as a starting point
[group('expand')]
clone source target:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ services_dir }}/{{ source }}"
    dst="{{ services_dir }}/{{ target }}"
    if [[ ! -d "$src" ]]; then
        echo "✗ Source service '{{ source }}' not found" >&2; exit 1
    fi
    if [[ -d "$dst" ]]; then
        echo "✗ Target '{{ target }}' already exists" >&2; exit 1
    fi
    cp -r "$src" "$dst"
    sed -i "s/{{ source }}/{{ target }}/g" "$dst/compose.yaml"
    echo "✓ Cloned {{ source }} → {{ target }}"
    echo "  Edit {{ services_dir }}/{{ target }}/compose.yaml to customize"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  RETIRE — Gracefully Decommission Services                              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Retire a service: stop gracefully, backup config, move to archive
[group('retire')]
retire service:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ services_dir }}/{{ service }}"
    dst="{{ archive_dir }}/{{ service }}"
    compose="$src/compose.yaml"
    if [[ ! -d "$src" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    printf '╭%62s╮\n' '' | tr ' ' '─'
    printf '│  %-60s│\n' 'Retiring: {{ service }}'
    printf '╰%62s╯\n' '' | tr ' ' '─'
    echo ""
    # 1. Stop the service gracefully
    if [[ -f "$compose" ]]; then
        echo "① Stopping {{ service }}..."
        svc_names=$(yq -r '.services | keys | .[]' "$compose")
        docker compose stop --timeout 30 $svc_names 2>&1 | sed 's/^/   /' || true
        docker compose rm -f $svc_names 2>&1 | sed 's/^/   /' || true
    fi
    # 2. Backup the config before archiving
    echo "② Backing up config..."
    mkdir -p "{{ backup_dir }}/retired"
    tar -czf "{{ backup_dir }}/retired/{{ service }}-{{ ts }}.tar.gz" \
        -C "{{ services_dir }}" "{{ service }}" 2>/dev/null || true
    # 3. Move to archive
    echo "③ Archiving..."
    mkdir -p "{{ archive_dir }}"
    if [[ -d "$dst" ]]; then
        mv "$src" "${dst}-{{ ts }}"
        echo "  (previous archive exists, saved as {{ service }}-{{ ts }})"
    else
        mv "$src" "$dst"
    fi
    # 4. Remove from root compose.yaml
    echo "④ Updating compose.yaml..."
    "{{ scripts_dir }}/sync-compose.sh" --remove-orphans 2>&1 | sed 's/^/   /'
    echo ""
    echo "✓ {{ service }} retired"
    echo "  Config backup: {{ backup_dir }}/retired/{{ service }}-{{ ts }}.tar.gz"
    echo "  Archived to:   {{ archive_dir }}/{{ service }}"
    echo ""
    echo "  To restore: just unretire {{ service }}"

# Restore a retired service from archive
[group('retire')]
unretire service:
    #!/usr/bin/env bash
    set -euo pipefail
    src="{{ archive_dir }}/{{ service }}"
    dst="{{ services_dir }}/{{ service }}"
    if [[ ! -d "$src" ]]; then
        echo "✗ No archive found for '{{ service }}'" >&2
        matches=$(ls -d {{ archive_dir }}/{{ service }}-* 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            echo "  Found timestamped archives:"
            echo "$matches" | sed 's/^/    /'
            echo "  Move the desired version to {{ archive_dir }}/{{ service }} and try again"
        fi
        exit 1
    fi
    if [[ -d "$dst" ]]; then
        echo "✗ Service '{{ service }}' already exists in services/" >&2; exit 1
    fi
    mv "$src" "$dst"
    # Add back to root compose.yaml
    "{{ scripts_dir }}/sync-compose.sh" --sync 2>&1 | sed 's/^/  /'
    echo "✓ Restored {{ service }} from archive"
    echo "  Run: just up {{ service }}"

# List archived (retired) services
[group('retire')]
archived:
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
# ║  BACKUP                                                                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Backup everything: configs, env/secrets, and optionally data
[group('backup')]
backup *scope:
    #!/usr/bin/env bash
    set -euo pipefail
    scope="{{ scope }}"
    if [[ -z "$scope" ]]; then
        scope="all"
    fi
    case "$scope" in
        config|configs)
            just backup-configs
            ;;
        env|secrets)
            just backup-secrets
            ;;
        data)
            just backup-data
            ;;
        all)
            just backup-configs
            just backup-secrets
            just backup-data
            echo ""
            echo "✓ Full backup complete → {{ backup_dir }}/"
            ;;
        *)
            echo "Usage: just backup [config|secrets|data|all]" >&2
            exit 1
            ;;
    esac

# Backup all service compose configs
[group('backup')]
backup-configs:
    #!/usr/bin/env bash
    set -euo pipefail
    dest="{{ backup_dir }}/configs-{{ ts }}.tar.gz"
    mkdir -p "{{ backup_dir }}"
    echo "Backing up service configs..."
    tar -czf "$dest" \
        -C "{{ root_dir }}" \
        --exclude='services/.template' \
        services/ 2>/dev/null
    size=$(du -sh "$dest" | cut -f1)
    echo "✓ Configs backed up ($size) → $dest"

# Backup .env and secrets (encrypted with optional GPG passphrase)
[group('backup')]
backup-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    dest="{{ backup_dir }}/secrets-{{ ts }}.tar.gz"
    mkdir -p "{{ backup_dir }}"
    echo "Backing up secrets and environment files..."
    files=()
    [[ -f "{{ root_dir }}/.env" ]] && files+=(".env")
    [[ -f "{{ root_dir }}/.env.example" ]] && files+=(".env.example")
    # Collect any per-service .env or secret files
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
    tar -czf "$dest" -C "{{ root_dir }}" "${files[@]}" 2>/dev/null || true
    size=$(du -sh "$dest" | cut -f1)
    echo "✓ Secrets backed up ($size) → $dest"
    echo ""
    echo "  ⚠  This file contains sensitive data. Store securely."
    if command -v gpg &>/dev/null; then
        read -p "  Encrypt with GPG passphrase? [y/N] " encrypt
        if [[ "$encrypt" =~ ^[Yy]$ ]]; then
            gpg --symmetric --cipher-algo AES256 "$dest"
            rm "$dest"
            echo "  ✓ Encrypted → ${dest}.gpg"
        fi
    fi

# Backup persistent data volumes for a service (or all)
[group('backup')]
backup-data *service:
    #!/usr/bin/env bash
    set -euo pipefail
    data="{{ data_path }}"
    if [[ ! -d "$data" ]]; then
        echo "✗ Data path not found: $data" >&2
        echo "  Set DATA_PATH in .env" >&2
        exit 1
    fi
    mkdir -p "{{ backup_dir }}"
    if [[ -n "{{ service }}" ]]; then
        svc_data="$data/{{ service }}"
        if [[ ! -d "$svc_data" ]]; then
            echo "✗ No data directory for '{{ service }}' at $svc_data" >&2; exit 1
        fi
        dest="{{ backup_dir }}/data-{{ service }}-{{ ts }}.tar.gz"
        echo "Backing up {{ service }} data..."
        echo "  ⚠  Stop the service first for a consistent backup: just stop {{ service }}"
        tar -czf "$dest" -C "$data" "{{ service }}" 2>/dev/null
        size=$(du -sh "$dest" | cut -f1)
        echo "✓ Data backed up ($size) → $dest"
    else
        dest="{{ backup_dir }}/data-all-{{ ts }}.tar.gz"
        echo "Backing up all service data from $data ..."
        echo "  ⚠  For consistent backups, stop services first: just stop"
        tar -czf "$dest" -C "$data" . 2>/dev/null
        size=$(du -sh "$dest" | cut -f1)
        echo "✓ All data backed up ($size) → $dest"
    fi

# List existing backups
[group('backup')]
backups:
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
    backup="{{ file }}"
    if [[ ! -f "$backup" ]]; then
        backup="{{ backup_dir }}/{{ file }}"
    fi
    if [[ ! -f "$backup" ]]; then
        echo "✗ Backup file not found: {{ file }}" >&2; exit 1
    fi
    echo "Restoring from: $backup"
    echo "  Contents:"
    tar -tzf "$backup" | head -20 | sed 's/^/    /'
    echo ""
    read -p "  Restore to {{ root_dir }}? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    tar -xzf "$backup" -C "{{ root_dir }}"
    echo "✓ Restored from $backup"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  SYNC                                                                    ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Check that compose.yaml includes all services (also runs as pre-commit hook)
[group('sync')]
sync-check:
    @"{{ scripts_dir }}/sync-compose.sh" --check

# Add missing services to compose.yaml and report orphans
[group('sync')]
sync *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "{{ args }}" == *"--remove-orphans"* ]]; then
        "{{ scripts_dir }}/sync-compose.sh" --sync
        "{{ scripts_dir }}/sync-compose.sh" --remove-orphans
    else
        "{{ scripts_dir }}/sync-compose.sh" --sync
    fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  MAINTENANCE                                                             ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Clean up Docker resources (dangling images, stopped containers, unused networks)
[group('maintenance')]
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Cleaning Docker resources..."
    docker system prune -f
    echo ""
    echo "Disk usage:"
    docker system df

# Setup pre-commit hooks and Docker network
[group('maintenance')]
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Setting up development environment..."
    if command -v pre-commit &>/dev/null; then
        pre-commit install
        pre-commit install --hook-type commit-msg
        echo "✓ Pre-commit hooks installed"
    else
        echo "⚠ pre-commit not found (install with: pip install pre-commit)"
    fi
    if ! docker network inspect nexus &>/dev/null; then
        docker network create nexus
        echo "✓ Docker network 'nexus' created"
    else
        echo "✓ Docker network 'nexus' exists"
    fi

# Update README with service listings
[group('maintenance')]
fmt:
    #!/usr/bin/env bash
    set -euo pipefail
    python_cmd="python3"
    [[ -f "{{ root_dir }}/.venv/bin/python" ]] && python_cmd="{{ root_dir }}/.venv/bin/python"
    if [[ -f "{{ root_dir }}/update-readme.py" ]]; then
        "$python_cmd" "{{ root_dir }}/update-readme.py"
        echo "✓ README.md updated"
    else
        echo "✗ update-readme.py not found" >&2; exit 1
    fi

# Check prerequisites (docker, compose, direnv, etc.)
[group('maintenance')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Checking prerequisites..."
    ok=true
    for cmd in docker git; do
        if command -v "$cmd" &>/dev/null; then
            printf "  \033[32m✓\033[0m %s (%s)\n" "$cmd" "$(command -v $cmd)"
        else
            printf "  \033[31m✗\033[0m %s\n" "$cmd"
            ok=false
        fi
    done
    if docker compose version &>/dev/null; then
        printf "  \033[32m✓\033[0m docker compose (%s)\n" "$(docker compose version --short 2>/dev/null)"
    else
        printf "  \033[31m✗\033[0m docker compose\n"
        ok=false
    fi
    for cmd in just direnv pre-commit python3 fzf; do
        if command -v "$cmd" &>/dev/null; then
            printf "  \033[32m✓\033[0m %s\n" "$cmd"
        else
            printf "  \033[33m⚠\033[0m %s (optional)\n" "$cmd"
        fi
    done
    echo ""
    if $ok; then
        echo "✓ All required tools present"
    else
        echo "✗ Missing required tools" >&2
        exit 1
    fi

# Run docker compose command directly for a service
[group('maintenance')]
compose service *args:
    #!/usr/bin/env bash
    set -euo pipefail
    compose="{{ services_dir }}/{{ service }}/compose.yaml"
    if [[ ! -f "$compose" ]]; then
        echo "✗ Service '{{ service }}' not found" >&2; exit 1
    fi
    svc_names=$(yq -r '.services | keys | .[]' "$compose")
    docker compose {{ args }} $svc_names

# Edit a service's compose file in $EDITOR
[group('maintenance')]
edit service:
    ${EDITOR:-vi} "{{ services_dir }}/{{ service }}/compose.yaml"
