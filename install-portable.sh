#!/bin/bash
# Portable dotfiles installer - works on any username

set -e

# Colors
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
reset=$(tput sgr0)

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

echo "${blue}Portable Dotfiles Installer${reset}"
echo "Home: $HOME_DIR"
echo "Dotfiles: $DOTFILES_DIR"
echo ""

# Backup existing configs
backup_configs() {
    echo "${yellow}Backing up existing configs...${reset}"
    BACKUP_DIR="$HOME_DIR/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    for dir in hypr quickshell hyprpaper dunst conky rofi zsh; do
        if [ -d "$HOME_DIR/.config/$dir" ]; then
            cp -r "$HOME_DIR/.config/$dir" "$BACKUP_DIR/" 2>/dev/null || true
        fi
    done
    
    if [ -f "$HOME_DIR/.zshrc" ]; then
        cp "$HOME_DIR/.zshrc" "$BACKUP_DIR/" 2>/dev/null || true
    fi
    
    echo "${green}✓ Backup saved to: $BACKUP_DIR${reset}"
}

# Copy and fix configs
install_configs() {
    echo "${yellow}Installing configs...${reset}"
    
    # Copy config directories
    for dir in dot_config/*; do
        if [ -d "$dir" ]; then
            target_name=$(basename "$dir" | sed 's/^dot_//')
            echo "  Installing $target_name..."
            cp -r "$dir" "$HOME_DIR/.config/$target_name"
        fi
    done
    
    # Copy shell configs
    if [ -f "$DOTFILES_DIR/dot_zshrc" ]; then
        cp "$DOTFILES_DIR/dot_zshrc" "$HOME_DIR/.zshrc"
        echo "  Installing .zshrc..."
    fi
    
    if [ -f "$DOTFILES_DIR/dot_bashrc" ]; then
        cp "$DOTFILES_DIR/dot_bashrc" "$HOME_DIR/.bashrc"
        echo "  Installing .bashrc..."
    fi
    
    echo "${green}✓ Configs installed${reset}"
}

# Make all paths portable
make_portable() {
    echo "${yellow}Making configs portable...${reset}"
    
    # Replace hardcoded usernames with $HOME in key files
    find "$HOME_DIR/.config" -type f \( \
        -name "*.conf" -o \
        -name "*.zsh" -o \
        -name "*.sh" -o \
        -name "*.lua" \
    \) 2>/dev/null | while read -r file; do
        # Use $HOME variable instead of hardcoded path
        sed -i "s|/home/[^/]*/|$HOME/|g" "$file" 2>/dev/null || true
    done
    
    # Fix zshrc
    sed -i "s|/home/[^/]*/|$HOME/|g" "$HOME_DIR/.zshrc" 2>/dev/null || true
    
    echo "${green}✓ Paths are now portable${reset}"
}

# Main
main() {
    echo "${blue}=================================${reset}"
    echo "${blue}  Portable Dotfiles Installer${reset}"
    echo "${blue}=================================${reset}"
    echo ""
    
    read -p "Continue with installation? (y/n): " confirm
    if [[ "$confirm" != [yY]* ]]; then
        echo "Aborted."
        exit 0
    fi
    
    backup_configs
    install_configs
    make_portable
    
    echo ""
    echo "${green}=================================${reset}"
    echo "${green}  Installation Complete!${reset}"
    echo "${green}=================================${reset}"
    echo ""
    echo "Next steps:"
    echo "1. Install dependencies: paru -S hyprpaper dunst conky mpd ncmpcpp"
    echo "2. Log out and log back in"
    echo ""
    echo "To switch between setups, use: ~/switch-hyprland-setup.sh"
}

main

# Fix conky paths (conky doesn't expand $HOME)
fix_conky() {
    if [ -f ~/.config/conky/.conkyrc ]; then
        echo "${yellow}Fixing conky paths...${reset}"
        sed -i "s|\\$HOME|$HOME|g" ~/.config/conky/.conkyrc
        echo "${green}✓ Conky paths fixed${reset}"
    fi
}

# Add this call in the install_configs function or at the end
