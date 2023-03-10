local M = {}

M.response_sock = nil

local function unblock_client(pipe, othercmds)
	M.response_sock = vim.fn.sockconnect("pipe", pipe, { rpc = true })
	vim.fn.rpcnotify(M.response_sock, "nvim_exec_lua", "vim.cmd('qa!')", {})
	vim.fn.chanclose(M.response_sock)
	M.response_sock = nil

	for _, cmd in ipairs(othercmds) do
		vim.api.nvim_del_autocmd(cmd)
	end
end

local function notify_when_done(pipe, bufnr, callback, ft)
	local quitpre
	local bufunload
	local bufdelete

	quitpre = vim.api.nvim_create_autocmd("QuitPre", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_client(pipe, { bufunload, bufdelete })
			callback(ft)
		end
	})
	bufunload = vim.api.nvim_create_autocmd("BufUnload", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_client(pipe, { quitpre, bufdelete })
			callback(ft)
		end
	})
	bufdelete = vim.api.nvim_create_autocmd("BufDelete", {
		buffer = bufnr,
		once = true,
		callback = function()
			unblock_client(pipe, { quitpre, bufunload })
			callback(ft)
		end
	})
end

M.edit_files = function(args, response_pipe)
	local config = require("flatten").config
	local callbacks = config.callbacks

	callbacks.pre_open()
	if #args > 0 then
		local argstr = ""
		for _, arg in pairs(args) do
			local p = vim.loop.fs_realpath(arg) or arg
			if argstr == "" or argstr == nil then
				argstr = p
			else
				argstr = argstr .. " " .. p
			end
		end
		vim.cmd("0argadd " .. argstr)

		vim.cmd("tab argument 1")

		vim.cmd("edit")
	else
		vim.cmd("tabnew")
	end
	local ft = vim.bo.filetype

	local winnr = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_get_current_buf()
	callbacks.post_open(bufnr, winnr, ft)

	local block = config.block_for[ft] == true
	if block then
		notify_when_done(response_pipe, bufnr, callbacks.block_end, ft)
	end
	return block
end

return M
