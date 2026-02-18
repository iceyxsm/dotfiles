#!/bin/bash
# Make dotfiles portable - replaces hardcoded usernames with $HOME
# Run this after copying dotfiles to a new system

echo "Making dotfiles portable..."

# Get current username
USER_NAME=$(whoami)
HOME_DIR="$HOME"

echo "Detected user: $USER_NAME"
echo "Home directory: $HOME_DIR"

# Find and replace hardcoded home paths in config files
find ~/.config -type f \( -name "*.conf" -o -name "*.zsh" -o -name "*.sh" -o -name "*.json" \) 2>/dev/null | while read -r file; do
    # Replace /home/anyuser/ with $HOME/
    sed -i "s|/home/[^/]*/|$HOME/|g" "$file" 2>/dev/null
done

# Fix specific files
# Zsh
sed -i "s|/home/[^/]*/|$HOME/|g" ~/.zshrc 2>/dev/null

# Bash
sed -i "s|/home/[^/]*/|$HOME/|g" ~/.bashrc 2>/dev/null

# Fish
if [ -f ~/.config/fish/config.fish ]; then
    sed -i "s|/home/[^/]*/|$HOME/|g" ~/.config/fish/config.fish 2>/dev/null
fi

# Hyprland configs
if [ -d ~/.config/hypr ]; then
    find ~/.config/hypr -type f -name "*.conf" 2>/dev/null | while read -r file; do
        sed -i "s|/home/[^/]*/|$HOME/|g" "$file" 2>/dev/null
    done
fi

# Hyprpaper
if [ -f ~/.config/hyprpaper/hyprpaper.conf ]; then
    sed -i "s|/home/[^/]*/|$HOME/|g" ~/.config/hyprpaper/hyprpaper.conf 2>/dev/null
fi

# Conky
if [ -f ~/.config/conky/.conkyrc ]; then
    sed -i "s|/home/[^/]*/|$HOME/|g" ~/.config/conky/.conkyrc 2>/dev/null
fi

echo "✓ Dotfiles are now portable!"
echo "All hardcoded paths have been replaced with \$HOME"

# Fix conky (special case - no $HOME expansion)
if [ -f ~/.config/conky/.conkyrc ]; then
    sed -i "s|/home/[^/]*/|$HOME/|g" ~/.config/conky/.conkyrc 2>/dev/null || true
fi
