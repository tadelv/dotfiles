local opt = vim.opt

-- swift commentstring
opt.commentstring = "// %s"

-- line numbers
opt.relativenumber = true
opt.number = true

-- tabs & indentation
opt.tabstop = 2
opt.shiftwidth = 2
-- opt.expandtab = true
-- opt.autoindent = true
opt.softtabstop = 2

-- line wrapping
opt.wrap = true
opt.tw = 120

-- search settings
opt.ignorecase = true
opt.smartcase = true

-- cursor line
opt.cursorline = true

-- appearance
opt.termguicolors = true
opt.background = "dark"
opt.signcolumn = "yes"

-- backspace
opt.backspace = "indent,eol,start"

-- clipboard
opt.clipboard:append("unnamedplus")

-- split windows
opt.splitright = true
opt.splitbelow = true

-- opt.iskeyword:append("-")
