return {
	"folke/trouble.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons", "folke/todo-comments.nvim" },
  cmd = "Trouble",
  opts = {},
	keys = {
		{ "<leader>Tx", "<cmd>Trouble<CR>", desc = "Open/close trouble list" },
		{ "<leader>Tw", "<cmd>Trouble workspace_diagnostics<CR>", desc = "Open trouble workspace diagnostics" },
		{ "<leader>Td", "<cmd>Trouble diagnostics toggle<CR>", desc = "Toggle Trouble diagnostics" },
		{ "<leader>Tq", "<cmd>Trouble quickfix<CR>", desc = "Open trouble quickfix list" },
		{ "<leader>Tl", "<cmd>Trouble loclist<CR>", desc = "Open trouble location list" },
		{ "<leader>Tt", "<cmd>TodoTrouble<CR>", desc = "Open todos in trouble" },
	},
}
