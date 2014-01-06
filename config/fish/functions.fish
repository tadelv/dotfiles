#echo "Loading functions ..."

function extract --description "Extract an archive"
  if begin; not test -z $argv[1]; and test -f $argv[1]; end
    switch $argv[1]
      case '*.tar.bz2'
        tar xjf $argv[1]
      case '*.tar.gz'
        tar xzf $argv[1]
      case '*.bz2'
        bunzip2 $argv[1]
      case '*.rar'
        rar x $argv[1]
      case '*.gz'
        gunzip $argv[1]
      case '*.tar'
        tar xf $argv[1]
      case '*.tbz2'
        tar xjf $argv[1]
      case '*.tgz'
        tar xzf $argv[1]
      case '*.zip'
        unzip $argv[1]
      case '*.Z'
        uncompress $argv[1]
      case '*.7z'
        7za x $argv[1]
      case '*'
        echo "'$argv[1]' cannot be extracted via extract()" ;;
    end
  else
    echo "'$argv[1]' is not a valid file"
  end
end

function l -d "long list"
  ls -la $argv
end

function subl -d "Sublime editor in a new window"
  /Applications/Sublime\ Text.app/Contents/SharedSupport/bin/subl -n $argv
end

# shorthands

function work -d "change to work directory"
  cd ~/development/work
end

function dev -d "development directory"
  cd ~/development
end

function scratch
  dev; cd scratch
end

function repos
  dev; cd repos
end

function dot
  repos; cd dotfiles
end

function xc
  open *.xcodeproj
end

# Helpers

function is_git
  git status >/dev/null ^&1
  return $status
end

# SVN stuff

function sup
  svn up $argv[1]
end

function sco
  svn co $argv[1]
end

function com
  if is_git
    git commit $argv
  else
    svn commit $argv
  end
end

function st
  if is_git
    git status $argv
  else
    svn status $argv
  end
end
