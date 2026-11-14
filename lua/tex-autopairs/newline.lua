local api = vim.api
local keys = require("tex-autopairs.keys")
local M = {}
local pending = {}

function M.load(config)
	M.start_command = config.newline and keys.command('require("tex-autopairs.newline").start()') or ""
	pending = {}
end

function M.cancel(buf)
	pending[buf] = nil
end

-- Only freshly generated pairs qualify; returning to an old pair cannot restart it.
function M.start()
	local buf = api.nvim_get_current_buf()
	local cursor = api.nvim_win_get_cursor(0)
	-- No intervening edits are allowed, so positions need no extmarks.
	pending[buf] = { row = cursor[1], col = cursor[2], tick = api.nvim_buf_get_changedtick(buf) }
end

function M.validate(buf)
	local candidate = pending[buf]
	if candidate then
		local cursor = api.nvim_win_get_cursor(0)
		if
			cursor[1] ~= candidate.row
			or cursor[2] ~= candidate.col
			or api.nvim_buf_get_changedtick(buf) ~= candidate.tick
		then
			M.cancel(buf)
		end
	end
end

function M.on_enter(buf)
	M.validate(buf)
	local candidate = pending[buf]
	M.cancel(buf)
	if candidate and vim.bo[buf].modifiable then
		-- After the user's CR, push the closer down again and return to the blank line.
		return "<CR><Up>"
	end
end

return M
