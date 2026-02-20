#!/bin/bash
# Dotfiles Reset Installer - Bulletproof Edition
# Original configs by StealthIQ (github.com/StealthIQ)
# Modified by Iceyxsm (github.com/iceyxsm)
#
# Features:
# - Full system reset while preserving user data
# - Removes all packages except base system
# - Reinstalls dotfiles and required packages
# - Atomic operations with rollback
# - Checkpoint system for recovery
# - Dry-run mode
# - Comprehensive validation

# Strict mode with custom error handling
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Script info
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths
readonly HOME_DIR="${HOME:-}"
readonly CONFIG_DIR="$HOME_DIR/.config"
readonly BACKUP_ROOT="$HOME_DIR/.dotfiles-backups"
readonly CHECKPOINT_DIR="$BACKUP_ROOT/.checkpoints"
readonly LOG_DIR="$HOME_DIR/.dotfiles-logs"
readonly LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
readonly LOCK_FILE="/tmp/dotfiles-install.lock"

# Colors (safe for non-TTY)
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly CYAN=$(tput setaf 6)
    readonly MAGENTA=$(tput setaf 5)
    readonly BOLD=$(tput bold)
    readonly RESET=$(tput sgr0)
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' RESET=''
fi

# Dry run mode
DRY_RUN=false

# Verbose mode (show all commands)
VERBOSE=false

# Debug mode (show variable values)
DEBUG=false

