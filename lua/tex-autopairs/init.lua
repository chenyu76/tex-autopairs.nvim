local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local input = require("tex-autopairs.input")
local tracking = require("tex-autopairs.tracking")
local M = {}
local buffers = {}

-- These commands run after native Insert-mode edits have committed.
function M._track(id)
	local cursor = api.nvim_win_get_cursor(0)
	tracking.add(buffers[api.nvim_get_current_buf()].tracking, delimiters.pairs[id], cursor[1] - 1, cursor[2])
end

function M._dollar(width)
	local cursor = api.nvim_win_get_cursor(0)
	local token = string.rep("$", width)
	tracking.add(
		buffers[api.nvim_get_current_buf()].tracking,
		{ open = token, close = token },
		cursor[1] - 1,
		cursor[2]
	)
end

function M._finish(id)
	tracking.finish(buffers[api.nvim_get_current_buf()].tracking, id)
end

function M.detach(buf)
	buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
	local state = buffers[buf]
	if not state then
		return
	end
	buffers[buf] = nil
	api.nvim_buf_call(buf, function()
		for lhs, mapping in pairs(state.mappings) do
			local current = vim.fn.maparg(lhs, "i", false, true)
			if current.buffer == 1 and current.callback == mapping.callback then
				vim.keymap.del("i", lhs, { buffer = buf })
				if mapping.previous then
					vim.fn.mapset("i", false, mapping.previous)
				end
			end
		end
	end)
	tracking.clear_marks(state.tracking)
end

function M.attach(buf)
	buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
	if not api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "tex" or buffers[buf] then
		return
	end
	local state = {
		mappings = {},
		tracking = tracking.new(buf),
	}
	buffers[buf] = state
	api.nvim_buf_call(buf, function()
		for _, lhs in ipairs(delimiters.keys) do
			local previous = vim.fn.maparg(lhs, "i", false, true)
			local callback = function()
				local result = vim.bo.filetype == "tex" and input.handle(state.tracking, lhs) or lhs
				-- Expr mappings can run before preceding literal input is committed.
				api.nvim_feedkeys(api.nvim_replace_termcodes(result, true, false, true), "in", false)
			end
			state.mappings[lhs] = {
				callback = callback,
				previous = previous.buffer == 1 and previous or nil,
			}
			vim.keymap.set("i", lhs, callback, {
				buffer = buf,
				silent = true,
				desc = "tex-autopairs: " .. lhs,
			})
		end
	end)
	local function on_update(event)
		if buffers[buf] ~= state then
			return true
		end
		if event == "bytes" then
			tracking.on_bytes(state.tracking)
		elseif event == "reload" then
			tracking.clear_marks(state.tracking)
			state.tracking = tracking.new(buf)
		elseif event == "changedtick" then
			state.tracking.replay = true
		end
	end
	api.nvim_buf_attach(buf, false, {
		on_bytes = on_update,
		on_reload = on_update,
		on_changedtick = on_update,
	})
end

function M.setup()
	for _, buf in ipairs(vim.tbl_keys(buffers)) do
		M.detach(buf)
	end
	local group = api.nvim_create_augroup("tex-autopairs", { clear = true })
	api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = group,
		callback = function(event)
			if vim.bo[event.buf].filetype == "tex" then
				M.attach(event.buf)
			else
				M.detach(event.buf)
			end
		end,
	})
	api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(event)
			M.detach(event.buf)
		end,
	})
	api.nvim_create_autocmd({ "InsertEnter", "InsertLeavePre", "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(event)
			local state = buffers[event.buf]
			if state then
				tracking.sync(state.tracking)
				if event.event == "InsertLeavePre" then
					tracking.prune(state.tracking)
				end
			end
		end,
	})
	for _, buf in ipairs(api.nvim_list_bufs()) do
		M.attach(buf)
	end
end

return M
