local M = {}

local function file_exist(file_path)
	local f = io.open(file_path, "r")
	return f ~= nil and io.close(f)
end

function M.store()
	local breakpoints = require("dap.breakpoints")
	local settings = vim.fn.getcwd() .. "/.nvim"
	local breakpoints_fp = settings .. "/breakpoints.json"
	vim.fn.systemlist({ "mkdir", "-p", settings })

	local bps = {}

	if file_exist(breakpoints_fp) then
		local breakpoints_handle = io.open(breakpoints_fp)

		if breakpoints_handle then
			local load_bps_raw = breakpoints_handle:read("*a")
			breakpoints_handle:close()

			if string.len(load_bps_raw) > 0 then
				bps = vim.fn.json_decode(load_bps_raw)
			end
		end
	end

	local breakpoints_by_buf = breakpoints.get()
	for _, bufrn in ipairs(vim.api.nvim_list_bufs()) do
		bps[vim.api.nvim_buf_get_name(bufrn)] = breakpoints_by_buf[bufrn]
	end

	local fp = io.open(breakpoints_fp, "w")
	if fp then
		fp:write(vim.fn.json_encode(bps))
		fp:close()
	end
end

function M.load()
	local breakpoints = require("dap.breakpoints")
	local settings = vim.fn.getcwd() .. "/.nvim"

	local fp = io.open(settings .. "/breakpoints.json", "r")
	if not fp then
		return
	end

	local content = fp:read("*a")
	fp:close()

	if string.len(content) == 0 then
		return
	end

	local bps = vim.fn.json_decode(content)

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local file_name = vim.api.nvim_buf_get_name(buf)

		if bps[file_name] then
			for _, bp in pairs(bps[file_name]) do
				local opts = {
					condition = bp.condition,
					log_message = bp.logMessage,
					hit_condition = bp.hitCondition,
				}
				breakpoints.set(opts, tonumber(buf), bp.line)
			end
		end
	end
end

function M.setupListeners()
	local dap = require("dap")
	local areSet = false

	dap.listeners.after["event_initialized"]["me"] = function()
		if not areSet then
			areSet = true
			vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "Continue", noremap = true })
			vim.keymap.set("n", "<leader>dC", dap.run_to_cursor, { desc = "Run To Cursor" })
			vim.keymap.set("n", "<leader>ds", dap.step_over, { desc = "Step Over" })
			vim.keymap.set("n", "<leader>di", dap.step_into, { desc = "Step Into" })
			vim.keymap.set("n", "<leader>do", dap.step_out, { desc = "Step Out" })
			vim.keymap.set({ "n", "v" }, "<Leader>dh", require("dap.ui.widgets").hover, { desc = "Hover" })
			vim.keymap.set({ "n", "v" }, "<Leader>de", require("dapui").eval, { desc = "Eval" })
		end
	end

	dap.listeners.after["event_terminated"]["me"] = function()
		if areSet then
			areSet = false
			vim.keymap.del("n", "<leader>dc")
			vim.keymap.del("n", "<leader>dC")
			vim.keymap.del("n", "<leader>ds")
			vim.keymap.del("n", "<leader>di")
			vim.keymap.del("n", "<leader>do")
			vim.keymap.del({ "n", "v" }, "<Leader>dh")
			vim.keymap.del({ "n", "v" }, "<Leader>de")
		end
	end
end

return {
	"mfussenegger/nvim-dap",
	dependencies = { "wojciech-kulik/xcodebuild.nvim" },
	config = function()
		local dap = require("dap")
		local xcodebuild = require("xcodebuild.dap")
		local autogroup = vim.api.nvim_create_augroup("dap-breakpoints", { clear = true })

		dap.configurations.swift = {
			{
				name = "iOS App Debugger",
				type = "codelldb",
				request = "attach",
				program = xcodebuild.get_program_path,
				cwd = "${workspaceFolder}",
				stopOnEntry = false,
				waitFor = true,
			},
		}

		-- TODO: make sure that paths match your environment!!
		dap.adapters.codelldb = {
			type = "server",
			port = "13000",
			executable = {
				command = os.getenv("HOME") .. "/.local/opt/codelldb/extension/adapter/codelldb",
				args = {
					"--port",
					"13000",
					--"--liblldb",
					--"/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/LLDB",
				},
			},
		}

		-- Suppress annoying message from codelldb
		local orig_notify = require("dap.utils").notify
		require("dap.utils").notify = function(msg, log_level)
			if not string.find(msg, "Either the adapter is slow") then
				orig_notify(msg, log_level)
			end
		end

		-- Load Breakpoints
		vim.api.nvim_create_autocmd({ "VimEnter" }, {
			group = autogroup,
			pattern = "*",
			once = true,
			callback = function()
				vim.defer_fn(M.load, 500)
			end,
		})

		-- Improve icons
		local define = vim.fn.sign_define
		define("DapBreakpoint", { text = "", texthl = "DiagnosticError", linehl = "", numhl = "" })
		define("DapBreakpointRejected", { text = "", texthl = "DiagnosticError", linehl = "", numhl = "" })
		define("DapStopped", { text = "", texthl = "DiagnosticOk", linehl = "", numhl = "" })
		define("DapLogPoint", { text = "", texthl = "DiagnosticInfo", linehl = "", numhl = "" })
		define("DapLogPoint", { text = "", texthl = "DiagnosticInfo", linehl = "", numhl = "" })

		M.setupListeners()

		vim.keymap.set("n", "<leader>dd", xcodebuild.build_and_debug, { desc = "Build & Debug" })
		vim.keymap.set("n", "<leader>dr", xcodebuild.debug_without_build, { desc = "Debug Without Building" })
		vim.keymap.set("n", "<leader>dt", xcodebuild.debug_tests, { desc = "Debug Tests" })
		vim.keymap.set("n", "<leader>dT", xcodebuild.debug_class_tests, { desc = "Debug Class Tests" })
		vim.keymap.set("n", "<leader>b", function()
			dap.toggle_breakpoint()
			M.store()
		end, { desc = "Toggle Breakpoint" })
		vim.keymap.set("n", "<leader>B", function()
			dap.set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
			M.store()
		end, { desc = "Toggle Log Breakpoint" })
		vim.keymap.set("n", "<Leader>dx", function()
			if dap.session() then
				dap.terminate()
			end
			require("xcodebuild.actions").cancel()
			require("dapui").close()
			dap.listeners.after["event_terminated"]["me"]()
		end, { desc = "Terminate" })
	end,
}