# =============================================================================
# LOGGING & OUTPUT
# =============================================================================

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
    # Store original file descriptors for cleanup
    exec 3>&1 4>&2
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    log "INFO" "=== Dotfiles Installer v$SCRIPT_VERSION ==="
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "User: $(whoami), Home: $HOME_DIR"
}

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Output functions
msg() { echo -e "${BLUE}â†’${RESET} $*"; log "INFO" "$@"; }
success() { echo -e "${GREEN}âœ“${RESET} $*"; log "SUCCESS" "$@"; }
warn() { echo -e "${YELLOW}âš ${RESET} $*" >&2; log "WARN" "$@"; }
error() { echo -e "${RED}âœ—${RESET} $*" >&2; log "ERROR" "$@"; }
header() { echo -e "${CYAN}${BOLD}$*${RESET}"; log "INFO" "$@"; }
debug() { [[ "$DEBUG" == true ]] && echo -e "${MAGENTA}[DEBUG]${RESET} $*" >&2; log "DEBUG" "$@"; }
verbose() { [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[VERBOSE]${RESET} $*"; log "VERBOSE" "$@"; }

# Progress indicator
show_progress() {
    local message="$1"
    local pid="$2"
    local spin='â ‹â ™â ¹â ¸â ¼â ´â ¦â §â ‡â '
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}${spin:$i:1}${RESET} %s" "$message"
        sleep 0.1
    done
    printf "\r%*s\r" $(( ${#message} + 2 )) ""
}

# =============================================================================

# =============================================================================
# LOCKING & SAFETY
# =============================================================================

# Acquire lock to prevent concurrent runs
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null) || true
        if kill -0 "$pid" 2>/dev/null; then
            error "Another instance is already running (PID: $pid)"
            error "If this is a mistake, remove: $LOCK_FILE"
            exit 1
        else
            warn "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log "INFO" "Lock acquired: $LOCK_FILE"
}

# Release lock
release_lock() {
    rm -f "$LOCK_FILE"
    log "INFO" "Lock released"
}

# =============================================================================
# CHECKPOINT SYSTEM (For rollback)
# =============================================================================

# Create checkpoint before making changes
create_checkpoint() {
    local name="$1"
    local checkpoint_path="$CHECKPOINT_DIR/$name-$(date +%s)"
    
    mkdir -p "$checkpoint_path"
    
    # Save current state
    {
        echo "CHECKPOINT_NAME=$name"
        echo "CHECKPOINT_TIME=$(date -Iseconds)"
        echo "CHECKPOINT_PATH=$checkpoint_path"
        echo "HOME=$HOME_DIR"
        echo "USER=$(whoami)"
        echo "KERNEL_VERSION=$(uname -r)"
        echo "SCRIPT_VERSION=$SCRIPT_VERSION"
    } > "$checkpoint_path/metadata.txt"
    
    # Save GPU driver info
    if command -v lspci &>/dev/null; then
        lspci | grep -i "vga\|3d\|display" > "$checkpoint_path/gpu_info.txt" 2>/dev/null || true
    fi
    
    # Save installed packages list
    if command -v pacman &>/dev/null; then
        pacman -Qe > "$checkpoint_path/installed_packages.txt" 2>/dev/null || true
    fi
    
    # List currently active symlinks
    find "$CONFIG_DIR" -maxdepth 1 -type l 2>/dev/null > "$checkpoint_path/symlinks.txt" || true
    
    # Save current config states for all tracked configs
    for dir in hypr hypr-stealthiq hypr-jakoolit zsh nvim kitty mpd ncmpcpp rofi ranger neofetch bashtop; do
        if [[ -L "$CONFIG_DIR/$dir" ]]; then
            echo "$dir=$(readlink "$CONFIG_DIR/$dir")" >> "$checkpoint_path/state.txt"
        elif [[ -d "$CONFIG_DIR/$dir" ]]; then
            echo "$dir=directory" >> "$checkpoint_path/state.txt"
        fi
    done
    
    # Save shell config states
    for file in .zshrc .bashrc; do
        if [[ -f "$HOME_DIR/$file" ]]; then
            cp "$HOME_DIR/$file" "$checkpoint_path/$file.bak" 2>/dev/null || true
            echo "$file=file" >> "$checkpoint_path/state.txt"
        fi
    done
    
    echo "$checkpoint_path"
}

# Restore from checkpoint
restore_checkpoint() {
    local checkpoint_path="$1"
    
    if [[ ! -f "$checkpoint_path/metadata.txt" ]]; then
        error "Invalid checkpoint: $checkpoint_path"
        return 1
    fi
    
    header "RESTORING FROM CHECKPOINT"
    msg "Checkpoint: $(grep CHECKPOINT_NAME "$checkpoint_path/metadata.txt" | cut -d= -f2)"
    
    # Read saved state
    if [[ -f "$checkpoint_path/state.txt" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                hypr|hypr-stealthiq|hypr-jakoolit|zsh|nvim|kitty|mpd|ncmpcpp|rofi|ranger|neofetch|bashtop)
                    msg "Restoring $key config..."
                    rm -f "$CONFIG_DIR/$key"
                    if [[ "$value" == "directory" ]]; then
                        # Original was a directory - restore from backup if exists
                        local backup
                        backup=$(find "$BACKUP_ROOT" -name "$key" -type d 2>/dev/null | head -1)
                        if [[ -n "$backup" ]]; then
                            cp -r "$backup" "$CONFIG_DIR/"
                            success "Restored $key from backup"
                        fi
                    else
                        ln -sf "$value" "$CONFIG_DIR/$key"
                        success "Restored $key symlink to $value"
                    fi
                    ;;
                .zshrc|.bashrc)
                    if [[ -f "$checkpoint_path/$key.bak" ]]; then
                        cp "$checkpoint_path/$key.bak" "$HOME_DIR/$key"
                        success "Restored $key from checkpoint"
                    fi
                    ;;
            esac
        done < "$checkpoint_path/state.txt"
    fi
    
    success "Rollback complete"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

# Check available disk space
check_disk_space() {
    local required_mb=500  # Minimum 500MB required
    local available_mb
    
    # Get available space in MB
    available_mb=$(df -m "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [[ -z "$available_mb" ]]; then
        warn "Could not determine available disk space"
        return 0  # Continue anyway
    fi
    
    debug "Disk space: ${available_mb}MB available, ${required_mb}MB required"
    
    if [[ $available_mb -lt $required_mb ]]; then
        error "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
        error "Free up space and try again"
        return 1
    fi
    
    success "Disk space OK: ${available_mb}MB available"
    return 0
}

# Check network connectivity
check_network() {
    local test_hosts=("archlinux.org" "google.com" "github.com")
    local connected=false
    
    msg "Checking network connectivity..."
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "$host" &>/dev/null; then
            connected=true
            debug "Network OK: Connected to $host"
            break
        fi
    done
    
    if [[ "$connected" == false ]]; then
        warn "No network connectivity detected"
        warn "Package installation may fail"
        return 1
    fi
    
    success "Network connectivity OK"
    return 0
}

# Install package with retry logic
install_with_retry() {
    local cmd="$1"
    shift
    local packages=("$@")
    local max_attempts=3
    local delay=5
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        debug "Install attempt $attempt/$max_attempts: ${packages[*]}"
        
        if $cmd "${packages[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    error "Failed after $max_attempts attempts: ${packages[*]}"
    return 1
}

check_prerequisites() {
    header "CHECKING PREREQUISITES"
    local failed=0
    
    # Check HOME
    if [[ -z "$HOME_DIR" ]]; then
        error "HOME environment variable is not set"
        ((failed++)) || true
    elif [[ ! -d "$HOME_DIR" ]]; then
        error "Home directory does not exist: $HOME_DIR"
        ((failed++)) || true
    fi
    
    # Check write permission
    if [[ ! -w "$HOME_DIR" ]]; then
        error "No write permission to home directory: $HOME_DIR"
        ((failed++)) || true
    fi
    
    # Check required commands
    local required_cmds=("cp" "mv" "rm" "mkdir" "ln" "find" "sed" "tee" "date")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            error "Required command not found: $cmd"
            ((failed++)) || true
        fi
    done
    
    # Check dotfiles source
    if [[ ! -d "$SCRIPT_DIR/dot_config" ]]; then
        error "Dotfiles source directory not found: $SCRIPT_DIR/dot_config"
        error "Make sure you're running this script from the dotfiles directory"
        ((failed++)) || true
    fi
    
    # Check OS (warn only)
    if [[ ! -f /etc/arch-release ]]; then
        warn "This script is designed for Arch Linux"
        warn "Some features may not work correctly"
    fi
    
    # Create required directories
    mkdir -p "$CONFIG_DIR" "$BACKUP_ROOT" "$CHECKPOINT_DIR" 2>/dev/null || {
        error "Failed to create required directories"
        ((failed++)) || true
    }
    
    # Check disk space
    if ! check_disk_space; then
        ((failed++)) || true
    fi
    
    if [[ $failed -gt 0 ]]; then
        error "$failed prerequisite check(s) failed"
        exit 1
    fi
    
    success "All prerequisites passed"
}

# =============================================================================
# CONFLICT DETECTION
# =============================================================================

detect_conflicts() {
    header "DETECTING CONFLICTS"
    local conflicts=()
    
    # Check for existing dotfiles
    for src in "$SCRIPT_DIR"/dot_config/*; do
        [[ -d "$src" ]] || continue
        local name
        name=$(basename "$src" | sed 's/^dot_//')
        local target="$CONFIG_DIR/$name"
        
        if [[ -e "$target" ]]; then
            if [[ -L "$target" ]]; then
                local link_target
                link_target=$(readlink "$target")
                warn "$name: Symlink exists â†’ $link_target"
            else
                warn "$name: Directory/file exists (will be backed up)"
            fi
            conflicts+=("$name")
        fi
    done
    
    # Check for shell config conflicts
    if [[ -f "$HOME_DIR/.zshrc" ]] && [[ -f "$SCRIPT_DIR/dot_zshrc" ]]; then
        warn ".zshrc exists (will be backed up)"
        conflicts+=(".zshrc")
    fi
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        msg "Found ${#conflicts[@]} potential conflict(s)"
        msg "All existing configs will be backed up before modification"
        
        if [[ "$DRY_RUN" == false ]] && [[ "${AUTO_MODE:-}" != "true" ]]; then
            read -rp "Continue? [Y/n]: " confirm
            [[ "$confirm" =~ ^[Nn]$ ]] && exit 0
        fi
    else
        success "No conflicts detected"
    fi
}

# =============================================================================
# BACKUP WITH VERIFICATION
# =============================================================================

backup_configs() {
    header "CREATING BACKUP"
    local backup_path="$BACKUP_ROOT/backup-$(date +%Y%m%d-%H%M%S)"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Would create backup at: $backup_path"
        return 0
    fi
    
    mkdir -p "$backup_path"
    local backed_up=0
    local failed=0
    
    # Backup configs (only directories that exist in dot_config)
    for dir in hypr hypr-stealthiq hypr-jakoolit hyprpaper dunst conky waybar wallust rofi zsh ncmpcpp mpd cava nvim kitty ranger neofetch bashtop X11 vlc; do
        local src="$CONFIG_DIR/$dir"
        if [[ -e "$src" ]]; then
            if cp -a "$src" "$backup_path/" 2>/dev/null; then
                ((backed_up++)) || true
                log "BACKUP" "$dir"
            else
                warn "Failed to backup: $dir"
                ((failed++)) || true
            fi
        fi
    done
    
    # Backup shell configs
    for file in .zshrc .bashrc; do
        if [[ -f "$HOME_DIR/$file" ]]; then
            if cp "$HOME_DIR/$file" "$backup_path/" 2>/dev/null; then
                ((backed_up++)) || true
                log "BACKUP" "$file"
            fi
        fi
    done
    
    # Verify backup
    if [[ $backed_up -gt 0 ]]; then
        local count
        count=$(find "$backup_path" -mindepth 1 -maxdepth 1 | wc -l)
        if [[ $count -gt 0 ]]; then
            success "Backup created: $backup_path ($backed_up items)"
            echo "$backup_path" > "$BACKUP_ROOT/latest.txt"
        else
            error "Backup verification failed!"
            return 1
        fi
    else
        msg "Nothing to backup"
    fi
    
    if [[ $failed -gt 0 ]]; then
        warn "$failed item(s) failed to backup"
    fi
    
    echo "$backup_path"
}

# =============================================================================
# ATOMIC FILE OPERATIONS
# =============================================================================

# Safe copy with rollback support
safe_copy() {
    local src="$1"
    local dst="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] cp -r $src $dst"
        return 0
    fi
    
    # Create parent directory if needed
    local parent
    parent=$(dirname "$dst")
    mkdir -p "$parent"
    
    # Remove destination if exists (backup already created)
    if [[ -e "$dst" ]]; then
        rm -rf "$dst" || {
            error "Failed to remove existing: $dst"
            return 1
        }
    fi
    
    # Copy
    if cp -r "$src" "$dst"; then
        log "COPY" "$src â†’ $dst"
        return 0
    else
        error "Failed to copy: $src â†’ $dst"
        return 1
    fi
}

# Safe symlink creation
safe_symlink() {
    local target="$1"
    local link="$2"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] ln -sf $target $link"
        return 0
    fi
    
    # Remove existing
    if [[ -L "$link" ]] || [[ -e "$link" ]]; then
        rm -rf "$link" || {
            error "Failed to remove existing: $link"
            return 1
        }
    fi
    
    # Create symlink
    if ln -sf "$target" "$link"; then
        log "SYMLINK" "$link â†’ $target"
        return 0
    else
        error "Failed to create symlink: $link â†’ $target"
        return 1
    fi
}

# =============================================================================
# COPY DOTFILES
# =============================================================================

copy_dotfiles() {
    header "COPYING DOTFILES"
    local copied=0
    local failed=0
    
    # Copy config directories
    for src in "$SCRIPT_DIR"/dot_config/*; do
        [[ -d "$src" ]] || continue
        
        local name
        name=$(basename "$src" | sed 's/^dot_//')
        local dst="$CONFIG_DIR/$name"
        
        msg "Copying $name..."
        
        if safe_copy "$src" "$dst"; then
            ((copied++)) || true
        else
            ((failed++)) || true
        fi
    done
    
    # Copy shell configs
    if [[ -f "$SCRIPT_DIR/dot_zshrc" ]]; then
        msg "Copying .zshrc..."
        if safe_copy "$SCRIPT_DIR/dot_zshrc" "$HOME_DIR/.zshrc"; then
            ((copied++)) || true
        fi
    fi
    
    if [[ -f "$SCRIPT_DIR/dot_bashrc" ]]; then
        msg "Copying .bashrc..."
        if safe_copy "$SCRIPT_DIR/dot_bashrc" "$HOME_DIR/.bashrc"; then
            ((copied++)) || true
        fi
    fi
    
    # Copy .local
    if [[ -d "$SCRIPT_DIR/dot_local" ]]; then
        msg "Copying .local files..."
        mkdir -p "$HOME_DIR/.local"
        cp -r "$SCRIPT_DIR/dot_local/"* "$HOME_DIR/.local/" 2>/dev/null || true
    fi
    
    # Copy wallpapers
    if [[ -d "$SCRIPT_DIR/misc/.wallpapers" ]]; then
        msg "Copying wallpapers..."
        mkdir -p "$HOME_DIR/wallpapers"
        cp -r "$SCRIPT_DIR/misc/.wallpapers/"* "$HOME_DIR/wallpapers/" 2>/dev/null || true
        ((copied++)) || true
    fi
    
    # Copy custom fonts
    if [[ -d "$SCRIPT_DIR/misc/.fonts" ]]; then
        msg "Copying fonts..."
        mkdir -p "$HOME_DIR/.local/share/fonts"
        cp -r "$SCRIPT_DIR/misc/.fonts/"* "$HOME_DIR/.local/share/fonts/" 2>/dev/null || true
        # Rebuild font cache
        fc-cache -f -v 2>/dev/null || true
        ((copied++)) || true
    fi
    
    # Copy icons
    if [[ -d "$SCRIPT_DIR/misc/.icons" ]]; then
        msg "Copying icons..."
        mkdir -p "$HOME_DIR/.icons"
        cp -r "$SCRIPT_DIR/misc/.icons/"* "$HOME_DIR/.icons/" 2>/dev/null || true
        ((copied++)) || true
    fi
    
    # Create default Pictures directory structure
    mkdir -p "$HOME_DIR/Pictures/Screenshots" 2>/dev/null || true
    
    if [[ $failed -gt 0 ]]; then
        error "$failed copy operation(s) failed"
        return 1
    fi
    
    success "Copied $copied item(s)"
}

# =============================================================================
# PORTABLE PATHS
# =============================================================================

make_portable() {
    local target_dir="${1:-$CONFIG_DIR}"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Make paths portable in $target_dir"
        return 0
    fi
    
    msg "Making configs portable..."
    
    local fixed=0
    while IFS= read -r -d '' file; do
        if sed -i "s|/home/[^/]*/|$HOME/|g" "$file" 2>/dev/null; then
            ((fixed++)) || true
        fi
    done < <(find "$target_dir" -type f \( \
        -name "*.conf" -o -name "*.sh" -o -name "*.zsh" -o \
        -name "*.qml" -o -name "*.json" -o -name "*.lua" \
    \) -print0 2>/dev/null)
    
    log "PORTABLE" "Fixed $fixed files"
    success "Paths updated"
}

# =============================================================================
# PACKAGE INSTALLATION
# =============================================================================

check_aur_helper() {
    if command -v paru &>/dev/null; then
        echo "paru"
    elif command -v yay &>/dev/null; then
        echo "yay"
    else
        echo ""
    fi
}

# Install paru (AUR helper) if not present
install_aur_helper() {
    local aur_helper
    aur_helper=$(check_aur_helper)
    
    if [[ -n "$aur_helper" ]]; then
        msg "AUR helper already installed: $aur_helper"
        return 0
    fi
    
    header "INSTALLING AUR HELPER (paru)"
    
    # Check for git and base-devel
    local build_deps=("git" "base-devel")
    local missing_deps=()
    
    for dep in "${build_deps[@]}"; do
        if ! pacman -Q "$dep" &>/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        msg "Installing build dependencies: ${missing_deps[*]}"
        sudo pacman -S --needed --noconfirm "${missing_deps[@]}" 2>&1 | tee -a "$LOG_FILE" || {
            error "Failed to install build dependencies"
            return 1
        }
    fi
    
    # Create temp directory for building
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    
    msg "Cloning paru from AUR..."
    git clone https://aur.archlinux.org/paru.git 2>&1 | tee -a "$LOG_FILE" || {
        error "Failed to clone paru"
        rm -rf "$tmp_dir"
        return 1
    }
    
    cd paru
    
    msg "Building and installing paru..."
    makepkg -si --noconfirm 2>&1 | tee -a "$LOG_FILE" || {
        error "Failed to build paru"
        rm -rf "$tmp_dir"
        return 1
    }
    
    # Cleanup
    cd /
    rm -rf "$tmp_dir"
    
    success "paru installed successfully"
    return 0
}

# =============================================================================
# GRAPHICS DRIVER DETECTION
# =============================================================================

detect_gpu() {
    local gpu_type="unknown"
    
    # Check for NVIDIA
    if lspci | grep -i nvidia &>/dev/null; then
        gpu_type="nvidia"
    # Check for AMD
    elif lspci | grep -i "vga|3d|display" | grep -i amd &>/dev/null; then
        gpu_type="amd"
    # Check for Intel
    elif lspci | grep -i "vga|3d|display" | grep -i intel &>/dev/null; then
        gpu_type="intel"
    # Check for VMware/VirtualBox
    elif lspci | grep -i "vmware|virtualbox" &>/dev/null; then
        gpu_type="virtual"
    fi
    
    echo "$gpu_type"
}

# =============================================================================
# BACKUP AND RESTORE FUNCTIONS
# =============================================================================
install_graphics_drivers() {
    header "DETECTING GRAPHICS (Installation Disabled)"
    
    # Detect GPU but don't install drivers
    local gpu_type
    gpu_type=$(detect_gpu)
    
    msg "Detected GPU type: $gpu_type"
    
    if [[ "$gpu_type" == "unknown" ]]; then
        warn "Could not detect GPU type"
    else
        warn "GPU detected: $gpu_type"
        warn "Driver installation is disabled - please install drivers manually"
    fi
    
    success "GPU detection complete (installation disabled)"
}

install_deps() {
    header "INSTALLING DEPENDENCIES"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Would install packages"
        return 0
    fi
    
    # First, ensure CA certificates are up to date (fixes certificate errors)
    msg "Updating CA certificates..."
    sudo pacman -S --needed --noconfirm ca-certificates 2>&1 | tee -a "$LOG_FILE" || true
    sudo update-ca-trust 2>/dev/null || true
    
    # Install graphics drivers
    install_graphics_drivers
    
    # Install AUR helper if not present
    install_aur_helper || warn "AUR helper installation failed, AUR packages will be skipped"
    
    # Core packages from official repos
    local pacman_pkgs=(
        # Hyprland ecosystem
        "hyprland" "hyprpaper" "hyprlock" "hypridle"
        # Notifications
        "dunst" "libnotify"
        # System monitoring
        "conky" "btop" "htop"
        # Audio/Music
        "mpd" "ncmpcpp" "cava" "playerctl" "pavucontrol"
        # Audio effects
        "easyeffects" "lsp-plugins"
        # Audio utilities
        "alsa-utils" "wireplumber" "pipewire" "pipewire-pulse"
        # Terminal
        "kitty"
        # Shell
        "zsh" "fish"
        # Screenshot/screen recording
        "grim" "slurp" "wl-clipboard" "hyprshot"
        # Clipboard history
        "cliphist"
        # Brightness control
        "brightnessctl"
        # App launcher (fallback)
        "fuzzel" "rofi"
        # Session menu (fallback)
        "wlogout"
        # File manager
        "thunar" "dolphin" "nautilus"
        # File manager plugins
        "thunar-archive-plugin" "thunar-volman" "tumbler"
        # Fonts (cursor theme)
        "bibata-cursor-theme"
        # Image viewer for wallpaper
        "imv"
        # Polkit authentication agent
        "polkit-gnome"
        # Keyring
        "gnome-keyring"
        # Media control
        "mpc"
        # Color picker
        "hyprpicker"
        # OCR (for screen text recognition)
        "tesseract" "tesseract-data-eng"
        # XDG utilities
        "xdg-utils" "xdg-user-dirs"
        # Wayland utilities
        "wtype" "wev"
        # Geolocation
        "geoclue"
        # Network
        "networkmanager" "network-manager-applet"
        # Bluetooth
        "bluez" "bluez-utils" "blueman"
        # Archive
        "unzip" "unrar" "p7zip"
        # Essential fonts
        "ttf-font-awesome" "ttf-jetbrains-mono" "noto-fonts" "noto-fonts-emoji"
        # Additional fonts for icons
        "ttf-nerd-fonts-symbols" "ttf-nerd-fonts-symbols-mono"
        # File manager terminal (yazi)
        "yazi"
        # Image manipulation (for wallpaper scripts)
        "imagemagick"
        # JSON processor (for scripts)
        "jq"
        # Calculator (used in some configs)
        "bc"
        # Killall command
        "psmisc"
        # Find utils
        "findutils"
        # Sed/awk/grep
        "sed" "gawk" "grep"
        # File watcher
        "inotify-tools"
        # Python (for quickshell scripts)
        "python" "python-pip" "python-virtualenv"
        # Python packages for quickshell scripts
        "python-pillow" "python-numpy" "python-opencv"
        # GNOME desktop for thumbnail generation
        "gnome-desktop"
        # Qt dependencies for quickshell
        "qt5-base" "qt6-base" "qt6-svg" "qt6-quickcontrols2"
        # KVantum for theming
        "kvantum"
        # ydotool for virtual keyboard input (used by quickshell)
        "ydotool"
        # hyprsunset for blue light filter (part of hyprland)
        "hyprsunset"
        # Modern file operations
        "eza"           # Modern ls replacement (maintained fork of exa)
        "zoxide"        # Smart cd command (used with 'z' alias)
        "bat"           # Modern cat with syntax highlighting
        "fd"            # Modern find replacement
        "swww"          # Animated wallpaper setter for Wayland
        "fzf"           # Fuzzy finder (used in various scripts)
    )
    
    # AUR packages (require paru or yay)
    local aur_pkgs=(
        # Quickshell - REQUIRED for UI (bar, launcher, sidebar, etc.)
        "quickshell"
        # ActivityWatch (used in execs.conf)
        "activitywatch-bin"
        # Vicinae (used in custom/execs.conf and keybinds)
        "vicinae-git"
        # Handy (AI assistant)
        "handy-git"
        # Python material color generation (for quickshell color scripts)
        "python-materialyoucolor"
        # Music recognition (used by quickshell SongRec service)
        "songrec"
        # LaTeX renderer for quickshell
        "microtex"
        # Pokemon in terminal
        "pokemon-colorscripts-git"
        # Browsers
        "brave-bin"
        # Notes
        "obsidian"
        # Cloud storage
        "megasync"
        # App launcher alternative
        "ulauncher"
        # Password manager
        "bitwarden"
        # Spotify
        "spotify"
        # Code editors
        "visual-studio-code-bin"
        # Emoji picker
        "emojione-picker"
    )
    
    # Install packages using AUR helper (yay/paru) - handles both official and AUR packages
    local aur_helper
    aur_helper=$(check_aur_helper)
    
    if [[ -n "$aur_helper" ]]; then
        msg "Installing all packages with $aur_helper..."
        # Combine official and AUR packages for yay to handle
        local all_pkgs=("${pacman_pkgs[@]}" "${aur_pkgs[@]}")
        if $aur_helper -S --needed --noconfirm "${all_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            success "All packages installed"
        else
            warn "Some packages may have failed (see log)"
        fi
    else
        # Fallback to pacman if no AUR helper available
        warn "AUR helper not available, using pacman for official packages only"
        if command -v pacman &>/dev/null; then
            msg "Installing official packages with pacman..."
            if sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
                success "Official packages installed"
            else
                warn "Some packages may have failed (see log)"
            fi
        fi
        warn "AUR packages skipped: ${aur_pkgs[*]}"
    fi
    
    # Verify critical packages
    local missing=()
    for pkg in hyprland zsh quickshell; do
        if ! command -v "$pkg" &>/dev/null && ! pacman -Q "$pkg" &>/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing critical packages: ${missing[*]}, attempting to install..."
        # Try to install missing critical packages using AUR helper (yay/paru)
        local aur_helper
        aur_helper=$(check_aur_helper)
        
        if [[ -n "$aur_helper" ]]; then
            for pkg in "${missing[@]}"; do
                msg "Installing missing package: $pkg using $aur_helper"
                if $aur_helper -S --needed --noconfirm "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
                    success "Installed: $pkg"
                else
                    error "Failed to install: $pkg"
                    return 1
                fi
            done
        else
            # Fallback to pacman if no AUR helper available
            if command -v pacman &>/dev/null; then
                for pkg in "${missing[@]}"; do
                    msg "Installing missing package: $pkg using pacman"
                    if sudo pacman -S --needed --noconfirm "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
                        success "Installed: $pkg"
                    else
                        error "Failed to install: $pkg"
                        return 1
                    fi
                done
            else
                error "Cannot install missing packages - neither AUR helper nor pacman available"
                return 1
            fi
        fi
    fi
    
    success "Dependencies OK"
}

# =============================================================================
# RESET SYSTEM - Remove all packages except base and user apps
# =============================================================================

# Apps to preserve during reset (user-installed applications)
PRESERVE_APPS=(
    # Browsers
    "brave-bin" "firefox" "chromium" "google-chrome"
    # Code editors
    "visual-studio-code-bin" "code" "vim" "neovim"
    # Communication
    "discord" "telegram-desktop" "slack-desktop"
    # Media
    "spotify" "vlc" "mpv"
    # Productivity
    "obsidian" "notion-app" "libreoffice-fresh"
    # Cloud storage
    "megasync" "dropbox" "nextcloud-client"
    # Password managers
    "bitwarden" "keepassxc" "lastpass"
    # Games (optional - uncomment if needed)
    # "steam" "lutris" "wine" "heroic-games-launcher-bin"
)

# Base system packages that should never be removed
BASE_PACKAGES=(
    "base" "base-devel" "linux" "linux-firmware"
    "pacman" "systemd" "bash" "coreutils" "util-linux"
    "grep" "sed" "gawk" "findutils" "procps"
    "networkmanager" "sudo" "shadow" "filesystem"
)

save_installed_packages() {
    local save_file="$BACKUP_ROOT/pre-reset-packages.txt"
    mkdir -p "$BACKUP_ROOT"
    
    msg "Saving current package list..."
    
    # Save explicitly installed packages
    pacman -Qe > "$save_file" 2>/dev/null || true
    
    # Save AUR packages separately
    pacman -Qm > "$BACKUP_ROOT/pre-reset-aur-packages.txt" 2>/dev/null || true
    
    success "Package lists saved to $BACKUP_ROOT"
}

get_preserve_list() {
    local preserve_list=()
    
    # Add base packages
    preserve_list+=("${BASE_PACKAGES[@]}")
    
    # Add preserved apps if installed
    for app in "${PRESERVE_APPS[@]}"; do
        if pacman -Q "$app" &>/dev/null 2>&1; then
            preserve_list+=("$app")
        fi
    done
    
    # Add AUR helper
    if command -v paru &>/dev/null; then
        preserve_list+=("paru")
    elif command -v yay &>/dev/null; then
        preserve_list+=("yay")
    fi
    
    echo "${preserve_list[@]}"
}

reset_packages() {
    header "RESETTING SYSTEM PACKAGES"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Would remove all non-essential packages"
        msg "[DRY RUN] Would preserve: base system, ${#PRESERVE_APPS[@]} user apps"
        return 0
    fi
    
    # Save current package list first
    save_installed_packages
    
    # Get list of packages to preserve
    local preserve_list
    preserve_list=$(get_preserve_list)
    
    msg "Packages to preserve: ${preserve_list[*]}"
    
    # Get all explicitly installed packages
    local all_packages
    all_packages=$(pacman -Qeq 2>/dev/null || true)
    
    # Build list of packages to remove
    local packages_to_remove=()
    for pkg in $all_packages; do
        local should_preserve=false
        for preserve in $preserve_list; do
            if [[ "$pkg" == "$preserve" ]]; then
                should_preserve=true
                break
            fi
        done
        
        if [[ "$should_preserve" == false ]]; then
            packages_to_remove+=("$pkg")
        fi
    done
    
    if [[ ${#packages_to_remove[@]} -eq 0 ]]; then
        success "No packages to remove"
        return 0
    fi
    
    msg "Removing ${#packages_to_remove[@]} packages..."
    
    # Remove packages
    if sudo pacman -Rns --noconfirm "${packages_to_remove[@]}" 2>&1 | tee -a "$LOG_FILE"; then
        success "Removed ${#packages_to_remove[@]} packages"
    else
        warn "Some packages could not be removed (may have dependencies)"
        # Try cascade removal for stubborn packages
        msg "Attempting cascade removal..."
        sudo pacman -Rns --noconfirm --cascade "${packages_to_remove[@]}" 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    # Clean orphan packages
    msg "Cleaning orphan packages..."
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null || true)
    if [[ -n "$orphans" ]]; then
        sudo pacman -Rns --noconfirm $orphans 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    # Clean package cache (keep last 3 versions)
    msg "Cleaning package cache..."
    sudo paccache -r 2>/dev/null || true
    
    success "System reset complete"
}

reset_configs() {
    header "RESETTING CONFIGURATIONS"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Would remove all config directories"
        return 0
    fi
    
    # Config directories to remove (preserving user data)
    local config_dirs=(
        "hypr" "hypr-stealthiq" "hypr-jakoolit" "hyprpaper"
        "quickshell" "dunst" "conky" "waybar" "wallust"
        "rofi" "ncmpcpp" "mpd" "cava" "kitty" "ranger"
        "neofetch" "bashtop" "X11" "vlc" "ulauncher"
        "alacritty" "btop" "nvim" "zsh"
    )
    
    # Remove config directories
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$CONFIG_DIR/$dir" ]]; then
            msg "Removing $dir..."
            rm -rf "$CONFIG_DIR/$dir"
        fi
    done
    
    # Remove shell configs (will be replaced)
    for file in .zshrc .bashrc .p10k.zsh; do
        if [[ -f "$HOME_DIR/$file" ]]; then
            rm -f "$HOME_DIR/$file"
        fi
    done
    
    # Remove quickshell state
    rm -rf "$HOME_DIR/.local/state/quickshell" 2>/dev/null || true
    rm -rf "$HOME_DIR/.cache/quickshell" 2>/dev/null || true
    
    # Remove illogical-impulse config
    rm -rf "$HOME_DIR/.config/illogical-impulse" 2>/dev/null || true
    rm -rf "$HOME_DIR/.config/matugen" 2>/dev/null || true
    
    success "Configurations reset"
}

full_reset() {
    local checkpoint=""
    
    show_banner
    header "FULL SYSTEM RESET"
    
    # Warning
    echo ""
    echo "${RED}${BOLD}âš  WARNING: This will reset your desktop environment!${RESET}"
    echo "${YELLOW}Your personal data (Documents, Pictures, etc.) will be preserved.${RESET}"
    echo "${YELLOW}All desktop packages and configs will be removed and reinstalled.${RESET}"
    echo ""
    
    if [[ "${AUTO_MODE:-}" != "true" ]]; then
        read -rp "Are you sure you want to continue? [y/N]: " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && { msg "Aborted"; exit 0; }
    fi
    
    # Pre-reset checks
    acquire_lock
    check_prerequisites
    check_network || { error "Network required for reset"; exit 1; }
    
    # Create checkpoint
    checkpoint=$(create_checkpoint "pre-reset")
    msg "Checkpoint created: $(basename "$checkpoint")"
    
    # Backup configs before reset
    backup_configs || warn "Backup had some issues, continuing..."
    
    # Reset packages (remove non-essential)
    reset_packages
    
    # Reset configs
    reset_configs
    
    # Reinstall AUR helper (may have been removed)
    install_aur_helper || warn "Could not reinstall AUR helper"
    
    # Copy fresh dotfiles
    copy_dotfiles
    
    # Install all required packages
    install_deps || warn "Some packages failed to install"
    
    # Setup StealthIQ
    setup_stealthiq || warn "Setup had issues"
    
    # Make paths portable
    make_portable
    
    # Post-reset validation
    header "VALIDATING RESET"
    local issues=0
    
    if [[ ! -d "$CONFIG_DIR/hypr-stealthiq" ]]; then
        error "StealthIQ config missing!"
        ((issues++)) || true
    fi
    
    if ! command -v hyprland &>/dev/null; then
        error "Hyprland not installed!"
        ((issues++)) || true
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Reset validated"
        echo
        echo "${GREEN}${BOLD}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—${RESET}"
        echo "${GREEN}${BOLD}â•‘        SYSTEM RESET COMPLETE!                  â•‘${RESET}"
        echo "${GREEN}${BOLD}â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${RESET}"
        echo
        echo "${CYAN}Please log out and log back in to apply changes.${RESET}"
        echo "${BLUE}Your personal data has been preserved.${RESET}"
        echo "${BLUE}Previous package list saved: $BACKUP_ROOT/pre-reset-packages.txt${RESET}"
        echo "${BLUE}Log:${RESET} $LOG_FILE"
    else
        error "Reset validation failed ($issues issues)"
        echo "${YELLOW}Checkpoint saved at: $checkpoint${RESET}"
        exit 1
    fi
    
    release_lock
}

# =============================================================================
# SETUP MANAGEMENT
# =============================================================================

setup_stealthiq() {
    header "SETTING UP STEALTHIQ"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Setup StealthIQ"
        return 0
    fi
    
    # Verify config exists
    if [[ ! -d "$CONFIG_DIR/hypr-stealthiq" ]]; then
        error "StealthIQ config not found. Run copy first."
        return 1
    fi
    
    # Backup current if needed
    if [[ -d "$CONFIG_DIR/hypr" ]] && [[ ! -L "$CONFIG_DIR/hypr" ]] && [[ ! -d "$CONFIG_DIR/hypr-jakoolit" ]]; then
        msg "Backing up current hypr as hypr-jakoolit..."
        mv "$CONFIG_DIR/hypr" "$CONFIG_DIR/hypr-jakoolit"
    fi
    
    # Create symlink
    safe_symlink "hypr-stealthiq" "$CONFIG_DIR/hypr"
    make_portable
    
    success "StealthIQ is now active"
}

setup_jakoolit() {
    header "SETTING UP JAKOOLIT"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Setup JaKooLit"
        return 0
    fi
    
    if [[ -d "$CONFIG_DIR/hypr-jakoolit" ]]; then
        safe_symlink "hypr-jakoolit" "$CONFIG_DIR/hypr"
    elif [[ -d "$CONFIG_DIR/hypr" ]] && [[ ! -L "$CONFIG_DIR/hypr" ]]; then
        mv "$CONFIG_DIR/hypr" "$CONFIG_DIR/hypr-jakoolit"
        safe_symlink "hypr-jakoolit" "$CONFIG_DIR/hypr"
    else
        error "JaKooLit config not found"
        return 1
    fi
    
    make_portable
    success "JaKooLit is now active"
}

switch_setup() {
    local target="$1"
    
    case "$target" in
        stealthiq) setup_stealthiq ;;
        jakoolit) setup_jakoolit ;;
        *) error "Unknown setup: $target" ; return 1 ;;
    esac
}

# =============================================================================
# EXPORT & UTILITY
# =============================================================================

export_dotfiles() {
    local export_dir="$HOME/dotfiles-export-$(date +%Y%m%d)"
    
    header "EXPORTING DOTFILES"
    mkdir -p "$export_dir"
    
    local exported=0
    for dir in hypr hypr-stealthiq hypr-jakoolit quickshell hyprpaper dunst conky waybar zsh; do
        if [[ -d "$CONFIG_DIR/$dir" ]]; then
            if cp -r "$CONFIG_DIR/$dir" "$export_dir/"; then
                msg "  $dir"
                ((exported++)) || true
            fi
        fi
    done
    
    cp "$0" "$export_dir/install.sh" 2>/dev/null || true
    
    cat > "$export_dir/README.md" << 'EOF'
# Dotfiles

## Credits
- **Original configs:** StealthIQ (github.com/StealthIQ)
- **Modified by:** Iceyxsm (github.com/iceyxsm)

## Install
```bash
./install.sh
```

## Other Options
```bash
./install.sh --auto jakoolit    # Install JaKooLit setup
./install.sh --auto both        # Install both setups
./install.sh --dry-run          # Preview changes
```

## Features
- Atomic operations with rollback
- Checkpoint system for recovery
- Dry-run mode
- Comprehensive validation
EOF
    
    success "Exported to: $export_dir"
}

# Clean compact banner
show_banner() {
    # Compact banner
    echo ""
    echo "${CYAN}â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”${RESET}"
    echo "${CYAN}â”‚${RESET}  ${BOLD}Dotfiles Installer${RESET} ${MAGENTA}v$SCRIPT_VERSION${RESET}        ${CYAN}â”‚${RESET}"
    echo "${CYAN}â”‚${RESET}                                        ${CYAN}â”‚${RESET}"
    echo "${CYAN}â”‚${RESET}  ${MAGENTA}Made by${RESET} StealthIQ                  ${CYAN}â”‚${RESET}"
    echo "${CYAN}â”‚${RESET}  ${MAGENTA}Refactored by${RESET} Iceyxsm              ${CYAN}â”‚${RESET}"
    echo "${CYAN}â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜${RESET}"
    echo ""
}

show_usage() {
    show_banner
    echo "${BOLD}Usage:${RESET} $0 [OPTIONS]"
    echo
    echo "${RED}${BOLD}RESET MODE (Recommended for broken desktops):${RESET}"
    echo "  --reset                        Full system reset preserving user data"
    echo "                                 Removes all packages except base + user apps"
    echo "                                 Reinstalls dotfiles and required packages"
    echo
    echo "${CYAN}Default:${RESET}"
    echo "  (no arguments)       Install StealthIQ setup (default)"
    echo
    echo "${CYAN}Auto Mode:${RESET}"
    echo "  --auto stealthiq     Install StealthIQ setup"
    echo "  --auto jakoolit      Install JaKooLit setup"
    echo "  --auto both          Install both setups"
    echo
    echo "${CYAN}Quick Actions:${RESET}"
    echo "  --switch [stealthiq|jakoolit]  Switch setup"
    echo "  --backup                       Backup configs"
    echo "  --export                       Export dotfiles"
    echo "  --portable                     Fix paths"
    echo "  --deps                         Install packages"
    echo "  --dry-run                      Preview changes"
    echo "  --help                         Show this help"
    echo
    echo "${CYAN}Checkpoint Management:${RESET}"
    echo "  --list-checkpoints             List available checkpoints"
    echo "  --rollback <checkpoint>        Rollback to specific checkpoint"
    echo
    echo "${CYAN}Debug Options:${RESET}"
    echo "  -v, --verbose                  Show all commands"
    echo "  -d, --debug                    Show variable values"
    echo
    echo "${CYAN}Log:${RESET} $LOG_FILE"
}

show_menu() {
    show_banner
    echo "${BLUE}User:${RESET} $(whoami)  ${BLUE}Log:${RESET} $LOG_FILE"
    echo
    
    # Detect current setup
    local current="unknown"
    if [[ -L "$CONFIG_DIR/hypr" ]]; then
        local link
        link=$(readlink "$CONFIG_DIR/hypr")
        case "$link" in
            hypr-stealthiq) current="StealthIQ" ;;
            hypr-jakoolit) current="JaKooLit" ;;
            *) current="Custom ($link)" ;;
        esac
    elif [[ -d "$CONFIG_DIR/hypr" ]]; then
        current="JaKooLit (original)"
    fi
    
    echo "${BLUE}Current:${RESET} ${MAGENTA}$current${RESET}"
    echo
    echo "${YELLOW}Options:${RESET}"
    echo "  1) Install StealthIQ"
    echo "  2) Setup JaKooLit"
    echo "  3) Install both"
    echo "  4) Switch setup"
    echo "  5) Fix paths"
    echo "  6) Backup"
    echo "  7) Export"
    echo "  8) Install deps"
    echo "  9) Exit"
    echo
}

