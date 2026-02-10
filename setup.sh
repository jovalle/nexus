#!/usr/bin/env bash
# =============================================================================
# Nexus — Host Setup
# =============================================================================
# Prepares a host to run the Nexus Docker Compose service stack.
# Idempotent — safe to run multiple times. Detects what's already installed
# and skips completed steps.
#
# Usage:
#   ./setup.sh                  Interactive (prompts for every choice)
#   ./setup.sh --auto           Opinionated defaults, no prompts
#   ./setup.sh --help           Show help
#
# Pipe from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/jovalle/nexus/main/setup.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/jovalle/nexus/main/setup.sh | bash -s -- --auto
#
# Flags:
#   --auto, -y        Skip all prompts; use opinionated defaults (see below)
#   --skip-brew       Do not install Linuxbrew
#   --skip-tools      Do not install optional CLI tools (jq, yq, fzf)
#   --skip-docker     Do not attempt Docker installation
#   --dry-run         Show what would happen without changing anything
#   --help, -h        Show this help
#
# Opinionated defaults (--auto):
#   • Installs Linuxbrew (TrueNAS) or uses system package manager
#   • Installs Docker + Docker Compose (if missing)
#   • Installs just, jq, yq, fzf
#   • Creates Docker network 'nexus'
#   • Delegates brew operations to the first regular user (UID ≥ 1000)
# =============================================================================
set -euo pipefail

# ── Flags ────────────────────────────────────────────────────────────────────
AUTO=false
SKIP_BREW=false
SKIP_TOOLS=false
SKIP_DOCKER=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto|-y)      AUTO=true ;;
        --skip-brew)    SKIP_BREW=true ;;
        --skip-tools)   SKIP_TOOLS=true ;;
        --skip-docker)  SKIP_DOCKER=true ;;
        --dry-run)      DRY_RUN=true ;;
        --help|-h)
            # Print the header comment block (lines between the #!/ shebang and first code)
            awk 'NR>1 && /^[^#]/{exit} NR>1{sub(/^# ?/,"");print}' "$0"
            exit 0
            ;;
        *)
            echo "Unknown flag: $1 (try --help)" >&2
            exit 1
            ;;
    esac
    shift
done

# When stdin is not a terminal (piped), fall back to auto mode.
if [[ ! -t 0 ]]; then
    AUTO=true
fi

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; NC=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }
step()  { echo -e "${BLUE}[»]${NC} ${BOLD}$*${NC}"; }
dry()   { echo -e "${DIM}[dry-run]${NC} $*"; }

# ── Helpers ──────────────────────────────────────────────────────────────────

# Ask a yes/no question. Returns 0 for yes, 1 for no.
#   ask "Install Docker?" Y   →  default is yes
#   ask "Remove data?" N      →  default is no
ask() {
    local prompt="$1" default="${2:-Y}"
    if $AUTO; then
        [[ "${default^^}" == "Y" ]] && return 0 || return 1
    fi
    local hint
    [[ "${default^^}" == "Y" ]] && hint="[Y/n]" || hint="[y/N]"
    echo -en "  ${prompt} ${hint} "
    read -r reply </dev/tty
    reply="${reply:-$default}"
    [[ "${reply^^}" == "Y" ]]
}

# Run a command (or just print it in dry-run mode).
run() {
    if $DRY_RUN; then
        dry "$*"
        return 0
    fi
    "$@"
}

# Check if a command exists.
has() { command -v "$1" &>/dev/null; }

# ── Platform Detection ───────────────────────────────────────────────────────

