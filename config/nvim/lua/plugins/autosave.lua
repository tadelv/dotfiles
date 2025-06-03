-- lua
return {
  "0x00-ketsu/autosave.nvim",
  -- lazy-loading on events
  event = { "InsertLeave", "TextChanged", "TextChangedI" },
  config = function()
    require("autosave").setup({
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      events = { "InsertLeave", "TextChanged" },
      debounce_delay = 1300,
      prompt_message = function()
        local msg = "💾: " .. vim.fn.strftime("%H:%M:%S")
        require("fidget").notify(msg)
        return ""
      end,
      prompt_style = "notify",
    })
  end,
}
