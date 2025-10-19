-- LSP keymaps
return {
  "neovim/nvim-lspconfig",
  opts = function()
    local keys = require("lazyvim.plugins.lsp.keymaps").get()
    -- change a keymap
    -- keys[#keys + 1] = { "K", "<cmd>echo 'hello'<cr>" }
    -- disable a keymap
    -- keys[#keys + 1] = { "K", false }
    -- add a keymap
    -- keys[#keys + 1] = { "H", "<cmd>echo 'hello'<cr>" }
    -- open in new vertical split
    keys[#keys + 1] = { "gt", false }
    keys[#keys + 1] = { "gt", "<cmd>vsp | lua vim.lsp.buf.definition()<cr>" }
  end,
}
