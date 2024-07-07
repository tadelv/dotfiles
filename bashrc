# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
export HISTCONTROL=ignoredups

export EDITOR="mate -w"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;36m\]\w\[\033[00m\]\[\033[01;33m\]$(parse_git_branch)\[\033[00m\]$ '

# Terminal title (git completion is required for this):
export PROMPT_COMMAND='echo -ne "\033]0;${PWD/#$HOME/~} $(__git_ps1 " (%s)")"; echo -ne "\007"' 

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME}: ${PWD/$HOME/~}\007"'
    ;;
*)
    ;;
esac

# Alias definitions.
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

if [ -f ~/bin/sake-completion ]; then
  complete -C ~/bin/sake-completion -o default sake
fi

if [ -f ~/.git-completion.bash ]; then
  source ~/.git-completion.bash
fi

# rake completion
complete -C ~/dotfiles/rake_autocomplete.rb -o default rake

# ssh completion on known hosts
SSH_COMPLETE=( $(cat ~/.ssh/known_hosts | \
cut -f 1 -d " " | \
sed -e s/,.*//g | \
uniq ) )
complete -o default -W "${SSH_COMPLETE[*]}" ssh


#rvm scripts
if [[ -s ~/.rvm/scripts/rvm ]] ; then source ~/.rvm/scripts/rvm ; fi


#makefile target autocomplete
complete -W "`test -e Makefile && grep -oE '^[a-zA-Z0-9_-]+:([^=]|$)' Makefile | sed 's/[^a-zA-Z0-9_-]*$//'`" make# 

#Install Ruby Gems to ~/gems
# export GEM_HOME=$HOME/gems
# export PATH=$HOME/gems/bin:$PATH

if [ -d "/usr/local/opt/ruby/bin" ]; then
  export PATH=/usr/local/opt/ruby/bin:$PATH
  export PATH=`gem environment gemdir`/bin:$PATH
fi