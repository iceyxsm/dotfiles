## My Arch Linux Dotfiles

Welcome to my experimental Arch Linux dotfiles repository! Please note that these configurations are a work in progress and not recommended for production setups. Use them at your own discretion.

> ** New: One-Command Installer**  
> Made by [StealthIQ](https://github.com/StealthIQ) | Refactored by [Iceyxsm](https://github.com/iceyxsm)  
> ```bash
> ./install.sh --auto
> ```
> Features: Auto-mode, checkpoint rollback, dry-run, conflict detection. See [Installation](#installation) below.

## Screenshots

![Imgur](https://i.imgur.com/MGrVLmG.png)

![Imgur](https://i.imgur.com/JlmzPOB.png)

### Setup Details

This repository contains dotfiles for a unique Arch Linux setup that includes the following components:

- **Operating System**: [Arch Linux](https://archlinux.org/download/)
- **Window Manager**: [Hyprland](https://hyprland.org/) (Wayland compositor)
- **Wallpaper**: [hyprpaper](https://github.com/hyprwm/hyprpaper)
- **Lock Screen**: [hyprlock](https://github.com/hyprwm/hyprlock)
- **Idle Daemon**: [hypridle](https://github.com/hyprwm/hypridle)
- **Bar**: [Quickshell](https://github.com/quickshell-linux/quickshell) / Waybar
- **Terminal**: [st (Luke's fork)](https://github.com/LukeSmithxyz/st) / Alacritty / Kitty
- **Shell**: [ZSH](https://github.com/zsh-users/zsh)
- **File Manager**: [ranger](https://github.com/ranger/ranger)
- **Notifications**: [dunst](https://github.com/dunst-project/dunst)
- **Music Player**: [Mpd](https://github.com/MusicPlayerDaemon/MPD) with [Ncmpcpp](https://github.com/ncmpcpp/ncmpcpp)
- **Visualizer**: [cava](https://github.com/karlstav/cava)
- **System Monitor**: [conky](https://github.com/brndnmtthws/conky)
- **Prompt**: [powerline10k](https://github.com/romkatv/powerlevel10k)
- **Font**: [iosevka](https://github.com/be5invis/Iosevka)

## Installation

### Quick Auto Install (New)
⚠️ Designed for Arch Linux with Hyprland.

```bash
git clone --depth 1 https://github.com/StealthIQ/dotfiles.git
cd dotfiles
./install.sh --auto           # Install StealthIQ setup (default)
./install.sh --auto jakoolit  # Or install JaKooLit setup
./install.sh --auto both      # Install both, switch anytime
```

**Features:**
- ✅ 100% automatic - no prompts
- ✅ Creates backup before changes
- ✅ Checkpoint system for rollback
- ✅ Dry-run mode: `./install.sh --dry-run`
- ✅ Switch setups: `./install.sh --switch [stealthiq|jakoolit]`

Made by [StealthIQ](https://github.com/StealthIQ) | Refactored by [Iceyxsm](https://github.com/iceyxsm)

---

### Manual Installation

If you prefer manual installation or the auto-installer doesn't work for your setup:

```bash
# 1. Clone the repository
git clone --depth 1 https://github.com/StealthIQ/dotfiles.git
cd dotfiles

# 2. Copy configs manually
cp -r dot_config/hypr ~/.config/hypr
cp -r dot_config/hyprpaper ~/.config/hyprpaper
cp -r dot_config/dunst ~/.config/dunst
cp -r dot_config/conky ~/.config/conky
# ... copy other configs as needed

# 3. Install dependencies
sudo pacman -S hyprland hyprpaper hyprlock hypridle dunst conky \
               mpd ncmpcpp cava alacritty kitty zsh

# 4. Set shell to zsh
chsh -s /usr/bin/zsh

# 5. Log out and back in
```

> **Note:** The manual steps above are simplified. The auto-installer handles backup, conflict detection, path fixing, and validation automatically.

### Features

- Stylish minimalist aesthetics with Hyprland (Wayland)
- Seamless wallpaper-themed customization with hyprpaper
- Quickshell/Waybar for customizable status bar
- Hyprlock for beautiful lock screen
- Consistent theme style across the desktop
- Customized P10K terminal prompt
- Conky system monitor with rings visualization
- MPD + ncmpcpp for music with visualizer


### Frequently Asked Questions (FAQ)

#### General Questions

1. **How does my theme change according to the wallpaper?**
   - I use a tool called pywal, which automatically extracts colors from the wallpaper and applies them to the theme.

2. **How do I add an audio visualizer to the bar?**
   - I utilize a script from [this GitHub repository](https://github.com/username/repo) (you will need mpd).

3. **What's the name of the music playing?**
   - The current track is "Take Off" by Chris Heria. You can find it on Spotify (download using SpotiFlyer).

4. **Have a question not listed here?**
   - Feel free to ask, and I'll do my best to provide an answer.

## My Keybindings 

#### Window Management

| Keybind                  | Action                                     |
|--------------------------|--------------------------------------------|
| <kbd>super + enter</kbd> | Spawn terminal                             |
| <kbd>super + shift + enter</kbd> | Spawn floating terminal              |
| <kbd>super + d</kbd>     | Launch rofi                                |
| <kbd>super + shift + q</kbd> | Close client                           |
| <kbd>super + control + space</kbd> | Toggle floating client            |
| <kbd>super + [1-0]</kbd> | View tag / Change workspace (for i3 folks) |
| <kbd>super + shift + [1-0]</kbd> | Move focused client to tag        |
| <kbd>super + s</kbd>     | Tiling layout                              |
| <kbd>super + shift + s</kbd> | Floating layout                          |
| <kbd>super + w</kbd>     | Maximized / Monocle layout                 |
| <kbd>super + [arrow keys]</kbd> | Change focus by direction          |
| <kbd>super + [hjkl]</kbd> | ^                                           |
| <kbd>super + shift + [arrow keys]</kbd> | Move client by direction        |
| <kbd>super + shift + [hjkl]</kbd> | ^                                    |
| <kbd>super + control + [arrow keys]</kbd> | Resize client                   |
| <kbd>super + control + [hjkl]</kbd> | ^                                       |
| <kbd>super + f</kbd>     | Toggle fullscreen                          |
| <kbd>super + m</kbd>     | Toggle maximize                            |
| <kbd>super + n</kbd>     | Minimize                                   |
| <kbd>super + shift + n</kbd> | Restore minimized                     |
| <kbd>super + c</kbd>     | Center floating client                     |
| <kbd>super + u</kbd>     | Jump to urgent client (or back to last tag if there is no such client) |
| <kbd>super + b</kbd>     | Toggle bar                                 |
| <kbd>super + =</kbd>     | Toggle tray                                |

#### Miscellaneous Actions

| Keybind                  | Action                                      |
|--------------------------|---------------------------------------------|
| <kbd>super + e</kbd>     | Launch VS Code                              |
| <kbd>super + r ; r</kbd> | Launch Librewolf Browser (Normal mode)     |
| <kbd>super + r ; p</kbd> | Launch Librewolf Browser (Private mode)    |
| <kbd>super + c</kbd>     | Toggle conky                                |
| <kbd>super + x</kbd>     | Toggle MPV                                  |
| <kbd>super + shift + c</kbd> | Launch Bleachbit                      |
| <kbd>super + l ; l ; s</kbd> | Suspend system                           |
| <kbd>super + l ; l ; b</kbd> | Lock screen with Betterlockscreen       |
| <kbd>super + l ; l ; i</kbd> | Lock screen with i3-lock-fancy          |
| <kbd>super + g ; r ; t</kbd> | Open Rofi theme selector                 |
| <kbd>super + m</kbd>     | Open Power menu                            |
| <kbd>super + a</kbd>     | Toggle Ulauncher                            |
| <kbd>ctrl + space</kbd>  | Open Rofi menu                              |
| <kbd>super + d</kbd>     | Open Rofi script menu                       |
| <kbd>super + shift + v</kbd> | Open pavucontrol                           |
| <kbd>super + semicolon</kbd> | Open Emoji Selector                      |
| <kbd>super + t</kbd>     | Open terminal (kitty)                      |
| <kbd>super + Return</kbd> | Open terminal (ST)                         |
| <kbd>super + y</kbd>     | Hide Polybar                               |
| <kbd>super + shift + y</kbd> | Hide Polybar and remove gaps             |

#### Multimedia Keys

| Keybind                  | Action                                      |
|--------------------------|---------------------------------------------|
| <kbd>XF86AudioRaiseVolume</kbd> | Increase volume                         |
| <kbd>XF86AudioLowerVolume</kbd> | Decrease volume                         |
| <kbd>XF86AudioMute</kbd> | Mute volume                                |
| <kbd>XF86AudioPlay</kbd> | Toggle play/pause (music player)         |
| <kbd>XF86AudioNext</kbd> | Play next song (music player)             |
| <kbd>XF86AudioPrev</kbd> | Play previous song (music player)         |
| <kbd>XF86AudioStop</kbd> | Stop music (music player)                  |
| <kbd>XF86MonBrightnessUp</kbd> | Increase brightness                      |
| <kbd>XF86MonBrightnessDown</kbd> | Decrease brightness                      |

### Bspwm Hotkeys

#### Window Management

| Keybind                  | Action                                      |
|--------------------------|---------------------------------------------|
| <kbd>super + shift + r</kbd> | Quit/Restart bspwm and sxhkd              |
| <kbd>alt + shift + r</kbd> | Reload sxhkd                               |
| <kbd>super + shift + Delete</kbd> | Quit bspwm                             |
| <kbd>super + {_,shift + }q</kbd> | Close and kill client                   |
| <kbd>super + space</kbd> | Alternate between the tiled and monocle layout |
| <kbd>super + f</kbd> | Set focused window to fullscreen mode     |
| <kbd>super + shift + f</kbd> | Set focused window to fullscreen mode (partial) |
| <kbd>super + shift + a</kbd> | Set focused window to tiled layout       |
| <kbd>super + shift + s</kbd> | Set focused window to floating layout    |
| <kbd>super + shift + f</kbd> | Set focused window to fullscreen layout  |
| <kbd>super + f</kbd> | Set focused window to fullscreen layout (partial) |
| <kbd>super + control + [1-9]</kbd> | Move focused window to desktop X      |
| <kbd>super + control + space</kbd> | Cancel preselection for focused node   |
| <kbd>super + control + shift + space</kbd> | Cancel preselection for focused desktop |
| <kbd>super + shift + {Left,Down,Up,Right}</kbd> | Move floating window |
| <kbd>super + shift + {h,j,k,l}</kbd> | Expand/Contract a window                  |

#### Miscellaneous Actions

| Keybind                  | Action                                      |
|--------------------------|---------------------------------------------|
| <kbd>super + g ; g ; p</kbd> | Generate random password (Bitwarden)    |
| <kbd>super + z</kbd> | Run Nitro

plex script                      |
| <kbd>super + x</kbd> | Run Nitroplex script (redundant)         |
| <kbd>super + shift + y</kbd> | Hide Polybar and remove gaps             |

### Multimedia Keys

| Keybind                  | Action                                      |
|--------------------------|---------------------------------------------|
| <kbd>XF86AudioRaiseVolume</kbd> | Increase volume                         |
| <kbd>XF86AudioLowerVolume</kbd> | Decrease volume                         |
| <kbd>XF86AudioMute</kbd> | Mute volume                                |
| <kbd>XF86AudioPlay</kbd> | Toggle play/pause (music player)         |
| <kbd>XF86AudioNext</kbd> | Play next song (music player)             |
| <kbd>XF86AudioPrev</kbd> | Play previous song (music player)         |
| <kbd>XF86AudioStop</kbd> | Stop music (music player)                  |
| <kbd>XF86MonBrightnessUp</kbd> | Increase brightness                      |
| <kbd>XF86MonBrightnessDown</kbd> | Decrease brightness                      |

### Feedback

If you have any feedback or suggestions, please reach out to me via email at stealthiq[at]protonmail[.]com or [Twitter](https://twitter.com/StealthIQQ).

### Author

- **Made by:** [@Stealthiq](https://www.github.com/stealthiq)
- **Installer Refactored by:** [@Iceyxsm](https://www.github.com/iceyxsm)

### License

This project is licensed under the [MIT License](https://choosealicense.com/licenses/mit/).
