local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local tracking = require("tex-autopairs.tracking")
local M = {}
local left, right = "<C-G>U<Left>", "<C-G>U<Right>"

local function command(action, argument)
	return '<Cmd>lua require("tex-autopairs")._' .. action .. "(" .. argument .. ")<CR>"
end

local function insert_pair(pair, typed)
	return typed .. pair.close .. string.rep(left, #pair.close) .. command("track", pair.id)
end

local function ends_with_unescaped(text, token)
	return text:sub(-#token) == token and not delimiters.escaped(text:sub(1, #text - #token))
end

local function completed(text, candidates, field)
	for _, spec in ipairs(candidates or {}) do
		if ends_with_unescaped(text, spec[field]) then
			return spec
		end
	end
end

local function empty_pair(before, after, target, row, col)
	if target then
		if target.row == row and target.col + #target.pair.open == col then
			return target.pair.open, target.pair.close
		end
		return
	end
	for _, pair in ipairs(delimiters.openers[before:sub(-1)] or {}) do
		if ends_with_unescaped(before, pair.open) and after:sub(1, #pair.close) == pair.close then
			return pair.open, pair.close
		end
	end
	for width = 2, 1, -1 do
		local token = string.rep("$", width)
		if ends_with_unescaped(before, token) and after:sub(1, width) == token then
			return token, token
		end
	end
end

local function skip(token)
	return string.rep("<BS>", #token - 1) .. string.rep(right, #token)
end

local function handle_dollar(state, before, after, row, col)
	if delimiters.escaped(before) then
		return "$"
	end
	local target = tracking.at_closer(state, row, col, 0)
	if target and target.pair.open == "$" then
		local finish = right .. command("finish", target.id)
		if target.row == row and target.col + 1 == col then
			-- Consume the first generated closer, then append the display closer.
			return finish .. "$$" .. left .. left .. command("dollar", 2)
		end
		return finish
	elseif target and target.pair.open == "$$" then
		local body = target.row == row and before:sub(target.col + 3) or before
		if ends_with_unescaped(body .. "$", "$$") then
			return skip("$$") .. command("finish", target.id)
		end
		return "$"
	end
	return after:sub(1, 1) == "$" and right or "$$" .. left .. command("dollar", 1)
end

function M.handle(state, key)
	if not vim.bo.modifiable then
		return key
	end
	tracking.sync(state)
	local cursor = api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local line = api.nvim_get_current_line()
	local before, after = line:sub(1, col), line:sub(col + 1)
	if key == "<BS>" then
		local target = tracking.at_closer(state, row, col, 0)
		local open, close = empty_pair(before, after, target, row, col)
		return open and string.rep("<BS>", #open) .. string.rep("<Del>", #close) or key
	elseif key == "$" then
		return handle_dollar(state, before, after, row, col)
	end

	local text = before .. key
	local close = completed(text, delimiters.closers[key], "close")
	local open = completed(text, delimiters.openers[key], "open")
	-- A longer opener must win over a closing suffix such as \| in \left\|.
	if open and close and #open.open > #close.close then
		close = nil
	end
	if close then
		local target = tracking.at_closer(state, row, col, #close.close - 1)
		-- A complete opener starts a nested pair unless it closes the current one.
		local opening = open and open.open == close.close
		local replace = target and target.pair.replaceable and close.replaceable and not opening
		if target and (target.pair.close == close.close or replace) then
			local result = target.pair.close == close.close and skip(close.close)
				or string.rep("<Del>", #target.pair.close) .. key
			return result .. command("finish", target.id)
		elseif after:sub(1, #close.close) == close.close then
			return skip(close.close)
		elseif not opening then
			return key
		end
	end
	return open and insert_pair(open, key) or key
end

return M