# =============================================================================
# MAIN INSTALLATION FLOW (with checkpoints)
# =============================================================================

full_install() {
    local mode="$1"
    local checkpoint=""
    
    show_banner
    msg "Mode: $mode"
    
    # Pre-installation checks
    acquire_lock
    check_prerequisites
    detect_conflicts
    
    # Create checkpoint before any changes
    checkpoint=$(create_checkpoint "pre-install")
    msg "Checkpoint created: $(basename "$checkpoint")"
    
    # Backup
    backup_configs || {
        error "Backup failed! Aborting for safety."
        exit 1
    }
    
    # Install based on mode
    case "$mode" in
        stealthiq)
            copy_dotfiles || { restore_checkpoint "$checkpoint"; exit 1; }
            install_deps || warn "Some packages failed"
            setup_stealthiq || { restore_checkpoint "$checkpoint"; exit 1; }
            ;;
        jakoolit)
            setup_jakoolit || { restore_checkpoint "$checkpoint"; exit 1; }
            ;;
        both)
            copy_dotfiles || { restore_checkpoint "$checkpoint"; exit 1; }
            install_deps || warn "Some packages failed"
            msg "Both setups installed. Use --switch to activate."
            ;;
    esac
    
    # Post-install validation
    header "VALIDATING INSTALLATION"
    local issues=0
    
    if [[ "$mode" == "stealthiq" ]] || [[ "$mode" == "both" ]]; then
        if [[ ! -d "$CONFIG_DIR/hypr-stealthiq" ]]; then
            error "StealthIQ config missing!"
            ((issues++)) || true
        fi
    fi
    
    if [[ "$mode" == "stealthiq" ]]; then
        if [[ ! -L "$CONFIG_DIR/hypr" ]] || [[ $(readlink "$CONFIG_DIR/hypr") != "hypr-stealthiq" ]]; then
            error "Hypr symlink not set correctly!"
            ((issues++)) || true
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "Installation validated"
        echo
        echo "${GREEN}${BOLD}â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—${RESET}"
        echo "${GREEN}${BOLD}â•‘     INSTALLATION COMPLETE!                     â•‘${RESET}"
        echo "${GREEN}${BOLD}â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${RESET}"
        echo
        echo "${CYAN}Log out and back in to apply changes.${RESET}"
        echo "${BLUE}Backup:${RESET} $(cat "$BACKUP_ROOT/latest.txt" 2>/dev/null || echo "See $BACKUP_ROOT")"
        echo "${BLUE}Log:${RESET} $LOG_FILE"
    else
        error "Installation validation failed ($issues issues)"
        echo "${YELLOW}Checkpoint saved at: $checkpoint${RESET}"
        echo "${YELLOW}To rollback: restore manually or re-run installer${RESET}"
        exit 1
    fi
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_mode() {
    while true; do
        show_menu
        read -rp "Select (1-9): " choice
        echo
        
        case "$choice" in
            1) full_install "stealthiq" ;;
            2) check_prerequisites; setup_jakoolit ;;
            3) full_install "both" ;;
            4)
                echo "Switch to:"
                echo "  1) StealthIQ"
                echo "  2) JaKooLit"
                read -rp "Choice: " sw
                [[ "$sw" == "1" ]] && setup_stealthiq
                [[ "$sw" == "2" ]] && setup_jakoolit
                ;;
            5) check_prerequisites; make_portable ;;
            6) check_prerequisites; backup_configs ;;
            7) check_prerequisites; export_dotfiles ;;
            8) check_prerequisites; install_deps ;;
            9) echo "Goodbye!"; exit 0 ;;
            *) warn "Invalid option" ;;
        esac
        
        echo
        read -rp "Press Enter..."
    done
}

