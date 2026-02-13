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

# Pyenv
set -Ux PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin
pyenv init - | source

starship init fish | source