detect_platform() {
    PLATFORM="unknown"
    PLATFORM_NAME="Unknown Linux"
    PLATFORM_PKG=""        # native package manager command
    PLATFORM_INSTALL=""    # install sub-command
    IS_TRUENAS=false
    IS_ROOT=false

    [[ $EUID -eq 0 ]] && IS_ROOT=true

    # TrueNAS SCALE — Debian-based but apt is locked / ephemeral
    if [[ -f /etc/version ]] && grep -qi truenas /etc/version 2>/dev/null; then
        IS_TRUENAS=true
        PLATFORM="truenas"
        PLATFORM_NAME="TrueNAS SCALE $(cat /etc/version 2>/dev/null | head -1)"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        case "${ID:-}" in
            debian|ubuntu|pop|linuxmint|raspbian)
                PLATFORM="debian"
                PLATFORM_NAME="${PRETTY_NAME:-Debian/Ubuntu}"
                PLATFORM_PKG="apt-get"
                PLATFORM_INSTALL="install -y"
                ;;
            fedora|rhel|centos|rocky|alma)
                PLATFORM="rhel"
                PLATFORM_NAME="${PRETTY_NAME:-RHEL/Fedora}"
                PLATFORM_PKG="dnf"
                PLATFORM_INSTALL="install -y"
                ;;
            alpine)
                PLATFORM="alpine"
                PLATFORM_NAME="${PRETTY_NAME:-Alpine Linux}"
                PLATFORM_PKG="apk"
                PLATFORM_INSTALL="add --no-cache"
                ;;
            arch|manjaro)
                PLATFORM="arch"
                PLATFORM_NAME="${PRETTY_NAME:-Arch Linux}"
                PLATFORM_PKG="pacman"
                PLATFORM_INSTALL="-S --noconfirm"
                ;;
            opensuse*|sles)
                PLATFORM="suse"
                PLATFORM_NAME="${PRETTY_NAME:-openSUSE}"
                PLATFORM_PKG="zypper"
                PLATFORM_INSTALL="install -y"
                ;;
            *)
                PLATFORM="linux"
                PLATFORM_NAME="${PRETTY_NAME:-Linux}"
                # Fallback: try to detect package manager
                if has apt-get;  then PLATFORM_PKG="apt-get"; PLATFORM_INSTALL="install -y";
                elif has dnf;    then PLATFORM_PKG="dnf";     PLATFORM_INSTALL="install -y";
                elif has apk;    then PLATFORM_PKG="apk";     PLATFORM_INSTALL="add --no-cache";
                elif has pacman; then PLATFORM_PKG="pacman";   PLATFORM_INSTALL="-S --noconfirm";
                fi
                ;;
        esac
    fi
}

# ── Banner ───────────────────────────────────────────────────────────────────

show_banner() {
    echo ""
    echo -e "${BOLD}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BOLD}│          Nexus — Host Setup                              │${NC}"
    echo -e "${BOLD}╰──────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "  Platform:   ${GREEN}${PLATFORM_NAME}${NC}"
    echo -e "  User:       $(whoami) (UID $EUID)"
    echo -e "  Shell:      ${SHELL:-unknown}"
    echo -e "  Date:       $(date '+%Y-%m-%d %H:%M %Z')"
    if $AUTO;    then echo -e "  Mode:       ${YELLOW}auto (opinionated defaults)${NC}"; fi
    if $DRY_RUN; then echo -e "  Mode:       ${YELLOW}dry-run (no changes)${NC}"; fi
    echo ""
}

# ── Auto-mode warning ───────────────────────────────────────────────────────

show_auto_warning() {
    if ! $AUTO; then return; fi
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│  Auto mode will:                                        │${NC}"
    echo -e "${YELLOW}│                                                         │${NC}"
    if ! $SKIP_DOCKER; then
    echo -e "${YELLOW}│  • Install Docker + Docker Compose (if missing)         │${NC}"
    fi
    if ! $SKIP_BREW && { $IS_TRUENAS || ! has apt-get; }; then
    echo -e "${YELLOW}│  • Install Linuxbrew as a package manager               │${NC}"
    fi
    if ! $SKIP_TOOLS; then
    echo -e "${YELLOW}│  • Install tools: just, jq, yq, fzf                     │${NC}"
    fi
    echo -e "${YELLOW}│  • Create Docker network 'nexus'                        │${NC}"
    echo -e "${YELLOW}│  • Configure shell profiles (.bashrc / .zshrc)          │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    if [[ -t 0 ]]; then
        sleep 2
    fi
}

