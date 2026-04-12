local function opencode_zen_key()
  local path = vim.fn.expand("~/.local/share/opencode/auth.json")
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or type(data) ~= "table" then return nil end
  return data.opencode and data.opencode.key or nil
end

return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "Davidyz/VectorCode",
    "nvim-telescope/telescope.nvim",
    "nvim-treesitter/nvim-treesitter",
    "j-hui/fidget.nvim",
  },
  config = function(_, opts)
    require("codecompanion").setup(opts)

    local progress = require("fidget.progress")
    local handles = {}

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionRequestStarted",
      callback = function(ev)
        handles[ev.data.id] = progress.handle.create({
          title = "CodeCompanion",
          message = "Thinking...",
          lsp_client = { name = "CodeCompanion" },
        })
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionRequestStreaming",
      callback = function(ev)
        local h = handles[ev.data.id]
        if h then
          h.message = "Streaming..."
        end
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionRequestFinished",
      callback = function(ev)
        local h = handles[ev.data.id]
        if h then
          h.message = "Done"
          h:finish()
          handles[ev.data.id] = nil
        end
      end,
    })
  end,
  opts = {
    adapters = {
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            commands = {
              default = { "claude-code-acp", "--dangerously-skip-permissions" },
            },
            env = {
              CLAUDE_CODE_OAUTH_TOKEN = vim.env.CLAUDE_CODE_OAUTH_TOKEN,
            },
            defaults = {
              model = "opus",
            },
          })
        end,
      },
      http = {
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
        -- Ollama: local models on artemis
        ollama = function()
          return require("codecompanion.adapters").extend("ollama", {
            env = {
              url = "http://artemis.home:11434",
            },
            schema = {
              model = {
                default = "qwen2.5-coder:14b-instruct-q6_K",
              },
            },
          })
        end,
        -- OpenCode Zen: OSS third-party models via /chat/completions router
        zen = function()
          return require("codecompanion.adapters").extend("openai", {
            name = "zen",
            formatted_name = "OpenCode Zen",
            env = {
              api_key = function() return opencode_zen_key() end,
            },
            url = "https://opencode.ai/zen/v1/chat/completions",
            schema = {
              model = {
                default = "nemotron-3-super-free",
                choices = {
                  -- free tier (no payment method required)
                  "nemotron-3-super-free",
                  "minimax-m2.5-free",
                  "trinity-large-preview-free",
                  -- paid (requires Zen billing)
                  "glm-5.1",
                  "glm-5",
                  "glm-4.7",
                  "glm-4.6",
                  "kimi-k2.5",
                  "kimi-k2",
                  "kimi-k2-thinking",
                  "minimax-m2.5",
                  "minimax-m2.1",
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
    },
    interactions = {
      chat = {
        adapter = "claude_code",
        opts = {
          system_prompt = function(ctx)
            return string.format(
              [[You are an AI programming assistant working within the Neovim text editor. You help users with software engineering tasks.

# Coding philosophy

- NEVER propose changes to code you haven't seen. Ask to see the relevant buffer or file first. Understand existing code before suggesting modifications.
- Avoid over-engineering. Only make changes that are directly requested or clearly necessary. Keep solutions simple and focused.
  - Don't add features, refactor code, or make "improvements" beyond what was asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't need extra configurability.
  - Don't add docstrings, comments, or type annotations to code you didn't change. Only add comments where the logic isn't self-evident.
  - Don't add error handling, fallbacks, or validation for scenarios that can't happen. Trust internal code and framework guarantees. Only validate at system boundaries.
  - Don't create helpers, utilities, or abstractions for one-time operations. Don't design for hypothetical future requirements. Three similar lines of code is better than a premature abstraction.
- Prefer editing existing code over creating new files. Never proactively create documentation files unless asked.
- Delete unused code entirely rather than commenting it out. No backwards-compatibility hacks for removed code.
- Be careful not to introduce security vulnerabilities (command injection, XSS, SQL injection, OWASP top 10). If you notice insecure code, fix it immediately.

# Tone and style

- Responses should be short and concise.
- Use Markdown formatting.
- No emojis unless the user explicitly requests them.
- Prioritize technical accuracy over validating the user's beliefs. Provide direct, objective technical info without unnecessary superlatives, praise, or emotional validation. Disagree when technically warranted.
- Never give time estimates or predictions for how long tasks will take. Focus on what needs to be done.

# Code blocks

When suggesting code changes, use Markdown code blocks with four backticks.
After the backticks, add the language ID and file path in curly braces if available.
Use a line comment with '...existing code...' to indicate code already present in the file, using the correct comment syntax for the language.

````languageId {path/to/file}
// ...existing code...
{ changed code }
// ...existing code...
````

# Context

Use the context, attachments, and rules the user provides.
All non-code text responses must be written in %s.
The current date is %s.
The user's Neovim version is %s.
The user is working on a %s machine. Respond with system specific commands if applicable.]],
              ctx.language,
              ctx.date,
              ctx.nvim_version,
              ctx.os
            )
          end,
        },
      },
    },
    rules = {
      opts = {
        chat = {
          enabled = true,
          autoload = "default",
        },
      },
    },
  },
}
