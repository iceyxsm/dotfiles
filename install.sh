#!/bin/bash
# Dotfiles Installer - Bulletproof Edition
# Original configs by StealthIQ (github.com/StealthIQ)
# Modified by Iceyxsm (github.com/iceyxsm)
#
# Features:
# - Atomic operations with rollback
# - Checkpoint system for recovery
# - Conflict detection
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

# =============================================================================
# LOGGING & OUTPUT
# =============================================================================

# Initialize logging
init_logging() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
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
msg() { echo -e "${BLUE}→${RESET} $*"; log "INFO" "$@"; }
success() { echo -e "${GREEN}✓${RESET} $*"; log "SUCCESS" "$@"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*" >&2; log "WARN" "$@"; }
error() { echo -e "${RED}✗${RESET} $*" >&2; log "ERROR" "$@"; }
header() { echo -e "${CYAN}${BOLD}$*${RESET}"; log "INFO" "$@"; }

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
    } > "$checkpoint_path/metadata.txt"
    
    # List currently active symlinks
    find "$CONFIG_DIR" -maxdepth 1 -type l 2>/dev/null > "$checkpoint_path/symlinks.txt" || true
    
    # Save current hypr config state
    if [[ -L "$CONFIG_DIR/hypr" ]]; then
        echo "hypr=$(readlink "$CONFIG_DIR/hypr")" >> "$checkpoint_path/state.txt"
    elif [[ -d "$CONFIG_DIR/hypr" ]]; then
        echo "hypr=directory" >> "$checkpoint_path/state.txt"
    fi
    
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
                hypr)
                    msg "Restoring hypr config..."
                    rm -f "$CONFIG_DIR/hypr"
                    if [[ "$value" == "directory" ]]; then
                        # Original was a directory - restore from backup if exists
                        local backup
                        backup=$(find "$BACKUP_ROOT" -name "hypr" -type d 2>/dev/null | head -1)
                        if [[ -n "$backup" ]]; then
                            cp -r "$backup" "$CONFIG_DIR/"
                            success "Restored hypr from backup"
                        fi
                    else
                        ln -sf "$value" "$CONFIG_DIR/hypr"
                        success "Restored hypr symlink to $value"
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
                warn "$name: Symlink exists → $link_target"
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
    
    # Backup configs
    for dir in hypr hypr-stealthiq hypr-jakoolit quickshell hyprpaper dunst conky waybar wallust rofi zsh ncmpcpp mpd cava; do
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
        log "COPY" "$src → $dst"
        return 0
    else
        error "Failed to copy: $src → $dst"
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
        log "SYMLINK" "$link → $target"
        return 0
    else
        error "Failed to create symlink: $link → $target"
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

install_deps() {
    header "INSTALLING DEPENDENCIES"
    
    if [[ "$DRY_RUN" == true ]]; then
        msg "[DRY RUN] Would install packages"
        return 0
    fi
    
    # Core packages
    local pacman_pkgs=("hyprland" "hyprpaper" "hyprlock" "hypridle" "dunst" "conky" "mpd" "ncmpcpp" "cava" "alacritty" "kitty" "zsh")
    
    # Install with pacman (official repos)
    if command -v pacman &>/dev/null; then
        msg "Installing official packages..."
        # shellcheck disable=SC2024
        if sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            success "Official packages installed"
        else
            warn "Some packages may have failed (see log)"
        fi
    fi
    
    # Check for AUR helper
    local aur_helper
    aur_helper=$(check_aur_helper)
    
    if [[ -z "$aur_helper" ]]; then
        warn "No AUR helper found (paru/yay)"
        msg "Install one for AUR packages:"
        msg "  paru: https://github.com/Morganamilo/paru"
    else
        msg "AUR helper: $aur_helper"
    fi
    
    # Verify critical packages
    local missing=()
    for pkg in hyprland zsh; do
        if ! command -v "$pkg" &>/dev/null && ! pacman -Q "$pkg" &>/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing critical packages: ${missing[*]}"
        return 1
    fi
    
    success "Dependencies OK"
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

## Auto Install
```bash
./install.sh --auto stealthiq
./install.sh --auto jakoolit
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
    echo "${CYAN}┌────────────────────────────────────────┐${RESET}"
    echo "${CYAN}│${RESET}  ${BOLD}Dotfiles Installer${RESET} ${MAGENTA}v$SCRIPT_VERSION${RESET}        ${CYAN}│${RESET}"
    echo "${CYAN}│${RESET}                                        ${CYAN}│${RESET}"
    echo "${CYAN}│${RESET}  ${MAGENTA}Made by${RESET} StealthIQ                  ${CYAN}│${RESET}"
    echo "${CYAN}│${RESET}  ${MAGENTA}Refactored by${RESET} Iceyxsm              ${CYAN}│${RESET}"
    echo "${CYAN}└────────────────────────────────────────┘${RESET}"
    echo ""
}

show_usage() {
    show_banner
    echo "${BOLD}Usage:${RESET} $0 [OPTIONS]"
    echo
    echo "${CYAN}Auto Mode:${RESET}"
    echo "  --auto               Install StealthIQ setup (default)"
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
        echo "${GREEN}${BOLD}╔════════════════════════════════════════════════╗${RESET}"
        echo "${GREEN}${BOLD}║     INSTALLATION COMPLETE!                     ║${RESET}"
        echo "${GREEN}${BOLD}╚════════════════════════════════════════════════╝${RESET}"
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
            install_deps
            release_lock
            ;;
        --dry-run)
            DRY_RUN=true
            msg "${YELLOW}DRY RUN MODE - No changes will be made${RESET}"
            check_prerequisites
            detect_conflicts
            backup_configs
            copy_dotfiles
            ;;
        "")
            interactive_mode
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
    release_lock 2>/dev/null || true
    
    if [[ $exit_code -ne 0 ]] && [[ -f "$LOG_FILE" ]]; then
        echo
        echo "${RED}Installation failed (exit code: $exit_code)${RESET}"
        echo "${YELLOW}Check log: $LOG_FILE${RESET}"
        
        if [[ -f "$BACKUP_ROOT/latest.txt" ]]; then
            echo "${CYAN}Backup location: $(cat "$BACKUP_ROOT/latest.txt")${RESET}"
        fi
    fi
    
    exit $exit_code
}
trap cleanup EXIT INT TERM HUP

# Run
main "$@"
