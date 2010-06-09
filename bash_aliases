# Some useful aliases
# vi:filetype=sh:
#alias aliases='vim ~/.bash_aliases && source ~/.bash_aliases'

# Function which adds an alias to the current shell and to
# the ~/.bash_aliases file.
add-alias ()
{
   local name=$1 value="$2"
   echo "alias $name='$value'" >> ~/.bash_aliases
   eval "alias $name='$value'"
   alias $name
}

#######
# git #
#######
alias gl='git pull --rebase'
alias gp='git push'
alias gd='git diff'
alias gc='git commit -v'
alias gca='git commit -v -a'
alias gb='git branch -v'

function gco {
  if [ -z "$1" ]; then
    git checkout master
  else
    git checkout $1
  fi
}

function st {
  if [ -d ".svn" ]; then
    svn status
  else
    git status
  fi
}

#######
# SVN #
#######
alias sup='svn up' # trust me 3 chars makes a different
# alias sstu='svn st -u' # remote repository changes
# alias scom='svn commit' # commit
alias svnclear='find . -name .svn -print0 | xargs -0 rm -rf' # removes all .svn folders from directory recursively
alias svnaddall='svn status | grep "^\?" | awk "{print \$2}" | xargs svn add' # adds all unadded files

########
# RUBY #
########
# use readline, completion and require rubygems by default for irb
alias irb='irb --simple-prompt -r irb/completion -rubygems'

# really awesome function, use: cdgem <gem name>, cd's into your gems directory
# and opens gem that best matches the gem name provided
#function cdgem {
#  cd `gem env gemdir`/gems
#  cd `ls | grep $1 | sort | tail -1`
#}
#function gemdoc {
#  GEMDIR=`gem env gemdir`/doc
#  open $GEMDIR/`ls $GEMDIR | grep $1 | sort | tail -1`/rdoc/index.html
#}
#function mategem {
#  GEMDIR=`gem env gemdir`/gems
#  mate $GEMDIR/`ls $GEMDIR | grep $1 | sort | tail -1`
#}

#alias qri='qri -w 98'
#alias fri='fri -w 98'

#########
# RAILS #
#########

########
# misc #
########

#alias texclean='rm -f *.toc *.aux *.log *.cp *.fn *.tp *.vr *.pg *.ky'
#alias clean='echo -n "Really clean this directory?";
#	read yorn;
#	if test "$yorn" = "y"; then
#	   rm -f \#* *~ .*~ *.bak .*.bak  *.tmp .*.tmp core a.out;
#	   echo "Cleaned.";
#	else
#	   echo "Not cleaned.";
#	fi'
alias h='history'
alias j="jobs -l"
alias l="ls -lah"
alias ll="ls -l"
alias la='ls -A'
# alias pu="pushd"
# alias po="popd"

alias m="mate ."
#alias g="git"
#alias oc="cd ~/Projects/oc"
#alias oci="cd ~/Projects/oci"
#alias lq="cd ~/Projects/livecliq"
#alias pg="cd ~/Sources/playground"
#alias dots="cd ~/dotfiles"
#alias in="cd ~/Install"
alias aliases="mate ~/.bash_aliases"
#alias s="cd ~/Sources"
#alias d="cd ~/Designs"
#alias p="cd ~/Projects"
#alias gx="gitx"
#alias gempath="cd /Library/Ruby/Gems/1.8/gems"
#alias good="git bisect good"
#alias bad="git bisect bad"
#alias gsu="git submodule update --init"




########
# my aliases
#######

alias dev="cd ~/Development"
alias repos='dev;cd repos'
alias xc='open *.xcodeproj'
alias rnd='dev;cd random'
alias pro='dev;cd projects'
alias dot='repos;cd dotfiles'

# find broken symlinks, for dotfiles
# thanks to 
# http://github.com/markcatley/dotfiles/commit/ee1b7013135f9c3813b43b9cd107b9d9294c7d49
#
# use with | grep dotfiles ;)
alias broken_links='find . -type l | (while read FN ; do test -e "$FN" || ls -ld "$FN"; done)'