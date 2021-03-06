#!/usr/bin/env ruby

# from http://errtheblog.com/posts/89-huba-huba

home = ENV['HOME']

Dir.chdir File.dirname(__FILE__) do
  dotfiles_dir = Dir.pwd.sub(home + '/', '')

  Dir['*'].each do |file|
    next if file == 'install.rb' || file == 'additional'
    target_name = file == 'bin' ? file : ".#{file}"
    target = File.join(home, target_name)
    #if file exists, delete/bak it first
    system %[ln -vsf #{File.join(dotfiles_dir, file)} #{target}]
  end
end
