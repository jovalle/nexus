#!/bin/bash
#
# Nexus Setup Script
# This script sets up the development environment for managing Docker stacks
#
# Prerequisites:
#   - Running on TrueNAS Scale or compatible Linux system
#   - Root access (for brew installation)
#   - Internet connection
#
# Usage:
#   sudo ./scripts/setup.sh [username]
#
# Environment Variables:
#   NEXUS_USER - Username to delegate brew operations to (default: auto-detect or prompt)

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

print_info "Nexus Setup Script"
print_info "Root directory: $ROOT_DIR"
echo ""

# Function to find existing delegate user
find_delegate_user() {
    # Search all home directories from /etc/passwd for .delegate file
    while IFS=: read -r username _ uid _ _ homedir _; do
        # Skip system users (UID < 1000) and root
        if [ "$uid" -ge 1000 ] && [ "$username" != "nobody" ] && [ -d "$homedir" ]; then
            if [ -f "$homedir/.delegate" ]; then
                echo "$username"
                return 0
            fi
        fi
    done < /etc/passwd
    return 1
}

# Determine the target user
TARGET_USER=""

# Check for environment variable first
if [ -n "${NEXUS_USER:-}" ]; then
    TARGET_USER="$NEXUS_USER"
    print_info "Using NEXUS_USER environment variable: $TARGET_USER"
# Check for command line argument
elif [ $# -eq 1 ]; then
    TARGET_USER="$1"
    print_info "Using provided username: $TARGET_USER"
# Check for existing delegate marker
else
    DELEGATE_USER=$(find_delegate_user || true)
    if [ -n "${DELEGATE_USER:-}" ]; then
        TARGET_USER="$DELEGATE_USER"
        print_info "Found existing delegate user: $TARGET_USER"
    else
        # Try to auto-detect or prompt
        print_info "No username provided, attempting to auto-detect..."
        # Find first regular user (UID >= 1000, not nobody)
        AUTO_USER=$(awk -F: '$3 >= 1000 && $1 != "nobody" && $7 !~ /nologin|false/ {print $1; exit}' /etc/passwd || true)

        if [ -n "$AUTO_USER" ]; then
            print_info "Auto-detected user: $AUTO_USER"
            read -p "Use this user for brew operations? (Y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                TARGET_USER="$AUTO_USER"
            fi
        fi

        # If still no user, prompt for one
        if [ -z "$TARGET_USER" ]; then
            read -p "Enter username to delegate brew operations to: " TARGET_USER
            if [ -z "$TARGET_USER" ]; then
                print_error "Username cannot be empty"
                exit 1
            fi
        fi
    fi
fi

# Verify user exists
if ! id "$TARGET_USER" &>/dev/null; then
    print_error "User $TARGET_USER does not exist"
    exit 1
fi

# Get user's home directory
USER_HOME=$(eval echo ~$TARGET_USER)

# Create delegate marker file
if [ ! -f "$USER_HOME/.delegate" ]; then
    touch "$USER_HOME/.delegate"
    chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.delegate"
    print_info "Created delegate marker: $USER_HOME/.delegate"
fi
print_info "Target user: $TARGET_USER"
echo ""

# Step 1: Install Homebrew (Linuxbrew)
print_step "Step 1: Installing Homebrew (Linuxbrew)"
echo ""

if command -v brew &>/dev/null; then
    BREW_VERSION=$(brew --version | head -n 1)
    print_info "✓ Homebrew already installed: $BREW_VERSION"
else
    print_info "Running install-linuxbrew.sh..."
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo) to install brew"
        exit 1
    fi
    bash "$SCRIPT_DIR/install-linuxbrew.sh" "$TARGET_USER"
fi

echo ""

# Step 2: Configure brew for current session
print_step "Step 2: Configuring brew for current session"
echo ""

# Add Homebrew to PATH for current session
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"

# Source brew environment
if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" || true
    print_info "✓ Brew environment configured"
    print_info "✓ PATH updated to include Homebrew binaries"
else
    print_error "Brew not found at expected location"
    exit 1
fi

echo ""

# Step 3: Install make
print_step "Step 3: Installing make"
echo ""

if command -v make &>/dev/null; then
    MAKE_VERSION=$(make --version | head -n 1)
    print_info "✓ make already installed: $MAKE_VERSION"
else
    print_info "Installing make via Homebrew..."
    if [ "$EUID" -eq 0 ]; then
        # Running as root, use sudo to run as target user
        sudo -u "$TARGET_USER" /home/linuxbrew/.linuxbrew/bin/brew install make
    else
        # Running as regular user
        brew install make
    fi

    # Add brew make to PATH
    export PATH="/home/linuxbrew/.linuxbrew/opt/make/libexec/gnubin:$PATH"
    print_info "✓ make installed successfully"
fi

echo ""

# Step 4: Create Makefile if it doesn't exist
print_step "Step 4: Setting up Makefile"
echo ""

if [ ! -f "$ROOT_DIR/Makefile" ]; then
    print_info "Makefile not found, it should be created separately"
else
    print_info "✓ Makefile already exists"
fi

echo ""

# Step 5: Install additional helpful tools
print_step "Step 5: Installing additional tools (optional)"
echo ""

ADDITIONAL_TOOLS=()
if ! command -v jq &>/dev/null; then
    ADDITIONAL_TOOLS+=(jq)
fi
if ! command -v yq &>/dev/null; then
    ADDITIONAL_TOOLS+=(yq)
fi

if [ ${#ADDITIONAL_TOOLS[@]} -gt 0 ]; then
    print_info "The following tools are recommended for working with compose files:"
    for tool in "${ADDITIONAL_TOOLS[@]}"; do
        echo "  - $tool"
    done

    read -p "Install these tools? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installing additional tools..."
        if [ "$EUID" -eq 0 ]; then
            sudo -u "$TARGET_USER" /home/linuxbrew/.linuxbrew/bin/brew install "${ADDITIONAL_TOOLS[@]}"
        else
            brew install "${ADDITIONAL_TOOLS[@]}"
        fi
        print_info "✓ Additional tools installed"
    fi
else
    print_info "✓ All recommended tools already installed"
fi

echo ""

# Print success message
print_info "=============================================="
print_info "✓ Nexus setup complete!"
print_info "=============================================="
echo ""
print_info "Summary:"
print_info "  • Homebrew installed and configured for: $TARGET_USER"
print_info "  • make installed and ready to use"
print_info "  • Nexus project ready at: $ROOT_DIR"
echo ""
print_info "Next steps:"
print_info "  1. Review and update .env files in each stack directory"
print_info "  2. Run 'make help' to see available commands"
print_info "  3. Run 'make fmt' to update README with current services"
print_info "  4. Run 'make start' to launch all stacks"
echo ""
print_info "For root users: Use 'brew' command (aliased to run as $TARGET_USER)"
print_info "For $TARGET_USER: Start a new shell or run 'source ~/.zshrc'"
echo ""
print_info "Happy containerizing! 🐋"
echo ""
