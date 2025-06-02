-- vim.lsp.config['clangd'] = {
--
-- }
--
vim.lsp.config["sourcekit"] = {
  cmd = { "/usr/bin/xcrun", "sourcekit-lsp" },
  filetypes = { "swift" },
  root_markers = {
    { "buildServer.json", "compile_commands.json", "Package.swift" },
    { "*.xcodeproj", "*.xcworkspace" },
  },
}

vim.lsp.enable("sourcekit")
-- local servers = {
--   clangd = {
--     capabilities = cmp_lsp.default_capabilities(),
--     filetypes = { "c", "cpp", "objective-c", "objective-cpp" },
--   },
--   sourcekit = {
--     -- cmd = { "/Applications/Xcode-16.3.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp" },
--     -- filetypes = { "swift", "objc", "objcpp", "c", "cpp" },
--     root_dir = function(filename, _)
--       return util.root_pattern("buildServer.json")(filename)
--         -- better to keep it at the end, because some modularized apps contain multiple Package.swift files
--         or util.root_pattern("compile_commands.json", "Package.swift")(filename)
--         or util.root_pattern("*.xcodeproj", "*.xcworkspace")(filename)
--         -- or util.find_git_ancestor(filename)
--     end,
--     -- get_language_id = function(_, ftype)
--     --   local t = { objc = "objective-c", objcpp = "objective-cpp" }
--     --   return t[ftype] or ftype
--     -- end,
--     capabilities = mergeTables(cmp_lsp.default_capabilities(), {
--       workspace = {
--         didChangeWatchedFiles = {
--           dynamicRegistration = true,
--         },
--       },
--     }),
--   },
--   -- lspconfig.rust_analyzer.setup({}),
-- }
--
-- for server, setup in pairs(servers) do
--   setup.handlers = handlers
--   lspconfig[server].setup(setup)
-- end