# ── Platform capability matrix ───────────────────────────────────────────────

show_capabilities() {
    if $AUTO; then return; fi
    echo -e "${BOLD}  Platform capabilities:${NC}"
    echo ""
    printf "  %-30s %s\n" "Feature" "Status"
    printf "  %-30s %s\n" "───────" "──────"

    # Docker
    if has docker; then
        printf "  %-30s ${GREEN}%s${NC}\n" "Docker" "installed ($(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1))"
    else
        printf "  %-30s ${YELLOW}%s${NC}\n" "Docker" "not installed — will set up"
    fi

    # Docker Compose
    if docker compose version &>/dev/null 2>&1; then
        printf "  %-30s ${GREEN}%s${NC}\n" "Docker Compose" "installed ($(docker compose version --short 2>/dev/null))"
    elif has docker-compose; then
        printf "  %-30s ${YELLOW}%s${NC}\n" "Docker Compose" "v1 found — v2 recommended"
    else
        printf "  %-30s ${YELLOW}%s${NC}\n" "Docker Compose" "not installed — will set up"
    fi

    # Package manager
    if $IS_TRUENAS; then
        printf "  %-30s ${YELLOW}%s${NC}\n" "System package manager" "locked (TrueNAS) — use Linuxbrew"
    elif [[ -n "$PLATFORM_PKG" ]]; then
        printf "  %-30s ${GREEN}%s${NC}\n" "System package manager" "$PLATFORM_PKG"
    else
        printf "  %-30s ${RED}%s${NC}\n" "System package manager" "not detected"
    fi

    # Linuxbrew
    if has brew; then
        printf "  %-30s ${GREEN}%s${NC}\n" "Linuxbrew" "installed"
    elif $IS_TRUENAS; then
        printf "  %-30s ${YELLOW}%s${NC}\n" "Linuxbrew" "recommended (TrueNAS)"
    else
        printf "  %-30s ${DIM}%s${NC}\n" "Linuxbrew" "optional"
    fi

    # Tools
    for tool in just jq yq fzf git curl; do
        if has "$tool"; then
            printf "  %-30s ${GREEN}%s${NC}\n" "$tool" "installed"
        else
            printf "  %-30s ${DIM}%s${NC}\n" "$tool" "not installed"
        fi
    done

    # Docker network
    if docker network inspect nexus &>/dev/null 2>&1; then
        printf "  %-30s ${GREEN}%s${NC}\n" "Docker network 'nexus'" "exists"
    else
        printf "  %-30s ${DIM}%s${NC}\n" "Docker network 'nexus'" "will create"
    fi

    echo ""
}

# ── User Detection ───────────────────────────────────────────────────────────

