local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local M = {}
local namespace = api.nvim_create_namespace("tex-autopairs")
local buffers = {}

local function undo_sequence(buf)
	-- Avoid copying the undo tree on every edit of the current buffer.
	return buf == api.nvim_get_current_buf() and vim.fn.changenr() or vim.fn.undotree(buf).seq_cur
end

local function mark(state, position, id)
	id = api.nvim_buf_set_extmark(state.buf, namespace, position.row, position.col, {
		id = id,
		end_row = position.end_row,
		end_col = position.end_col,
		right_gravity = true,
		end_right_gravity = false,
	})
	state.pairs[id] = position.pair
end

local function positions(state)
	local result = {}
	local extmarks = api.nvim_buf_get_extmarks(state.buf, namespace, 0, -1, { details = true })
	for _, extmark in ipairs(extmarks) do
		local id, row, col, details = extmark[1], extmark[2], extmark[3], extmark[4]
		---@cast details -nil
		result[id] = {
			pair = state.pairs[id],
			row = row,
			col = col,
			end_row = details.end_row,
			end_col = details.end_col,
		}
	end
	return result
end

local function checkpoint(state)
	local snapshot = positions(state)
	for id, position in pairs(snapshot) do
		local pair = position.pair
		local row, col = position.row, position.col
		local end_row, end_col = position.end_row, position.end_col
		local first = api.nvim_buf_get_lines(state.buf, row, row + 1, true)[1]
		local last = row == end_row and first or api.nvim_buf_get_lines(state.buf, end_row, end_row + 1, true)[1]
		local intact = (row < end_row or col + #pair.open <= end_col - #pair.close)
			and first:sub(col + 1, col + #pair.open) == pair.open
			and last:sub(end_col - #pair.close + 1, end_col) == pair.close
			and not delimiters.escaped(first:sub(1, col))
		if not intact then
			snapshot[id], state.pairs[id] = nil, nil
			api.nvim_buf_del_extmark(state.buf, namespace, id)
		end
	end
	state.history[state.sequence] = snapshot
	state.tick = api.nvim_buf_get_changedtick(state.buf)
end

local function restore_undo_state(state)
	local sequence = undo_sequence(state.buf)
	if state.replay or sequence ~= state.sequence then
		local snapshot = state.history[sequence]
		if snapshot then
			-- Extmarks do not replay their birth when an earlier insertion is redone.
			api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
			state.pairs = {}
			for id, position in pairs(snapshot) do
				mark(state, position, id)
			end
		end
		state.sequence = sequence
	end
	state.replay = nil
end

local function new(buf)
	local sequence = undo_sequence(buf)
	return {
		buf = buf,
		sequence = sequence,
		tick = api.nvim_buf_get_changedtick(buf),
		pairs = {},
		history = { [sequence] = {} },
		parents = {},
	}
end

function M.attach(buf)
	local state = new(buf)
	buffers[buf] = state
	local function on_update(event)
		if buffers[buf] ~= state then
			return true
		end
		if event == "bytes" then
			local sequence = undo_sequence(buf)
			if not state.replay and sequence ~= state.sequence then
				-- on_bytes runs before extmarks move: these positions close the previous undo block.
				state.history[state.sequence] = positions(state)
				state.parents[sequence] = state.sequence
				state.sequence = sequence
			end
		elseif event == "reload" then
			api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
			state = new(buf)
			buffers[buf] = state
		elseif event == "changedtick" then
			state.replay = true
		end
	end
	api.nvim_buf_attach(buf, false, {
		on_bytes = on_update,
		on_reload = on_update,
		on_changedtick = on_update,
	})
end

function M.detach(buf)
	buffers[buf] = nil
	api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

function M.sync(buf)
	local state = buffers[buf]
	if
		not state.replay
		and undo_sequence(state.buf) == state.sequence
		and state.tick == api.nvim_buf_get_changedtick(state.buf)
	then
		return
	end
	restore_undo_state(state)
	checkpoint(state)
end

local function add(state, pair, row, col)
	restore_undo_state(state)
	mark(state, {
		pair = pair,
		row = row,
		col = col - #pair.open,
		end_row = row,
		end_col = col + #pair.close,
	})
	checkpoint(state)
end

-- These commands run after native Insert-mode edits have committed.
function M.track(id)
	local cursor = api.nvim_win_get_cursor(0)
	add(buffers[api.nvim_get_current_buf()], delimiters.pairs[id], cursor[1] - 1, cursor[2])
end

function M.dollar(width)
	local cursor = api.nvim_win_get_cursor(0)
	local token = string.rep("$", width)
	add(buffers[api.nvim_get_current_buf()], { open = token, close = token }, cursor[1] - 1, cursor[2])
end

function M.finish(id)
	local state = buffers[api.nvim_get_current_buf()]
	restore_undo_state(state)
	state.pairs[id] = nil
	api.nvim_buf_del_extmark(state.buf, namespace, id)
	checkpoint(state)
end

function M.at_closer(buf, row, col, prefix_length)
	local state = buffers[buf]
	local target
	local extmarks = api.nvim_buf_get_extmarks(state.buf, namespace, { row, col }, { row, col }, {
		details = true,
		overlap = true,
	})
	for _, extmark in ipairs(extmarks) do
		local id, start_row, start_col, details = extmark[1], extmark[2], extmark[3], extmark[4]
		---@cast details -nil
		local pair = state.pairs[id]
		local inside = start_row < row or start_col + #pair.open <= col - prefix_length
		if
			inside
			and details.end_row == row
			and details.end_col == col + #pair.close
			and (not target or start_row > target.row or (start_row == target.row and start_col > target.col))
		then
			target = { id = id, pair = pair, row = start_row, col = start_col }
		end
	end
	return target
end

function M.prune(buf)
	local state = buffers[buf]
	local retained = { [state.sequence] = true }
	local function visit(entries)
		for _, entry in ipairs(entries) do
			retained[entry.seq] = true
			if state.parents[entry.seq] then
				-- The oldest reachable state precedes the first entry in the undo tree.
				retained[state.parents[entry.seq]] = true
			end
			if entry.alt then
				visit(entry.alt)
			end
		end
	end
	visit(vim.fn.undotree(state.buf).entries)
	for sequence in pairs(state.history) do
		if not retained[sequence] then
			state.history[sequence], state.parents[sequence] = nil, nil
		end
	end
end

return M
