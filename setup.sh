#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# macOS Development Environment Setup
# Idempotent — safe to run multiple times.
#
# Usage:
#   curl -fsSL <raw-url>/setup.sh | bash
#   — or —
#   bash ~/development/repos/dotfiles/setup.sh
# =============================================================================

echo "==> Starting environment setup..."

# -----------------------------------------------------------------------------
# Homebrew
# -----------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
else
    echo "==> Homebrew already installed"
fi

# -----------------------------------------------------------------------------
# Brew formulae
# -----------------------------------------------------------------------------
FORMULAE=(
    # C/C++ toolchain
    cmake
    ninja
    ccache
    llvm
    pkg-config
    autoconf
    automake
    libtool

    # Terminal
    tmux
    fish
    starship

    # Docker
    colima
    docker
    docker-compose
    docker-credential-helper

    # Python
    pipx
    pyenv

    # Sync
    syncthing
)

echo "==> Installing brew formulae..."
brew install "${FORMULAE[@]}" 2>&1 | grep -E "already installed|Installing|Pouring" || true

# -----------------------------------------------------------------------------
# Brew casks
# -----------------------------------------------------------------------------
CASKS=(
    android-studio
    temurin@17
    wch-ch34x-usb-serial-driver
)

echo "==> Installing brew casks..."
for cask in "${CASKS[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
        echo "    $cask already installed"
    else
        echo "    Installing $cask..."
        brew install --cask "$cask" || echo "    ⚠ $cask failed (may need sudo — run: brew install --cask $cask)"
    fi
done

# -----------------------------------------------------------------------------
# PlatformIO
# -----------------------------------------------------------------------------
if command -v pio &>/dev/null; then
    echo "==> PlatformIO already installed"
else
    echo "==> Installing PlatformIO..."
    pipx ensurepath
    pipx install platformio
fi

# -----------------------------------------------------------------------------
# Android SDK
# -----------------------------------------------------------------------------
ANDROID_HOME="$HOME/Library/Android/sdk"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

# Find JDK 17
if [ -d "/Library/Java/JavaVirtualMachines/temurin-17.jdk" ]; then
    export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home"
elif /usr/libexec/java_home -v 17 &>/dev/null; then
    export JAVA_HOME=$(/usr/libexec/java_home -v 17)
fi

# Install cmdline-tools if missing
if [ ! -f "$SDKMANAGER" ]; then
    echo "==> Installing Android SDK command-line tools..."
    mkdir -p "$ANDROID_HOME/cmdline-tools"

    CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
    TMPZIP="$(mktemp /tmp/cmdline-tools.XXXXXX.zip)"
    TMPDIR_EXTRACT="$(mktemp -d /tmp/cmdline-tools-extract.XXXXXX)"

    curl -fsSL -o "$TMPZIP" "$CMDLINE_TOOLS_URL"
    unzip -qo "$TMPZIP" -d "$TMPDIR_EXTRACT"

    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$TMPDIR_EXTRACT/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$TMPZIP" "$TMPDIR_EXTRACT"
else
    echo "==> Android SDK command-line tools already installed"
fi

# Accept licenses and install SDK components
if [ -f "$SDKMANAGER" ] && [ -n "${JAVA_HOME:-}" ]; then
    echo "==> Accepting Android SDK licenses..."
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true

    SDK_PACKAGES=(
        "platform-tools"
        "build-tools;35.0.0"
        "build-tools;36.0.0"
        "platforms;android-35"
        "platforms;android-36"
        "emulator"
        "sources;android-35"
        "ndk;27.0.12077973"
        "cmdline-tools;latest"
    )

    echo "==> Installing Android SDK packages..."
    "$SDKMANAGER" "${SDK_PACKAGES[@]}" 2>&1 | grep -E "done|already" || true
else
    echo "⚠ Skipping Android SDK setup (need JDK 17 — run: brew install --cask temurin@17)"
fi

