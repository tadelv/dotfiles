-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("config.lsp")
require("config.commands")


-- OSC 52 clipboard helper that works through tmux/SSH
local function copy_to_osc52(content)
    if not content or content == '' then return end
    
    -- Encode to base64
    local cmd = string.format('echo -n "%s" | base64 | tr -d "\\n"', 
        content:gsub('"', '\\"'))
    local b64 = vim.fn.system(cmd):gsub('\n', '')
    
    -- OSC 52 sequence
    local osc52 = string.format('\027]52;c;%s\027\\', b64)
    
    -- Try writing directly to stdout (works in Kitty)
    io.write(osc52)
    
    -- Also try through tmux if in tmux
    if vim.env.TMUX then
        vim.fn.system('tmux set-buffer -w ' .. vim.fn.shellescape(content))
    end
end

vim.api.nvim_create_autocmd('TextYankPost', {
    pattern = '*',
    callback = function()
        -- Get the yanked content
        local content = vim.fn.getreg('"')
        if content and content ~= '' then
            copy_to_osc52(content)
            
            -- Visual feedback
            vim.cmd('echo "Yanked to Kitty clipboard"')
        end
    end,
})
