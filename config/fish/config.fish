# Fish config file

if test -d "/usr/local/opt/ruby/bin"
	fish_add_path /usr/local/opt/ruby/bin
end

if test -d "/opt/homebrew/opt/ruby/bin"
	fish_add_path /opt/homebrew/opt/ruby/bin
end

fish_add_path (gem environment gemhome)/bin

. ~/.config/fish/functions.fish

set -x EDITOR 'mate -w'


set arch (uname -m)
if [ $arch = "arm64" ];
	eval (/opt/homebrew/bin/brew shellenv)
end


# Created by `pipx` on 2024-06-15 20:29:10
set PATH $PATH /Users/vid/.local/bin

starship init fish | source
