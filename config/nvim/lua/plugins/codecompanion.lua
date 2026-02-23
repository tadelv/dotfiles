return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "Davidyz/VectorCode",
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    adapters = {
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            env = {
              CLAUDE_CODE_OAUTH_TOKEN = vim.env.CLAUDE_CODE_OAUTH_TOKEN,
            },
          })
        end,
      },
      -- DeepSeek: chat + inline fallback
      deepseek = function()
        return require("codecompanion.adapters").extend("openai", {
          env = {
            api_key = vim.env.DEEPSEEK_API_KEY,
          },
          url = os.getenv("DEEPSEEK_API_BASE") or "https://api.deepseek.com",
          supports_tools = false,
          schema = {
            model = {
              default = "deepseek-chat",
              choices = {
                "deepseek-chat",
                "deepseek-coder",
              },
            },
            max_tokens = { default = 8192 },
            temperature = { default = 0.3 },
          },
        })
      end,
      -- OpenAI: tools + agents
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          env = {
            api_key = vim.env.OPENAI_API_KEY,
          },
          schema = {
            model = {
              default = "gpt-4.1-mini",
            },
            max_tokens = { default = 4096 },
            temperature = { default = 0.1 },
          },
        })
      end,
    },
    interactions = {
      chat = { adapter = "claude_code" },
    },
  },
}