# =============================================================================
# COMMAND LINE PARSING
# =============================================================================

main() {
    # Initialize
    init_logging
    
    # Parse arguments
    case "${1:-}" in
        --reset)
            AUTO_MODE=true full_reset
            ;;
        --help|-h)
            show_usage
            ;;
        --auto)
            # Default to stealthiq if no argument provided
            local mode="${2:-stealthiq}"
            AUTO_MODE=true full_install "$mode"
            ;;
        --switch)
            [[ -z "${2:-}" ]] && { error "--switch requires argument"; exit 1; }
            acquire_lock
            check_prerequisites
            switch_setup "$2"
            release_lock
            ;;
        --backup)
            acquire_lock
            check_prerequisites
            backup_configs
            release_lock
            ;;
        --export)
            check_prerequisites
            export_dotfiles
            ;;
        --portable)
            acquire_lock
            check_prerequisites
            make_portable
            release_lock
            ;;
        --deps)
            acquire_lock
            check_prerequisites
            check_network || warn "No network - package installation may fail"
            install_deps
            release_lock
            ;;
        --rollback)
            [[ -z "${2:-}" ]] && { error "--rollback requires checkpoint name"; list_checkpoints; exit 1; }
            rollback_to_checkpoint "$2"
            ;;
        --list-checkpoints)
            list_checkpoints
            ;;
        --verbose|-v)
            VERBOSE=true
            msg "${CYAN}VERBOSE MODE - Showing all commands${RESET}"
            shift
            # Re-process remaining arguments
            if [[ $# -gt 0 ]]; then
                main "$@"
            else
                AUTO_MODE=true full_install "stealthiq"
            fi
            ;;
        --debug|-d)
            DEBUG=true
            VERBOSE=true
            msg "${MAGENTA}DEBUG MODE - Showing variable values${RESET}"
            shift
            # Re-process remaining arguments
            if [[ $# -gt 0 ]]; then
                main "$@"
            else
                AUTO_MODE=true full_install "stealthiq"
            fi
            ;;
        --dry-run)
            DRY_RUN=true
            msg "${YELLOW}DRY RUN MODE - No changes will be made${RESET}"
            check_prerequisites
            detect_conflicts
            backup_configs
            copy_dotfiles
            # Show what would be installed
            msg "[DRY RUN] Would update CA certificates"
            msg "[DRY RUN] Would detect and install graphics drivers (NVIDIA/AMD/Intel)"
            msg "[DRY RUN] Would install paru (AUR helper) if not present"
            msg "[DRY RUN] Would install pacman packages: hyprland, hyprpaper, hyprlock, hypridle, dunst, conky, btop, mpd, ncmpcpp, cava, playerctl, pavucontrol, easyeffects, kitty, zsh, fish, grim, slurp, wl-clipboard, hyprshot, cliphist, brightnessctl, fuzzel, rofi, wlogout, thunar, dolphin, nautilus, yazi, fonts, python, qt, ydotool, hyprsunset..."
            msg "[DRY RUN] Would install AUR packages: quickshell, activitywatch-bin, vicinae-git, handy-git, python-materialyoucolor, songrec, microtex, pokemon-colorscripts-git, brave-bin, obsidian, megasync, ulauncher, bitwarden, spotify, visual-studio-code-bin, emojione-picker"
            msg "[DRY RUN] Would setup: StealthIQ (symlink hypr -> hypr-stealthiq)"
            msg "[DRY RUN] Would make paths portable in $CONFIG_DIR"
            ;;
        "")
            # Default: run stealthiq installation directly
            AUTO_MODE=true full_install "stealthiq"
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    
    # Show rollback message on interrupt
    if [[ $exit_code -ne 0 ]] && [[ -n "${checkpoint:-}" ]]; then
        echo
        echo "${YELLOW}Operation interrupted or failed${RESET}"
        echo "${CYAN}Rolling back to checkpoint: $(basename "$checkpoint")${RESET}"
        restore_checkpoint "$checkpoint" 2>/dev/null || true
    fi
    
    release_lock 2>/dev/null || true
    
    # Restore original file descriptors and close tee processes properly
    if [[ -e /proc/self/fd/3 ]]; then
        exec 1>&3 2>&4
        exec 3>&- 4>&-
    fi
    
    if [[ $exit_code -ne 0 ]] && [[ -f "$LOG_FILE" ]]; then
        echo
        echo "${RED}Installation failed (exit code: $exit_code)${RESET}"
        echo "${YELLOW}Check log: $LOG_FILE${RESET}"
        
        if [[ -f "$BACKUP_ROOT/latest.txt" ]]; then
            echo "${CYAN}Backup location: $(cat "$BACKUP_ROOT/latest.txt")${RESET}"
        fi
        
        # List available checkpoints
        if [[ -d "$CHECKPOINT_DIR" ]] && [[ $(ls -A "$CHECKPOINT_DIR" 2>/dev/null) ]]; then
            echo "${CYAN}Available checkpoints for rollback:${RESET}"
            ls -t "$CHECKPOINT_DIR" | head -5 | while read -r cp; do
                echo "  - $cp"
            done
        fi
    fi
    
    exit $exit_code
}
trap cleanup EXIT INT TERM HUP

