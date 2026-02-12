# Fish config file

if test -d "/usr/local/opt/ruby/bin"
	fish_add_path /usr/local/opt/ruby/bin
end

if test -d "/opt/homebrew/opt/ruby/bin"
	fish_add_path /opt/homebrew/opt/ruby/bin
end

fish_add_path (gem environment gemhome)/bin

. ~/.config/fish/functions.fish

set -x EDITOR 'nvim'

. ~/.config/fish/private.fish

set arch (uname -m)
if [ $arch = "arm64" ];
	eval (/opt/homebrew/bin/brew shellenv)
end

# dotfiles bin
set PATH $PATH ~/bin

# Created by `pipx` on 2024-06-15 20:29:10
set PATH $PATH ~/.local/bin
set PATH $PATH ~/development/flutter/bin
set PATH $PATH ~/.pub-cache/bin/

# toolchains
set PATH $PATH ~/development/repos/tup
set PATH $PATH /Applications/ArmGNUToolchain/15.2.rel1/arm-none-eabi/bin

# Android SDK
set -gx ANDROID_HOME $HOME/Library/Android/sdk
set -gx ANDROID_SDK_ROOT $ANDROID_HOME
if test -d "$ANDROID_HOME"
    fish_add_path $ANDROID_HOME/cmdline-tools/latest/bin
    fish_add_path $ANDROID_HOME/platform-tools
    fish_add_path $ANDROID_HOME/emulator
end

# JDK 17 (for Flutter/Android)
if test -d "/Library/Java/JavaVirtualMachines/temurin-17.jdk"
    set -gx JAVA_HOME /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home
else if test -x /usr/libexec/java_home; and /usr/libexec/java_home -v 17 >/dev/null 2>&1
    set -gx JAVA_HOME (/usr/libexec/java_home -v 17)
end

# LLVM (brew)
if test -d "/opt/homebrew/opt/llvm/bin"
    fish_add_path /opt/homebrew/opt/llvm/bin
end

# Pyenv
set -Ux PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
pyenv init - | source

starship init fish | source