# Configure Flutter JDK
if command -v flutter &>/dev/null && [ -n "${JAVA_HOME:-}" ]; then
    echo "==> Configuring Flutter JDK..."
    flutter config --jdk-dir="$JAVA_HOME" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Docker config
# -----------------------------------------------------------------------------
echo "==> Configuring Docker..."
mkdir -p "$HOME/.docker"
if [ ! -f "$HOME/.docker/config.json" ]; then
    cat > "$HOME/.docker/config.json" <<'DOCKER_EOF'
{
  "cliPluginsExtraDirs": [
    "/opt/homebrew/lib/docker/cli-plugins"
  ]
}
DOCKER_EOF
else
    # Ensure cliPluginsExtraDirs is present
    if ! grep -q "cliPluginsExtraDirs" "$HOME/.docker/config.json"; then
        python3 -c "
import json, pathlib
p = pathlib.Path('$HOME/.docker/config.json')
cfg = json.loads(p.read_text())
cfg['cliPluginsExtraDirs'] = ['/opt/homebrew/lib/docker/cli-plugins']
p.write_text(json.dumps(cfg, indent=2) + '\n')
" 2>/dev/null || true
    fi
    echo "    Docker config already exists"
fi

# -----------------------------------------------------------------------------
# Dotfiles (symlink)
# -----------------------------------------------------------------------------
DOTFILES_DIR="$HOME/development/repos/dotfiles"
if [ -d "$DOTFILES_DIR" ]; then
    echo "==> Linking dotfiles..."
    cd "$DOTFILES_DIR"
    ruby install.rb
    # Symlink .config subdirectories
    mkdir -p "$HOME/.config"
    for dir in "$DOTFILES_DIR/config"/*/; do
        name="$(basename "$dir")"
        ln -sfn "$DOTFILES_DIR/config/$name" "$HOME/.config/$name"
        echo "    .config/$name -> dotfiles/config/$name"
    done
    cd - >/dev/null
else
    echo "⚠ Dotfiles repo not found at $DOTFILES_DIR — skipping symlinks"
fi

# -----------------------------------------------------------------------------
# Services
# -----------------------------------------------------------------------------
echo "==> Starting services..."

# Syncthing
if brew services list | grep -q "syncthing.*started"; then
    echo "    Syncthing already running"
else
    brew services start syncthing || true
fi

# Colima
if colima status &>/dev/null; then
    echo "    Colima already running"
else
    echo "    Starting Colima..."
    colima start --cpu 4 --memory 8 --disk 60 --arch aarch64 || true
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "==> Setup complete!"
echo ""
echo "Installed:"
command -v cmake    &>/dev/null && echo "  ✓ cmake $(cmake --version | head -1 | awk '{print $3}')"
command -v ninja    &>/dev/null && echo "  ✓ ninja $(ninja --version)"
command -v ccache   &>/dev/null && echo "  ✓ ccache"
command -v clang    &>/dev/null && echo "  ✓ clang"
command -v pio      &>/dev/null && echo "  ✓ platformio $(pio --version | awk '{print $NF}')"
command -v tmux     &>/dev/null && echo "  ✓ tmux"
command -v docker   &>/dev/null && echo "  ✓ docker"
command -v colima   &>/dev/null && echo "  ✓ colima"
command -v flutter  &>/dev/null && echo "  ✓ flutter"
command -v syncthing &>/dev/null && echo "  ✓ syncthing"
[ -d "$ANDROID_HOME/platform-tools" ] && echo "  ✓ android sdk"
[ -n "${JAVA_HOME:-}" ] && echo "  ✓ jdk 17 ($JAVA_HOME)"
echo ""
echo "Manual steps (if needed):"
echo "  • Open Android Studio once to complete first-run wizard"
echo "  • Approve CH34x driver in System Settings > Privacy & Security"
echo "  • Configure Syncthing folders at http://127.0.0.1:8384"
