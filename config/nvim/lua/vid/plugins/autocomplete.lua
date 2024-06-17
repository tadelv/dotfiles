return {
	{
		"hrsh7th/nvim-cmp",
		version = false,
		event = "InsertEnter",
		dependencies = {
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-path",
			"hrsh7th/cmp-buffer",
			"L3MON4D3/LuaSnip",
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("cmp")
			local opts = {
				-- Where to get completion results from
				sources = cmp.config.sources({
					{ name = "nvim_lsp" },
					{ name = "buffer" },
					{ name = "path" },
				}),
				-- Make 'enter' key select the completion
				mapping = cmp.mapping.preset.insert({
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<S-tab>"] = cmp.mapping(function(original)
						if cmp.visual() then
							cmp.select_prev_item()
						elseif luasnip.expand_or_jumpable() then
							luasnip.jump(-1)
						else
							original()
						end
					end, { "i", "s" }),
				}),
				snippets = {
					expand = function(args)
						luasnip.lsp_expand(args)
					end,
				},
			}
			cmp.setup(opts)
		end,
	},
	{ "hrsh7th/cmp-nvim-lsp", lazy = true },
	{ "hrsh7th/cmp-path", lazy = true },
	{ "hrsh7th/cmp-buffer", lazy = true },
}