# =============================================================================
# CHECKPOINT MANAGEMENT
# =============================================================================

# List available checkpoints
list_checkpoints() {
    header "AVAILABLE CHECKPOINTS"
    
    if [[ ! -d "$CHECKPOINT_DIR" ]] || [[ -z $(ls -A "$CHECKPOINT_DIR" 2>/dev/null) ]]; then
        msg "No checkpoints found"
        return 0
    fi
    
    echo
    for cp_dir in "$CHECKPOINT_DIR"/*; do
        [[ -d "$cp_dir" ]] || continue
        
        local name=""
        local time=""
        local kernel=""
        
        if [[ -f "$cp_dir/metadata.txt" ]]; then
            name=$(grep "CHECKPOINT_NAME=" "$cp_dir/metadata.txt" 2>/dev/null | cut -d= -f2)
            time=$(grep "CHECKPOINT_TIME=" "$cp_dir/metadata.txt" 2>/dev/null | cut -d= -f2)
            kernel=$(grep "KERNEL_VERSION=" "$cp_dir/metadata.txt" 2>/dev/null | cut -d= -f2)
        fi
        
        echo "${GREEN}$(basename "$cp_dir")${RESET}"
        echo "  Name: ${name:-unknown}"
        echo "  Time: ${time:-unknown}"
        [[ -n "$kernel" ]] && echo "  Kernel: $kernel"
        echo
    done
}

# Rollback to specific checkpoint
rollback_to_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_path=""
    
    # Find checkpoint by name or full path
    if [[ -d "$checkpoint_name" ]]; then
        checkpoint_path="$checkpoint_name"
    elif [[ -d "$CHECKPOINT_DIR/$checkpoint_name" ]]; then
        checkpoint_path="$CHECKPOINT_DIR/$checkpoint_name"
    else
        # Try partial match
        checkpoint_path=$(find "$CHECKPOINT_DIR" -maxdepth 1 -type d -name "*$checkpoint_name*" 2>/dev/null | head -1)
    fi
    
    if [[ -z "$checkpoint_path" ]] || [[ ! -d "$checkpoint_path" ]]; then
        error "Checkpoint not found: $checkpoint_name"
        list_checkpoints
        return 1
    fi
    
    header "ROLLING BACK TO CHECKPOINT"
    msg "Checkpoint: $(basename "$checkpoint_path")"
    
    acquire_lock
    restore_checkpoint "$checkpoint_path"
    release_lock
    
    success "Rollback complete"
}

# Run
main "$@"