detect_target_user() {
    TARGET_USER=""
    USER_HOME=""

    # 1. Environment variable
    if [[ -n "${NEXUS_USER:-}" ]]; then
        TARGET_USER="$NEXUS_USER"
        info "Using NEXUS_USER: $TARGET_USER"
    fi

    # 2. Existing delegate marker
    if [[ -z "$TARGET_USER" ]]; then
        while IFS=: read -r username _ uid _ _ homedir _; do
            if [[ "$uid" -ge 1000 ]] && [[ "$username" != "nobody" ]] && [[ -d "$homedir" ]]; then
                if [[ -f "$homedir/.delegate" ]]; then
                    TARGET_USER="$username"
                    info "Found existing delegate user: $TARGET_USER"
                    break
                fi
            fi
        done < /etc/passwd
    fi

    # 3. Auto-detect first regular user
    if [[ -z "$TARGET_USER" ]]; then
        local auto_user
        auto_user=$(awk -F: '$3 >= 1000 && $1 != "nobody" && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd || true)
        if [[ -n "$auto_user" ]]; then
            if $AUTO; then
                TARGET_USER="$auto_user"
                info "Auto-selected user: $TARGET_USER"
            elif ask "Detected user '${auto_user}'. Use for brew delegation?" Y; then
                TARGET_USER="$auto_user"
            fi
        fi
    fi

    # 4. Prompt
    if [[ -z "$TARGET_USER" ]] && ! $AUTO; then
        echo -n "  Enter username for brew delegation: "
        read -r TARGET_USER </dev/tty
    fi

    # 5. Fallback: current user (if not root)
    if [[ -z "$TARGET_USER" ]]; then
        if [[ $EUID -ne 0 ]]; then
            TARGET_USER="$(whoami)"
            info "Using current user: $TARGET_USER"
        else
            err "Could not determine target user. Set NEXUS_USER or pass a username."
            exit 1
        fi
    fi

    # Validate
    if ! id "$TARGET_USER" &>/dev/null; then
        err "User '$TARGET_USER' does not exist."
        exit 1
    fi

    USER_HOME=$(eval echo "~${TARGET_USER}")
}

# ── Step: Docker ─────────────────────────────────────────────────────────────

setup_docker() {
    step "Docker & Docker Compose"
    echo ""

    if $SKIP_DOCKER; then
        warn "Skipped (--skip-docker)"
        echo ""
        return
    fi

    # Docker engine
    if has docker; then
        info "Docker already installed: $(docker --version 2>/dev/null | head -1)"
    else
        if $IS_TRUENAS; then
            err "Docker not found. On TrueNAS, Docker is managed by the system."
            err "Enable Apps in System Settings → Apps to start Docker."
            echo ""
            return
        fi

        if ! ask "Install Docker?" Y; then
            warn "Skipping Docker installation"
            echo ""
            return
        fi

        info "Installing Docker via official install script..."
        if $IS_ROOT; then
            run bash -c "curl -fsSL https://get.docker.com | sh"
        else
            run bash -c "curl -fsSL https://get.docker.com | sudo sh"
            # Add user to docker group
            run sudo usermod -aG docker "$(whoami)"
            warn "You may need to log out and back in for docker group membership to take effect."
        fi
    fi

    # Docker Compose (v2 plugin)
    if docker compose version &>/dev/null 2>&1; then
        info "Docker Compose already installed: $(docker compose version --short 2>/dev/null)"
    else
        warn "Docker Compose (v2 plugin) not found."
        if [[ -n "$PLATFORM_PKG" ]] && ! $IS_TRUENAS; then
            info "Installing docker-compose-plugin..."
            if $IS_ROOT; then
                run $PLATFORM_PKG "$PLATFORM_INSTALL" docker-compose-plugin
            else
                run sudo $PLATFORM_PKG "$PLATFORM_INSTALL" docker-compose-plugin
            fi
        else
            warn "Install Docker Compose v2 manually: https://docs.docker.com/compose/install/"
        fi
    fi

    echo ""
}

# ── Step: Linuxbrew ──────────────────────────────────────────────────────────

setup_brew() {
    step "Linuxbrew (Homebrew for Linux)"
    echo ""

    if $SKIP_BREW; then
        warn "Skipped (--skip-brew)"
        echo ""
        return
    fi

    # Determine if brew is needed/wanted
    local need_brew=false
    if $IS_TRUENAS; then
        need_brew=true
        info "TrueNAS detected — Linuxbrew is the primary package manager."
    elif has brew; then
        info "Linuxbrew already installed: $(brew --version 2>/dev/null | head -1)"
        echo ""
        return
    else
        if ! ask "Install Linuxbrew? (optional on standard Linux)" N; then
            info "Skipping Linuxbrew"
            echo ""
            return
        fi
        need_brew=true
    fi

    if has brew; then
        info "Linuxbrew already installed: $(brew --version 2>/dev/null | head -1)"
        echo ""
        return
    fi

    if ! $need_brew; then
        echo ""
        return
    fi

    # Must be root (or sudo available) for installation
    if ! $IS_ROOT && ! has sudo; then
        err "Root access required to install Linuxbrew. Run with sudo."
        echo ""
        return
    fi

    detect_target_user

    local brew_dir="/home/linuxbrew/.linuxbrew"

    # TrueNAS: /home may be noexec
    if $IS_TRUENAS && mount | grep -q "on /home type zfs.*noexec" 2>/dev/null; then
        warn "/home is mounted with noexec — using /mnt/data/home instead"
        brew_dir="/mnt/data/home/linuxbrew/.linuxbrew"
        if [[ ! -L /home/linuxbrew ]]; then
            info "Creating symlink: /home/linuxbrew → /mnt/data/home/linuxbrew"
            run rm -rf /home/linuxbrew
            run mkdir -p /mnt/data/home/linuxbrew
            run ln -s /mnt/data/home/linuxbrew /home/linuxbrew
        fi
    fi

    # Install
    if [[ -d "${brew_dir}/Homebrew" ]]; then
        info "Homebrew already cloned at ${brew_dir}"
    else
        info "Installing Linuxbrew to ${brew_dir}..."
        run mkdir -p "${brew_dir}"/{bin,etc,include,lib,sbin,share,var,opt,Cellar,Caskroom,Frameworks,share/zsh/site-functions,var/homebrew/linked}
        run chown -R "${TARGET_USER}:${TARGET_USER}" "$(dirname "$brew_dir")"
        run su - "$TARGET_USER" -c "cd '$brew_dir' && git clone https://github.com/Homebrew/brew Homebrew"
        run rm -f "${brew_dir}/bin/brew"
        run su - "$TARGET_USER" -c "ln -s '${brew_dir}/Homebrew/bin/brew' '${brew_dir}/bin/brew'"

        if su - "$TARGET_USER" -c "${brew_dir}/bin/brew --version" &>/dev/null; then
            info "Linuxbrew installed: $(su - "$TARGET_USER" -c "${brew_dir}/bin/brew --version" | head -1)"
        else
            err "Linuxbrew installation failed"
            echo ""
            return
        fi
    fi

    # Shell profile — target user
    _configure_shell_profile "$USER_HOME" "$TARGET_USER" \
        "# Homebrew (Linuxbrew)" \
        'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

    # Shell profile — root (alias so brew commands delegate)
    if $IS_ROOT; then
        _configure_shell_profile "/root" "root" \
            "# Homebrew (Linuxbrew) — delegated to ${TARGET_USER}" \
            "export PATH=\"/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:\$PATH\"
alias brew='sudo -u ${TARGET_USER} /home/linuxbrew/.linuxbrew/bin/brew'"
    fi

    # Delegate marker
    if [[ ! -f "${USER_HOME}/.delegate" ]]; then
        run touch "${USER_HOME}/.delegate"
        run chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.delegate"
        info "Created delegate marker: ${USER_HOME}/.delegate"
    fi

    # Make brew available for the rest of this script
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || true

    echo ""
}

# Append a block to a user's shell profile (idempotent).
_configure_shell_profile() {
    local home="$1" user="$2" marker="$3" block="$4"
    local rc=""

    if [[ -f "${home}/.zshrc" ]]; then
        rc="${home}/.zshrc"
    elif [[ -f "${home}/.bashrc" ]]; then
        rc="${home}/.bashrc"
    else
        rc="${home}/.bashrc"
        run touch "$rc"
        [[ "$user" != "root" ]] && run chown "${user}:${user}" "$rc"
    fi

    if grep -qF "$marker" "$rc" 2>/dev/null; then
        info "Shell profile already configured: ${rc}"
        return
    fi

    if ! $DRY_RUN; then
        printf '\n%s\n%s\n' "$marker" "$block" >> "$rc"
        [[ "$user" != "root" ]] && chown "${user}:${user}" "$rc"
    fi
    info "Configured ${rc}"
}

# ── Step: CLI Tools ──────────────────────────────────────────────────────────

setup_tools() {
    step "CLI Tools"
    echo ""

    if $SKIP_TOOLS; then
        warn "Skipped (--skip-tools)"
        echo ""
        return
    fi

    # Desired tools: name → description
    local -a tools=( just jq yq fzf )
    local -a missing=()

    for t in "${tools[@]}"; do
        if has "$t"; then
            info "${t} — installed"
        else
            missing+=("$t")
        fi
    done

    # Also ensure git and curl are present (hard requirements)
    for t in git curl; do
        if ! has "$t"; then
            missing+=("$t")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        info "All tools already installed"
        echo ""
        return
    fi

    echo ""
    echo "  Tools to install: ${missing[*]}"
    echo ""

    if ! ask "Install these tools?" Y; then
        warn "Skipping tool installation"
        echo ""
        return
    fi

    _install_packages "${missing[@]}"
    echo ""
}

# Install packages using the best available package manager.
_install_packages() {
    local -a pkgs=("$@")

    # Prefer brew on TrueNAS (apt is locked).
    if $IS_TRUENAS || { ! has apt-get && has brew; }; then
        _install_via_brew "${pkgs[@]}"
        return
    fi

    # Standard Linux — use system package manager, fall back to brew.
    if [[ -n "$PLATFORM_PKG" ]]; then
        # Map generic names to distro-specific package names where needed
        local -a sys_pkgs=()
        local -a brew_only=()
        for pkg in "${pkgs[@]}"; do
            case "$pkg" in
                just)
                    # 'just' is rarely in default repos; use brew/cargo/prebuilt
                    brew_only+=("$pkg")
                    ;;
                yq)
                    # yq is not in most system repos
                    brew_only+=("$pkg")
                    ;;
                *)
                    sys_pkgs+=("$pkg")
                    ;;
            esac
        done

        if [[ ${#sys_pkgs[@]} -gt 0 ]]; then
            info "Installing via ${PLATFORM_PKG}: ${sys_pkgs[*]}"
            if $IS_ROOT; then
                run $PLATFORM_PKG "$PLATFORM_INSTALL" "${sys_pkgs[@]}"
            else
                run sudo $PLATFORM_PKG "$PLATFORM_INSTALL" "${sys_pkgs[@]}"
            fi
        fi

        if [[ ${#brew_only[@]} -gt 0 ]]; then
            if has brew; then
                _install_via_brew "${brew_only[@]}"
            else
                # Try standalone installers as last resort
                for pkg in "${brew_only[@]}"; do
                    _install_standalone "$pkg"
                done
            fi
        fi
    elif has brew; then
        _install_via_brew "${pkgs[@]}"
    else
        err "No package manager found. Install manually: ${pkgs[*]}"
    fi
}

_install_via_brew() {
    local -a pkgs=("$@")
    info "Installing via Linuxbrew: ${pkgs[*]}"

    local brew_cmd="brew"
    if $IS_ROOT && [[ -n "${TARGET_USER:-}" ]]; then
        brew_cmd="sudo -u ${TARGET_USER} /home/linuxbrew/.linuxbrew/bin/brew"
    fi

    for pkg in "${pkgs[@]}"; do
        run $brew_cmd install "$pkg" || warn "Failed to install ${pkg} via brew"
    done
}

_install_standalone() {
    local pkg="$1"
    case "$pkg" in
        just)
            info "Installing just via prebuilt binary..."
            run bash -c "curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin"
            ;;
        yq)
            info "Installing yq via binary..."
            local arch; arch=$(uname -m)
            [[ "$arch" == "x86_64" ]] && arch="amd64"
            [[ "$arch" == "aarch64" ]] && arch="arm64"
            run bash -c "curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch} -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq"
            ;;
        *)
            warn "No standalone installer for '${pkg}'. Install manually."
            ;;
    esac
}

# ── Step: Docker Network ────────────────────────────────────────────────────

setup_network() {
    step "Docker Network"
    echo ""

    if ! has docker; then
        warn "Docker not available — skipping network setup"
        echo ""
        return
    fi

    if docker network inspect nexus &>/dev/null 2>&1; then
        info "Docker network 'nexus' already exists"
    else
        if ! ask "Create Docker network 'nexus'?" Y; then
            warn "Skipping network creation"
            echo ""
            return
        fi
        run docker network create nexus
        info "Docker network 'nexus' created"
    fi

    echo ""
}

# ── Step: Nexus Repo ─────────────────────────────────────────────────────────

setup_repo() {
    step "Nexus Repository"
    echo ""

    # Detect if we're running from inside the repo already
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -f "${script_dir}/justfile" ]] && [[ -d "${script_dir}/services" ]]; then
        info "Running from Nexus repo: ${script_dir}"
        NEXUS_DIR="$script_dir"
    elif [[ -f ./justfile ]] && [[ -d ./services ]]; then
        info "Nexus repo found in current directory"
        NEXUS_DIR="$(pwd)"
    else
        info "Nexus repo not found in current directory."
        local clone_dest="${HOME}/nexus"
        if ask "Clone nexus to ${clone_dest}?" Y; then
            if [[ -d "$clone_dest" ]]; then
                warn "${clone_dest} already exists — skipping clone"
            else
                run git clone https://github.com/jovalle/nexus.git "$clone_dest"
                info "Cloned to ${clone_dest}"
            fi
            NEXUS_DIR="$clone_dest"
        else
            warn "Skipping repo clone"
            NEXUS_DIR=""
        fi
    fi

    # Create .env from example if it doesn't exist
    if [[ -n "${NEXUS_DIR:-}" ]] && [[ -f "${NEXUS_DIR}/.env.example" ]] && [[ ! -f "${NEXUS_DIR}/.env" ]]; then
        info "Creating .env from .env.example"
        run cp "${NEXUS_DIR}/.env.example" "${NEXUS_DIR}/.env"
        warn "Edit ${NEXUS_DIR}/.env with your configuration before starting services."
    fi

    echo ""
}

