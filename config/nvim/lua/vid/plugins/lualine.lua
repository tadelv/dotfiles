local function xcodebuild_device()
  if vim.g.xcodebuild_platform == "macOS" then
    return " macOS"
  end

  local deviceIcon = ""
  if vim.g.xcodebuild_platform:match("watch") then
    deviceIcon = "􀟤"
  elseif vim.g.xcodebuild_platform:match("tv") then
    deviceIcon = "􀡴 "
  elseif vim.g.xcodebuild_platform:match("vision") then
    deviceIcon = "􁎖 "
  end

  if vim.g.xcodebuild_os then
    return deviceIcon .. " " .. vim.g.xcodebuild_device_name .. " (" .. vim.g.xcodebuild_os .. ")"
  end

  return deviceIcon .. " " .. vim.g.xcodebuild_device_name
end

return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local lualine = require("lualine")
    local lazy_status = require("lazy.status") -- to configure lazy pending updates count

    -- configure lualine with modified theme
    lualine.setup({
      options = {
        globalstatus = true,
      },
      sections = {
        lualine_x = {
          {
            lazy_status.updates,
            cond = lazy_status.has_updates,
            -- color = { fg = "#ff9e64" },
          },
          -- { "encoding" },
          -- { "fileformat" },
          { "' ' .. vim.g.xcodebuild_last_status", color = { fg = "Gray" } },
          { "'󰓾 ' .. vim.g.xcodebuild_scheme" },
          { xcodebuild_device, color = { fg = "#f9e2af", bg = "#161622" } },
          { "filetype" },
        },
      },
      winbar = {
        lualine_a = { "'hello'" },
        lualine_b = {},
        lualine_c = { 'filename' },
        lualine_x = {},
        lualine_y = {},
        lualine_z = {},
      },
      inactive_winbar = {
        lualine_a = {},
        lualine_b = { 'filename' },
        lualine_c = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = {},
      },
    })
  end,
}
