#!/usr/bin/env ruby

home = ENV['HOME']

themes_dir = home + "/Library/Application Support/Xcode/Color Themes"


Dir.chdir File.dirname(__FILE__) do
  src_dir = Dir.pwd.sub(home+ '/', '')
  
  Dir['*'].each do |theme|
    next if theme == 'install_themes.rb'
    target = File.join(themes_dir, theme)
    system %[ln -vsf #{File.join(home,src_dir, theme)} \'#{target}\']
  end
end


  