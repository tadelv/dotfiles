#!/usr/bin/env ruby

# from http://errtheblog.com/posts/89-huba-huba

home = ENV['HOME']

Dir.chdir File.dirname(__FILE__) do
  dotfiles_dir = Dir.pwd.sub(home + '/', '')

  Dir['*'].each do |file|
    next if file == 'install.rb' || file == 'additional'
    target_name = file == 'bin' ? file : ".#{file}"
    target = File.join(home, target_name)
    # ln -sf would nest the link *inside* an existing real directory (e.g. ~/bin/bin);
    # move it aside first so the symlink can take its place...
    bak = nil
    if File.directory?(target) && !File.symlink?(target)
      bak = "#{target}.bak-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
      system %[mv #{target} #{bak}]
    end
    system %[ln -vsf #{File.join(dotfiles_dir, file)} #{target}]

    # ...then carry back anything that only lived in the old directory.
    next unless bak
    Dir.children(bak).each do |entry|
      next if entry == File.basename(target) # leftover of an earlier nested-link install
      dest = File.join(target, entry)
      next if File.exist?(dest) || File.symlink?(dest)
      system %[cp -Rp #{File.join(bak, entry)} #{dest}]
      puts "restored: #{entry} -> #{target}"
    end
  end

  # Optional companions the Pi config references but does not ship. They live
  # outside this repo, so a fresh machine silently lacks them.
  referenced = {
    "~/.agents/skills/karpathy-guidelines" => File.join(home, ".agents/skills/karpathy-guidelines"),
    "~/development/AGENTS.md" => File.join(home, "development/AGENTS.md"),
  }
  missing = referenced.reject { |_label, path| File.exist?(path) }
  unless missing.empty?
    puts "⚠ Pi config references paths missing on this machine:"
    missing.each_key { |label| puts "    #{label}" }
    puts "    The a-team agents read these. Create or link them, or update the agent prompts."
  end
end
