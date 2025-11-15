#!/bin/bash
#
# Linuxbrew Installation Script for TrueNAS Scale
# This script automates the installation of Homebrew (Linuxbrew) on TrueNAS Scale systems
#
# Author: Auto-generated
# Date: 2025-11-11
#
# Prerequisites:
#   - Running on TrueNAS Scale
#   - Regular user account (non-root)
#   - Internet connection
#
# Usage:
#   sudo ./install-linuxbrew.sh [username]
#
# If username is not provided, the script will attempt to detect a regular user account

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Determine the target user
if [ $# -eq 1 ]; then
    TARGET_USER="$1"
    print_info "Using provided username: $TARGET_USER"
else
    # Try to auto-detect a regular user
    print_info "No username provided, attempting to auto-detect..."
    TARGET_USER=$(cat /etc/passwd | grep -E '/mnt/data/home|/home' | grep -v nologin | grep -v false | grep -v root | head -n 1 | cut -d: -f1)

    if [ -z "$TARGET_USER" ]; then
        print_error "Could not auto-detect a user. Please provide a username as an argument."
        exit 1
    fi

    print_info "Auto-detected user: $TARGET_USER"
fi

# Verify user exists
if ! id "$TARGET_USER" &>/dev/null; then
    print_error "User $TARGET_USER does not exist"
    exit 1
fi

# Get user's home directory
USER_HOME=$(eval echo ~$TARGET_USER)
print_info "User home directory: $USER_HOME"

# Determine installation directory
# TrueNAS Scale has /home mounted with noexec, so we use /mnt/data/home instead
if mount | grep -q "on /home type zfs.*noexec"; then
    print_warn "/home is mounted with noexec flag, using /mnt/data/home instead"
    LINUXBREW_DIR="/mnt/data/home/linuxbrew/.linuxbrew"

    # Create symlink from /home/linuxbrew to /mnt/data/home/linuxbrew
    if [ ! -L "/home/linuxbrew" ]; then
        print_info "Creating symlink: /home/linuxbrew -> /mnt/data/home/linuxbrew"
        rm -rf /home/linuxbrew
        mkdir -p /mnt/data/home/linuxbrew
        ln -s /mnt/data/home/linuxbrew /home/linuxbrew
    fi
else
    LINUXBREW_DIR="/home/linuxbrew/.linuxbrew"
fi

print_info "Installing Linuxbrew to: $LINUXBREW_DIR"

# Check if Homebrew is already installed
if [ -d "$LINUXBREW_DIR/Homebrew" ]; then
    print_warn "Homebrew appears to be already installed at $LINUXBREW_DIR"
    read -p "Do you want to reinstall? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    print_info "Removing existing installation..."
    rm -rf "$LINUXBREW_DIR/Homebrew"
fi

# Create directory structure
print_info "Creating directory structure..."
mkdir -p "$LINUXBREW_DIR"/{bin,etc,include,lib,sbin,share,var,opt,Cellar,Caskroom,Frameworks,share/zsh/site-functions,var/homebrew/linked}

# Set ownership
print_info "Setting ownership to $TARGET_USER..."
chown -R "$TARGET_USER:$TARGET_USER" "$(dirname $LINUXBREW_DIR)"

# Clone Homebrew repository
print_info "Cloning Homebrew repository..."
su - "$TARGET_USER" -c "cd $LINUXBREW_DIR && git clone https://github.com/Homebrew/brew Homebrew"

# Create brew symlink
print_info "Creating brew symlink..."
rm -f "$LINUXBREW_DIR/bin/brew"
su - "$TARGET_USER" -c "ln -s $LINUXBREW_DIR/Homebrew/bin/brew $LINUXBREW_DIR/bin/brew"

# Test installation
print_info "Testing brew installation..."
if su - "$TARGET_USER" -c "$LINUXBREW_DIR/bin/brew --version" &>/dev/null; then
    VERSION=$(su - "$TARGET_USER" -c "$LINUXBREW_DIR/bin/brew --version" | head -n 1)
    print_info "✓ Homebrew installed successfully: $VERSION"
else
    print_error "Homebrew installation failed"
    exit 1
fi

# Add to shell profile
SHELL_RC=""
if [ -f "$USER_HOME/.zshrc" ]; then
    SHELL_RC="$USER_HOME/.zshrc"
elif [ -f "$USER_HOME/.bashrc" ]; then
    SHELL_RC="$USER_HOME/.bashrc"
else
    # Create .zshrc if it doesn't exist
    SHELL_RC="$USER_HOME/.zshrc"
    touch "$SHELL_RC"
    chown "$TARGET_USER:$TARGET_USER" "$SHELL_RC"
fi

print_info "Configuring shell profile: $SHELL_RC"

# Check if brew configuration already exists (idempotent)
if grep -q "# Homebrew (Linuxbrew) Configuration" "$SHELL_RC" 2>/dev/null; then
    print_info "✓ Brew already configured in $SHELL_RC (skipping)"
else
    # Add brew to PATH for target user
    cat >> "$SHELL_RC" << 'EOF'

# Homebrew (Linuxbrew) Configuration
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
EOF
    chown "$TARGET_USER:$TARGET_USER" "$SHELL_RC"
    print_info "✓ Added brew configuration to: $SHELL_RC"
fi

# Configure root's shell profile with alias
print_info "Configuring brew alias for root..."
ROOT_SHELL_RC=""
if [ -f "/root/.zshrc" ]; then
    ROOT_SHELL_RC="/root/.zshrc"
elif [ -f "/root/.bashrc" ]; then
    ROOT_SHELL_RC="/root/.bashrc"
else
    # Create .zshrc if it doesn't exist (zsh is default on TrueNAS Scale)
    ROOT_SHELL_RC="/root/.zshrc"
    touch "$ROOT_SHELL_RC"
fi

# Check if brew configuration already exists (idempotent)
if grep -q "# Homebrew (Linuxbrew) Configuration for Root" "$ROOT_SHELL_RC" 2>/dev/null; then
    print_info "✓ Brew already configured for root in $ROOT_SHELL_RC (skipping)"
else
    # Add brew alias and PATH for root
    cat >> "$ROOT_SHELL_RC" << EOF

# Homebrew (Linuxbrew) Configuration for Root
# Add Homebrew to PATH so installed packages are available
export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:\$PATH"
# Alias to run brew commands as $TARGET_USER (brew won't run as root)
alias brew='sudo -u $TARGET_USER /home/linuxbrew/.linuxbrew/bin/brew'
EOF
    print_info "✓ Added brew configuration and PATH to: $ROOT_SHELL_RC"
fi

# Create delegate marker file in user's home directory
DELEGATE_MARKER="$USER_HOME/.delegate"
if [ ! -f "$DELEGATE_MARKER" ]; then
    touch "$DELEGATE_MARKER"
    chown "$TARGET_USER:$TARGET_USER" "$DELEGATE_MARKER"
    print_info "✓ Created delegate marker: $DELEGATE_MARKER"
else
    print_info "✓ Delegate marker already exists: $DELEGATE_MARKER"
fi

# Update Homebrew
print_info "Updating Homebrew..."
su - "$TARGET_USER" -c "eval \"\$($LINUXBREW_DIR/bin/brew shellenv)\" && brew update" || true

# Run brew doctor to check for issues
print_info "Running brew doctor..."
su - "$TARGET_USER" -c "eval \"\$($LINUXBREW_DIR/bin/brew shellenv)\" && brew doctor" || print_warn "Some warnings from brew doctor (this is usually normal)"

# Print success message
echo ""
print_info "=============================================="
print_info "Linuxbrew installation complete!"
print_info "=============================================="
echo ""
print_info "Configured for:"
print_info "  • $TARGET_USER: Full brew access ($SHELL_RC)"
print_info "  • root: Brew alias (runs as $TARGET_USER) ($ROOT_SHELL_RC)"
echo ""
print_info "To use brew:"
print_info "  As $TARGET_USER: Start a new shell or run 'source ~/.zshrc'"
print_info "  As root: Use 'brew' command (runs as $TARGET_USER via alias)"
echo ""
print_info "Verify installation with: brew --version"
print_info "Install packages with: brew install <package>"
print_info "Search for packages: brew search <query>"
echo ""
print_info "Installation location: $LINUXBREW_DIR"
echo ""
print_info "Note: Packages installed via brew are available to all users,"
print_info "      but brew commands from root run as $TARGET_USER."
echo ""

# Optional: Install commonly used packages
read -p "Would you like to install common development tools (gcc, make, git)? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Installing development tools..."
    su - "$TARGET_USER" -c "eval \"\$($LINUXBREW_DIR/bin/brew shellenv)\" && brew install gcc make git"
    print_info "Development tools installed!"
fi

print_info "Done!"
