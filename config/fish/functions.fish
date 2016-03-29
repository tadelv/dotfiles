# echo "Loading functions ..."

function extract --description "Extract an archive"
	set archive_path $argv[1]
	if begin; not test -z $archive_path; and test -f $archive_path; end
		switch $archive_path
			case '*.tar.bz2'
				tar xjf $argv
			case '*.tar.gz'
				tar xzf $argv
			case '*.bz2'
				bunzip2 $argv
			case '*.rar'
				rar x $argv
			case '*.gz'
				gunzip $argv
			case '*.tar'
				tar xf $argv
			case '*.tbz2'
				tar xjf $argv
			case '*.tgz'
				tar xzf $argv
			case '*.zip'
				unzip $argv
			case '*.Z'
				uncompress $argv
			case '*.7z'
				7za x $argv
			case '*'
				echo "'$archive_path' cannot be extracted via extract()" ;;
		end
	else
		echo "'$archive_path' is not a valid file"
	end
end

function l -d "long list"
	ls -la $argv
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

function xcw
	open *.xcworkspace
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

function vpn_up #"Connect home"
	osascript -e 'tell application "System Events" 
		tell current location of network preferences
			set VPN to service "Home (PPTP)"
			if exists VPN then connect VPN
			repeat while (current configuration of VPN is not connected)
				delay 1
			end repeat
		end tell
	end tell'
end

function vpn_down #"Connect home"
	osascript -e 'tell application "System Events" 
		tell current location of network preferences
			set VPN to service "Home (PPTP)"
			if exists VPN then disconnect VPN
		end tell
	end tell'
end
