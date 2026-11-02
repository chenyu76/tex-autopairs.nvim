local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local text = require("tex-autopairs.text")
local tracking = require("tex-autopairs.tracking")
local M = {}
-- Automatic cursor moves must stay in the same undo block as the insertion.
local left, right = "<C-G>U<Left>", "<C-G>U<Right>"

-- <Cmd> queues state updates after native edits and cursor movement have run.
local function track(reference)
	return '<Cmd>lua require("tex-autopairs.tracking").track(' .. vim.inspect(reference) .. ")<CR>"
end

local function finish(mark_id)
	return '<Cmd>lua require("tex-autopairs.tracking").finish(' .. mark_id .. ")<CR>"
end

local function append_closer(token, reference)
	return token .. string.rep(left, #token) .. track(reference)
end

local function completed(value, candidates, field)
	for _, spec in ipairs(candidates) do
		if text.ends_with_unescaped(value, spec[field]) then
			return spec
		end
	end
end

local function empty_pair(before, after, target, row, col)
	if target then
		if target.row == row and target.col + #target.pair.open == col then
			return target.pair
		end
		return
	end
	for _, pair in ipairs(delimiters.openers[before:sub(-1)] or {}) do
		if text.ends_with_unescaped(before, pair.open) and vim.startswith(after, pair.close) then
			return pair
		end
	end
	-- Dollars have only two widths; prefer the complete display pair.
	for width = 2, 1, -1 do
		local token = string.rep("$", width)
		if text.ends_with_unescaped(before, token) and vim.startswith(after, token) then
			return { open = token, close = token, replaceable = false }
		end
	end
end

local function skip(token)
	-- The final key is not inserted yet; erase its typed prefix, then cross the closer.
	return string.rep("<BS>", #token - 1) .. string.rep(right, #token)
end

local function close_pair(target)
	return skip(target.pair.close) .. finish(target.mark_id)
end

local function handle_dollar(buf, before, after, row, col)
	if text.escaped(before) then
		return "$"
	end
	local target = tracking.at_closer(buf, row, col, 0)
	if target and (target.pair.open == "$" or target.pair.open == "$$") then
		local pair = target.pair
		if pair.open == "$" and target.row == row and target.col + #pair.open == col then
			return close_pair(target) .. append_closer("$$", "$$")
		end
		-- A closing token cannot borrow dollars from its opener.
		local body = target.row == row and before:sub(target.col + #pair.open + 1) or before
		if text.ends_with_unescaped(body .. "$", pair.close) then
			return close_pair(target)
		end
		return "$"
	end
	if vim.startswith(after, "$") then
		return right
	end
	return "$" .. append_closer("$", "$")
end

-- Called by the current buffer's Insert-mode mapping.
function M.handle(key)
	-- Let native input report E21 if the buffer becomes nonmodifiable during insertion.
	if not vim.bo.modifiable then
		return key
	end
	local buf = api.nvim_get_current_buf()
	tracking.sync(buf)
	local cursor = api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local line = api.nvim_get_current_line()
	local before, after = line:sub(1, col), line:sub(col + 1)
	if key == "<BS>" then
		local target = tracking.at_closer(buf, row, col, 0)
		local pair = empty_pair(before, after, target, row, col)
		if pair then
			return string.rep("<BS>", #pair.open) .. string.rep("<Del>", #pair.close)
		end
		return key
	elseif key == "$" then
		return handle_dollar(buf, before, after, row, col)
	end

	local candidate = before .. key
	local open = completed(candidate, delimiters.openers[key], "open")
	local close = completed(candidate, delimiters.closers[key], "close")
	-- Decide the longest token before choosing an opening or closing action.
	if open and (not close or #open.open > #close.close) then
		return key .. append_closer(open.close, open.id)
	end
	if not close then
		return key
	end
	local target = tracking.at_closer(buf, row, col, #close.close - 1)
	if target and target.pair.close == close.close then
		return close_pair(target)
	end
	local matching_after = vim.startswith(after, close.close)
	if open and open.open == close.close then
		-- Symmetric tokens close their own pair or start a nested pair.
		if matching_after then
			return skip(close.close)
		end
		return key .. append_closer(open.close, open.id)
	end
	if target and target.pair.replaceable and close.replaceable then
		return string.rep("<Del>", #target.pair.close) .. key .. finish(target.mark_id)
	end
	if matching_after then
		return skip(close.close)
	end
	return key
end

return M
