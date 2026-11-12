#!/usr/bin/env bash
# Set up an Ubuntu 24.04 machine for these dotfiles: packages, tools built or downloaded
# outside apt, and the links from ~ and ~/.config into this repo.
# Safe to rerun: each step skips what is already there.
#
# Usage: ./install.sh            run every step in order
#        ./install.sh links fonts run only the named steps (see STEPS below)
set -euo pipefail

DOTFILES=$(cd "$(dirname "$0")" && pwd)
BIN=$HOME/.local/bin
OPT=$HOME/.local/opt

NVIM_VERSION=v0.12.6
GREENCLIP_VERSION=v4.2
QTILE_VERSION=0.37.1
I3LOCK_COLOR_VERSION=2.13.c.5
I3LOCK_COLOR_DIR=$HOME/i3lock-color

export PATH="$BIN:$HOME/.cargo/bin:$PATH"

log() { printf '\n==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Link $DOTFILES/$1 to $2. Anything else already at $2 is renamed with a .bak suffix, not deleted.
link() {
    local src=$DOTFILES/$1 dest=$2
    [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] && return
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        mv "$dest" "$dest.bak-$(date +%Y%m%d-%H%M%S)"
        echo "moved old $dest aside"
    fi
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    echo "linked $dest -> $src"
}

step_submodules() {
    log "Submodules (qtile, nvim)"
    git -C "$DOTFILES" submodule update --init
}

step_apt() {
    log "apt packages"
    if ! ls /etc/apt/sources.list.d/ | grep -q ibus-bamboo; then
        sudo add-apt-repository -y ppa:bamboo-engine/ibus-bamboo
    fi
    local packages=(
        # Base and build tools
        git curl build-essential cmake pkg-config python3
        # Qtile session: autostart.sh, keys.py and the bar
        rofi dunst libnotify-bin picom xss-lock i3lock x11-xserver-utils poweralertd
        ibus ibus-bamboo network-manager-gnome blueman bluez policykit-1-gnome
        thunar xclip keepassxc libpangocairo-1.0-0
        # Shell, terminal and editor tools
        tmux htop ripgrep ncurses-term zathura zathura-pdf-poppler latexmk clangd-18
        # Fonts not from Nerd Fonts (the lock screen uses EB Garamond)
        fonts-ebgaramond-extra fonts-dejavu
        # To build alacritty
        libfontconfig1-dev libfreetype6-dev libxcb-xfixes0-dev libxkbcommon-dev
        # To build i3lock-color
        autoconf automake libpam0g-dev libcairo2-dev libxcb-composite0-dev libev-dev
        libx11-xcb-dev libxcb-xkb-dev libxcb-xinerama0-dev libxcb-randr0-dev
        libxcb-image0-dev libxcb-util0-dev libxcb-xrm-dev libxkbcommon-dev
        libxkbcommon-x11-dev libjpeg-dev libgif-dev
    )
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
    sudo update-alternatives --install /usr/bin/clangd clangd /usr/bin/clangd-18 100
}

step_snaps() {
    log "Snaps (browser and mail, launched at login)"
    sudo snap install firefox thunderbird
}

step_rust() {
    log "Rust and cargo tools"
    if [ ! -x "$HOME/.cargo/bin/cargo" ]; then
        # --no-modify-path: .bashrc already sources ~/.cargo/env, and it is a link into this repo
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    fi
    have alacritty || cargo install alacritty --locked
}

step_uv() {
    log "uv and uv tools (qtile, autorandr, Python editor tools)"
    if ! have uv; then
        curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
    fi
    local installed
    installed=$(uv tool list 2>/dev/null)
    grep -q '^qtile ' <<<"$installed" || uv tool install "qtile==$QTILE_VERSION" \
        --with "qtile-extras==$QTILE_VERSION" --with dbus-fast --with pulsectl \
        --with pulsectl-asyncio --with psutil --with requests --with aiohttp
    grep -q '^autorandr ' <<<"$installed" || uv tool install autorandr
    grep -q '^python-lsp-server ' <<<"$installed" || uv tool install python-lsp-server --with pylsp-mypy
    grep -q '^ruff ' <<<"$installed" || uv tool install ruff
    grep -q '^mypy ' <<<"$installed" || uv tool install mypy
}

step_tools() {
    log "Downloaded tools (nvim, starship, fzf, greenclip, rofi-power-menu)"
    mkdir -p "$BIN" "$OPT"

    if [ ! -x "$OPT/nvim-$NVIM_VERSION/bin/nvim" ]; then
        local tmp
        tmp=$(mktemp -d)
        curl -fsSL "https://github.com/neovim/neovim/releases/download/$NVIM_VERSION/nvim-linux-x86_64.tar.gz" |
            tar -xz -C "$tmp"
        mv "$tmp/nvim-linux-x86_64" "$OPT/nvim-$NVIM_VERSION"
        rm -rf "$tmp"
    fi
    ln -sfn "$OPT/nvim-$NVIM_VERSION/bin/nvim" "$BIN/nvim"

    have starship || curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$BIN"

    if [ ! -d "$HOME/.fzf" ]; then
        git clone --depth 1 https://github.com/junegunn/fzf "$HOME/.fzf"
    fi
    # Writes ~/.fzf.bash, which .bashrc sources
    [ -f "$HOME/.fzf.bash" ] || "$HOME/.fzf/install" --key-bindings --completion --no-update-rc

    if ! have greenclip; then
        curl -fsSL -o "$BIN/greenclip" \
            "https://github.com/erebe/greenclip/releases/download/$GREENCLIP_VERSION/greenclip"
        chmod +x "$BIN/greenclip"
    fi

    if ! have rofi-power-menu; then
        curl -fsSL -o "$BIN/rofi-power-menu" \
            https://raw.githubusercontent.com/jluttine/rofi-power-menu/master/rofi-power-menu
        chmod +x "$BIN/rofi-power-menu"
    fi
}

step_fonts() {
    log "Nerd Fonts (FiraCode for qtile, alacritty, dunst, zathura; JetBrainsMono for rofi)"
    local name dir changed=
    for name in FiraCode JetBrainsMono; do
        fc-list : family | grep -q "$name Nerd Font" && continue
        dir=$HOME/.local/share/fonts/$name-NerdFont
        mkdir -p "$dir"
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.tar.xz" |
            tar -xJ -C "$dir"
        changed=1
    done
    [ -z "$changed" ] || fc-cache -f
}

step_tmux() {
    log "tmux plugin manager"
    [ -d "$HOME/.tmux/plugins/tpm" ] || git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
}

step_i3lock_color() {
    log "i3lock-color $I3LOCK_COLOR_VERSION (for qtile/lock.sh)"
    if [ ! -d "$I3LOCK_COLOR_DIR" ]; then
        git clone --depth 1 --branch "$I3LOCK_COLOR_VERSION" \
            https://github.com/Raymo111/i3lock-color "$I3LOCK_COLOR_DIR"
    fi
    [ -x "$I3LOCK_COLOR_DIR/build/i3lock" ] || (cd "$I3LOCK_COLOR_DIR" && ./build.sh)
    mkdir -p "$BIN"
    ln -sfn "$I3LOCK_COLOR_DIR/build/i3lock" "$BIN/i3lock-color"
}

step_nvim() {
    log "Neovim tools (nvim/setup.sh)"
    (cd "$DOTFILES/nvim" && sh ./setup.sh)
}

step_links() {
    log "Links into this repo"
    link .bashrc ~/.bashrc
    link .bash_aliases ~/.bash_aliases
    link .inputrc ~/.inputrc
    link qtile_start.sh ~/qtile_start.sh
    link greenclip.toml ~/.config/greenclip.toml
    link starship.toml ~/.config/starship.toml
    local dir
    for dir in alacritty autorandr dunst nvim picom qtile rofi tmux zathura; do
        link "$dir" ~/.config/"$dir"
    done
}

step_session() {
    log "Qtile entry on the login screen"
    local entry=/usr/share/xsessions/qtile.desktop
    local content="[Desktop Entry]
Name=Qtile
Comment=Qtile Session
Exec=$HOME/qtile_start.sh
Type=Application
Keywords=wm;tiling"
    if [ "$(cat "$entry" 2>/dev/null)" != "$content" ]; then
        printf '%s\n' "$content" | sudo tee "$entry" >/dev/null
        echo "wrote $entry"
    fi
}

STEPS=(submodules apt snaps rust uv tools fonts tmux i3lock_color nvim links session)

if [ $# -eq 0 ]; then
    set -- "${STEPS[@]}"
fi
for step in "$@"; do
    if ! declare -F "step_$step" >/dev/null; then
        echo "unknown step: $step (steps: ${STEPS[*]})" >&2
        exit 1
    fi
done
for step in "$@"; do
    "step_$step"
done

log "Done. By hand:"
echo "- In tmux, press prefix + I to install the tmux plugins."
echo "- Put the GitHub token for the bar at ~/tokens/github.token and API keys in ~/.api_key."
echo "- Language servers beyond pylsp, ruff, mypy and clangd: see nvim/README.md."
echo "- Apps from their own repos: spotify, zotero, discord, docker (bentopdf container)."
