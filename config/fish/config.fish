
. ~/.config/fish/functions.fish


set -x N_PREFIX ~/bin/n
set -x PATH $N_PREFIX/bin ~/bin /usr/local/bin $PATH
set -x EDITOR 'mate -w'

# add qt and gems paths
set -x PATH /usr/local/opt/qt/bin ~/gems $PATH

# set gems home
# gem_home does it better
# gem_home ~/gems
set -x GEM_HOME "$HOME/gems"

# Qt configs --> broken
#
#set -g fish_user_paths "/usr/local/opt/qt/bin" $fish_user_paths

# export LDFLAGS="-L/usr/local/opt/qt/lib"
# export CPPFLAGS="-I/usr/local/opt/qt/include"
# export PKG_CONFIG_PATH="/usr/local/opt/qt/lib/pkgconfig"


# rbenv config
#
#status --is-interactive; and source (rbenv init -| psub)
