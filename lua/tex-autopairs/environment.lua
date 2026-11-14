local api = vim.api
local text = require("tex-autopairs.text")
local keys = require("tex-autopairs.keys")
local M = {}
local namespace = api.nvim_create_namespace("tex-autopairs-environment")
local sessions = {}
local left, right = keys.left, keys.right
local begin_prefix, end_prefix = "\\begin{", "\\end{"
local empty_end = end_prefix .. "}"

function M.cancel(buf)
	if sessions[buf] then
		sessions[buf] = nil
		api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
	end
end

function M.active(buf)
	return sessions[buf] ~= nil
end

local function range(buf, id)
	local mark = api.nvim_buf_get_extmark_by_id(buf, namespace, id, { details = true })
	local details = mark[3]
	---@cast details -nil
	return mark[1], mark[2], details.end_row, details.end_col
end

local function name_at(buf, id, prefix)
	local row, col, end_row, end_col = range(buf, id)
	local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if
		line
		and row == end_row
		and text.ends_with_unescaped(line:sub(1, col), prefix)
		and line:sub(end_col + 1, end_col + 1) == "}"
	then
		return { row = row, col = col, end_col = end_col, value = line:sub(col + 1, end_col) }
	end
end

local function inside(name, cursor)
	return cursor[1] - 1 == name.row and cursor[2] >= name.col and cursor[2] <= name.end_col
end

local function names(buf, session)
	local source = name_at(buf, session.source, begin_prefix)
	local target = name_at(buf, session.target, end_prefix)
	-- A changed target belongs to the user, even when its braces are still intact.
	if source and target and source.row == target.row and target.value == session.mirrored then
		return source, target
	end
end

function M.validate_cursor(buf)
	local session = sessions[buf]
	if session then
		local source, target = names(buf, session)
		if source and inside(source, api.nvim_win_get_cursor(0)) then
			return source, target
		end
		M.cancel(buf)
	end
end

function M.start()
	local buf = api.nvim_get_current_buf()
	local cursor = api.nvim_win_get_cursor(0)
	local row, col = cursor[1] - 1, cursor[2]
	local function mark(at)
		-- Both boundaries expand to include insertion into an initially empty name.
		return api.nvim_buf_set_extmark(buf, namespace, row, at, {
			end_row = row,
			end_col = at,
			right_gravity = false,
			end_right_gravity = true,
		})
	end
	sessions[buf] = { source = mark(col), target = mark(col + 1 + #end_prefix), mirrored = "" }
end

local function cursor_steps(value)
	return vim.fn.strchars(value, 1)
end

local function delete_keys(value)
	-- Unlike cursor movement, deletion can remove combining codepoints separately.
	return string.rep("<Del>", vim.fn.strchars(value, vim.o.delcombine and 0 or 1))
end

function M.prepare_input(key)
	local buf = api.nvim_get_current_buf()
	local source, target = M.validate_cursor(buf)
	if key ~= "<BS>" or not source or source.value ~= "" then
		return ""
	end
	-- These edits follow ordinary empty-brace deletion and remove only our generated end.
	local line = api.nvim_get_current_line()
	local gap = cursor_steps(line:sub(source.end_col + 2, target.col - #end_prefix))
	M.cancel(buf)
	return string.rep(right, gap) .. delete_keys(end_prefix .. target.value .. "}") .. string.rep(left, gap)
end

-- Return native edits so mirroring participates in the insertion's undo and redo keys.
---@param key? string
---@return string output
---@return boolean? empty_body Whether a completed begin directly precedes its generated end.
function M.after_input(key)
	local buf = api.nvim_get_current_buf()
	local session = sessions[buf]
	if not session and key ~= "{" then
		return ""
	end
	if vim.bo.filetype ~= "tex" or not vim.bo.modifiable then
		M.cancel(buf)
		return ""
	end
	local cursor = api.nvim_win_get_cursor(0)
	local line = api.nvim_get_current_line()
	if not session then
		-- The mapped opening brace has already inserted its ordinary closing brace.
		if text.ends_with_unescaped(line:sub(1, cursor[2]), begin_prefix) then
			return right
				.. empty_end
				.. string.rep(left, #empty_end + 1)
				.. keys.command('require("tex-autopairs.environment").start()')
		end
		return ""
	end
	-- Cursor movement would accept a popup selection; mirror it after completion ends.
	if vim.fn.pumvisible() == 1 then
		return ""
	end
	local source, target = names(buf, session)
	if not source then
		M.cancel(buf)
		return ""
	end
	local finished = key == "}"
	if not finished and not inside(source, cursor) then
		M.cancel(buf)
		return ""
	end
	local output = ""
	if source.value ~= target.value then
		local distance = cursor_steps(line:sub(cursor[2] + 1, target.col))
		output = string.rep(right, distance)
			.. delete_keys(target.value)
			.. source.value
			.. string.rep(left, distance + cursor_steps(source.value))
		session.mirrored = source.value
	end
	if finished then
		M.cancel(buf)
		return output, cursor[1] - 1 == target.row and cursor[2] == target.col - #end_prefix
	end
	return output
end

return M
