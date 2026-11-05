local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local text = require("tex-autopairs.text")
local tracking = require("tex-autopairs.tracking")
local environment = require("tex-autopairs.environment")
local keys = require("tex-autopairs.keys")
local M = {}
local sessions = {}
local emitting = false
local left, right = keys.left, keys.right

function M.end_feed()
	emitting = false
end

function M.sync_environment(key)
	local output = environment.after_input(key)
	if output ~= "" then
		M.feed(output)
	end
end

function M.feed(output)
	-- Generated cursor commands contain unmapped bytes, such as U in <C-G>U.
	emitting = true
	output = output .. keys.command('require("tex-autopairs.input").end_feed()')
	api.nvim_feedkeys(api.nvim_replace_termcodes(output, true, false, true), "in", false)
end

function M.cancel_closing(buf)
	sessions[buf] = nil
end

local function closing_at(buf, row, col)
	local session = sessions[buf]
	if not session then
		return
	end
	if row == session.row and col == session.col then
		local target = tracking.at_closer(buf, row, col, 0, session.merged)
		if target and target.mark_id == session.mark_id then
			return session, target
		end
	end
	M.cancel_closing(buf)
end

function M.validate_cursor(buf)
	if emitting then
		return
	end
	environment.validate_cursor(buf)
	if sessions[buf] then
		tracking.sync(buf)
		local cursor = api.nvim_win_get_cursor(0)
		closing_at(buf, cursor[1] - 1, cursor[2])
	end
end

-- Native edits have committed before this queued command records the next position.
function M.resume_closing(merged, start_col)
	local buf = api.nvim_get_current_buf()
	local cursor = api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local target = tracking.at_closer(buf, row, col, 0, merged)
	if target then
		-- Keep the owner's id; row/col describe the expected cursor, not the pair's range.
		sessions[buf] = { mark_id = target.mark_id, merged = merged, start_col = start_col, row = row, col = col }
	else
		M.cancel_closing(buf)
	end
end

local function resume_closing(merged, start_col)
	return keys.command('require("tex-autopairs.input").resume_closing(' .. merged .. "," .. start_col .. ")")
end

