function mergeTables(t1, t2)
  local merged = {}

  -- Insert elements from t1
  for k, v in pairs(t1) do
    merged[k] = v
  end

  -- Insert elements from t2
  for k, v in pairs(t2) do
    merged[k] = v
  end

  return merged
end


return {
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig",
    },
    lazy = false,
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup()

      local lspconfig = require("lspconfig")
      local ui = require("vid.core.ui")
      local borders = { border = ui.borders }
      local lsp = vim.lsp
      local handlers = {
        ["textDocument/hover"] = lsp.with(lsp.handlers.hover, borders),
        ["txtdocument/signatureHelp"] = lsp.with(lsp.handlers.signature_help, borders),
      }
      local cmp_lsp = require("cmp_nvim_lsp")
      local util = require("lspconfig.util")

      local servers = {
        clangd = {
          capabilities = cmp_lsp.default_capabilities(),
          filetypes = { "c", "cpp", "objective-c", "objective-cpp" },
        },
        sourcekit = {
          cmd = { "/Applications/Xcode-16.3.0.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp" },
          filetypes = { "swift", "objc", "objcpp", "c", "cpp" },
          root_dir = function(filename, _)
            return util.root_pattern("buildServer.json")(filename)
              or util.root_pattern("*.xcodeproj", "*.xcworkspace")(filename)
              -- better to keep it at the end, because some modularized apps contain multiple Package.swift files
              or util.root_pattern("compile_commands.json", "Package.swift")(filename)
              or util.find_git_ancestor(filename)
          end,
          get_language_id = function(_, ftype)
            local t = { objc = "objective-c", objcpp = "objective-cpp" }
            return t[ftype] or ftype
          end,
          capabilities = mergeTables(cmp_lsp.default_capabilities(), {
            workspace = {
              didChangeWatchedFiles = {
                dynamicRegistration = true,
              },
            },
          }),
        },
        -- lspconfig.rust_analyzer.setup({}),
      }

      for server, setup in pairs(servers) do
        setup.handlers = handlers
        lspconfig[server].setup(setup)
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        desc = "LSP Actions",
        callback = function(args)
          -- Once we've attached, configure the keybindings
          local wk = require("which-key")
          wk.register({
            K = { "<cmd>lua vim.lsp.buf.hover()<cr>", "LSP hover info" },
            gd = { "<cmd>lua vim.lsp.buf.definition()<cr>", "LSP go to definition" },
            gD = { "<cmd>lua vim.lsp.buf.declaration()<cr>", "LSP go to declaration" },
            gi = { "<cmd>lua vim.lsp.buf.implementation()<cr>", "LSP go to implementation" },
            gr = { "<cmd>lua vim.lsp.buf.references()<cr>", "LSP list references" },
            gt = {
              "<cmd>vsp | lua vim.lsp.buf.definition()<cr>",
              "LSP go to definition in new split",
            },
            gs = { "<cmd>lua vim.lsp.buf.signature_help()<cr>", "LSP signature help" },
            gn = { "<cmd>lua vim.lsp.buf.rename()<cr>", "LSP rename" },
            ["[g"] = { "<cmd>lua vim.diagnostic.goto_prev()<cr>", "Go to previous diagnostic" },
            ["g]"] = { "<cmd>lua vim.diagnostic.goto_next()<cr>", "Go to next diagnostic" },
          }, {
            mode = "n",
            -- buffer = true,
            silent = true,
          })
        end,
      })
      -- nice icons
      local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
      end

    end,
  },
}