# ── Summary ──────────────────────────────────────────────────────────────────

show_summary() {
    echo -e "${BOLD}╭──────────────────────────────────────────────────────────╮${NC}"
    echo -e "${BOLD}│          Setup Complete                                   │${NC}"
    echo -e "${BOLD}╰──────────────────────────────────────────────────────────╯${NC}"
    echo ""

    local ok=true
    for cmd in docker git; do
        if has "$cmd"; then
            printf "  ${GREEN}✓${NC} %-18s %s\n" "$cmd" "$(command -v "$cmd")"
        else
            printf "  ${RED}✗${NC} %-18s %s\n" "$cmd" "not found"
            ok=false
        fi
    done

    if docker compose version &>/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} %-18s %s\n" "docker compose" "$(docker compose version --short 2>/dev/null)"
    else
        printf "  ${RED}✗${NC} %-18s %s\n" "docker compose" "not found"
        ok=false
    fi

    for cmd in just jq yq fzf brew; do
        if has "$cmd"; then
            printf "  ${GREEN}✓${NC} %-18s %s\n" "$cmd" "$(command -v "$cmd")"
        else
            printf "  ${DIM}○${NC} %-18s %s\n" "$cmd" "not installed"
        fi
    done

    if docker network inspect nexus &>/dev/null 2>&1; then
        printf "  ${GREEN}✓${NC} %-18s %s\n" "network: nexus" "exists"
    else
        printf "  ${DIM}○${NC} %-18s %s\n" "network: nexus" "not created"
    fi

    echo ""

    if [[ -n "${NEXUS_DIR:-}" ]]; then
        echo "  Next steps:"
        echo "    1. cd ${NEXUS_DIR}"
        echo "    2. Review and edit .env"
        echo "    3. just ls              — list services"
        echo "    4. just up <service>    — start a service"
        echo "    5. just ps              — check status"
    else
        echo "  Next steps:"
        echo "    1. Clone the nexus repo"
        echo "    2. Run ./setup.sh from inside the repo"
    fi

    echo ""

    if ! $ok; then
        warn "Some required tools are missing. Re-run setup or install manually."
    fi

    if [[ -n "${TARGET_USER:-}" ]] && $IS_ROOT; then
        info "Start a new shell or run 'source ~/.zshrc' to activate Linuxbrew."
    fi

    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    detect_platform
    show_banner
    show_auto_warning
    show_capabilities

    setup_docker
    setup_brew
    setup_tools
    setup_network
    setup_repo

    show_summary
}

main