local function restore_closer(target, merged)
	if merged > 0 then
		local token = target.pair.close
		-- Insert before deleting the old suffix so the pair's end mark follows the text.
		return token .. string.rep("<Del>", #token - merged) .. string.rep(left, #token)
	end
	return ""
end

local function matched_prefix_len(value, token)
	for width = math.min(#value, #token - 1), 1, -1 do
		if text.ends_with_unescaped(value, token:sub(1, width)) then
			return width
		end
	end
	return 0
end

function M.reconcile_closing(start_col)
	local buf = api.nvim_get_current_buf()
	local cursor = api.nvim_win_get_cursor(0)
	local target = tracking.at_closer(buf, cursor[1] - 1, cursor[2], 0)
	if target then
		-- Native deletion decides how many bytes tab stops and combining characters remove.
		local typed = api.nvim_get_current_line():sub(start_col + 1, cursor[2])
		local merged = matched_prefix_len(typed, target.pair.close)
		M.feed(string.rep("<Del>", merged) .. resume_closing(merged, start_col))
	else
		M.cancel_closing(buf)
	end
end

local function edit_prefix(session, target, key, before)
	local start_col = session and session.start_col or #before
	local typed = before:sub(start_col + 1)
	local previous = session and session.merged or 0
	if key == "<BS>" then
		if previous > 0 then
			-- A merged prefix ends in an ASCII token character; restore its preceding suffix.
			local merged = matched_prefix_len(typed:sub(1, -2), target.pair.close)
			if merged == previous - 1 then
				return left .. resume_closing(merged, start_col)
			end
		end
		return restore_closer(target, previous)
			.. key
			.. keys.command('require("tex-autopairs.input").reconcile_closing(' .. start_col .. ")")
	end
	local merged = matched_prefix_len(typed .. key, target.pair.close)
	local output
	if merged == previous + #key then
		output = string.rep(right, #key)
	else
		output = restore_closer(target, previous) .. key .. string.rep("<Del>", merged)
	end
	return output .. resume_closing(merged, start_col)
end

local leave_keys = {}
for _, key in ipairs({
	"<Esc>",
	"<C-C>",
	"<C-O>",
	"<Left>",
	"<Right>",
	"<Up>",
	"<Down>",
	"<Home>",
	"<End>",
	"<PageUp>",
	"<PageDown>",
	"<S-Left>",
	"<S-Right>",
	"<C-Left>",
	"<C-Right>",
	"<C-Home>",
	"<C-End>",
	"<Del>",
}) do
	leave_keys[api.nvim_replace_termcodes(key, true, false, true)] = true
end

function M.observe(key)
	-- on_key also sees plugins' :normal! commands in temporary windows.
	if emitting or api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
		return
	end
	local buf = api.nvim_get_current_buf()
	local session = sessions[buf]
	local syncing_environment = environment.active(buf)
	if not session and not syncing_environment then
		return
	end
	local byte = key:byte(1)
	local mapped = delimiters.is_mapped(key)
	if syncing_environment then
		-- Observe navigation keys, but not Lua callbacks or <Cmd> command encodings.
		if not mapped and byte and (byte ~= 0x80 or leave_keys[key]) then
			M.feed(keys.command('require("tex-autopairs.input").sync_environment()'))
		end
	end
	if not session then
		return
	end
	if vim.bo.filetype ~= "tex" or not vim.bo.modifiable or leave_keys[key] then
		M.cancel_closing(buf)
		return
	end
	-- Mapped characters are handled before their native output is emitted.
	-- K_SPECIAL (0x80) prefixes encoded keys, including Lua mapping callbacks.
	local newline = key == "\r" or key == "\n"
	local tab = key == "\t"
	if mapped or not byte or (byte < 32 and not newline and not tab) or byte == 127 or byte == 0x80 then
		return
	end
	tracking.sync(buf)
	local cursor = api.nvim_win_get_cursor(0)
	local target
	session, target = closing_at(buf, cursor[1] - 1, cursor[2])
	if not session then
		return
	end
	if newline then
		-- A new line ends this session; repair after native indentation or line insertion.
		M.cancel_closing(buf)
		if session.merged > 0 then
			M.feed(restore_closer(target, session.merged))
		end
	elseif session.merged > 0 or tab then
		-- The current key inserts first; native repair keys also become part of dot repeat.
		M.feed(restore_closer(target, session.merged) .. resume_closing(0, session.start_col))
	else
		session.col = session.col + #key
	end
end

local function track(reference)
	return keys.command('require("tex-autopairs.tracking").track(' .. vim.inspect(reference) .. ")")
end

local function finish(mark_id)
	return keys.command('require("tex-autopairs.tracking").finish(' .. mark_id .. ")")
end

local function append_closer(pair)
	return pair.close .. string.rep(left, #pair.close) .. track(pair.id)
end

local function completed(value, candidates, field)
	for _, spec in ipairs(candidates or {}) do
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
			return delimiters.dollar(token)
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
			return close_pair(target) .. append_closer(delimiters.dollar("$$"))
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
	local pair = delimiters.dollar("$")
	return pair.open .. append_closer(pair)
end

-- Decide the native edits for the mapped key.
local function handle(key)
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
	local session, target = closing_at(buf, row, col)
	local merged = session and session.merged or 0
	-- Only prefix-edit results resume the session after their native keys finish.
	M.cancel_closing(buf)
	if key == "<BS>" then
		if session and col > session.start_col then
			return edit_prefix(session, target, key, before)
		end
		target = tracking.at_closer(buf, row, col, 0)
		local pair = empty_pair(before, after, target, row, col)
		if pair then
			return string.rep("<BS>", #pair.open) .. string.rep("<Del>", #pair.close)
		end
		return key
	elseif key == "$" then
		return restore_closer(target, merged) .. handle_dollar(buf, before, after, row, col)
	end

	local candidate = before .. key
	local open = completed(candidate, delimiters.openers[key], "open")
	local close = completed(candidate, delimiters.closers[key], "close")
	-- Decide the longest token before choosing an opening or closing action.
	if open and (not close or #open.open > #close.close) then
		return restore_closer(target, merged) .. key .. append_closer(open)
	end
	if not target then
		target = tracking.at_closer(buf, row, col, close and #close.close - 1 or 0)
	end
	if close and target and target.pair.close == close.close then
		if session then
			return string.rep(right, #target.pair.close - merged) .. finish(target.mark_id)
		end
		return close_pair(target)
	end
	local matching_after = close and vim.startswith(after, close.close)
	if open and close and open.open == close.close then
		-- Symmetric tokens close their own pair or start a nested pair.
		if matching_after then
			return skip(close.close)
		end
		return restore_closer(target, merged) .. key .. append_closer(open)
	end
	if close and target and delimiters.can_replace(target.pair, close) then
		return string.rep("<Del>", #target.pair.close - merged) .. key .. finish(target.mark_id)
	end
	if matching_after then
		return skip(close.close)
	end
	if
		session
		or (target and #target.pair.close > 1 and target.pair.close:sub(1, 1) == key and not text.escaped(before))
	then
		return edit_prefix(session, target, key, before)
	end
	return key
end

function M.insert(key)
	local buf = api.nvim_get_current_buf()
	local trailing = environment.prepare_input(key)
	local output = handle(key) .. trailing
	if key == "{" or environment.active(buf) then
		local argument = vim.inspect(key:match("^[{}]$"))
		output = output .. keys.command('require("tex-autopairs.input").sync_environment(' .. argument .. ")")
	end
	M.feed(output)
end

return M
