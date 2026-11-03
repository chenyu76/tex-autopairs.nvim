local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local text = require("tex-autopairs.text")
local M = {}
local namespace = api.nvim_create_namespace("tex-autopairs")
local states = {}

local function undo_sequence(buf)
	-- Avoid copying the undo tree on every edit of the current buffer.
	return buf == api.nvim_get_current_buf() and vim.fn.changenr() or vim.fn.undotree(buf).seq_cur
end

local function mark(state, position, mark_id)
	mark_id = api.nvim_buf_set_extmark(state.buf, namespace, position.row, position.col, {
		id = mark_id,
		end_row = position.end_row,
		end_col = position.end_col,
		right_gravity = true,
		end_right_gravity = false,
	})
	state.pairs[mark_id] = position.pair
end

local function positions(state)
	local result = {}
	local extmarks = api.nvim_buf_get_extmarks(state.buf, namespace, 0, -1, { details = true })
	for _, extmark in ipairs(extmarks) do
		local mark_id, row, col, details = extmark[1], extmark[2], extmark[3], extmark[4]
		---@cast details -nil
		result[mark_id] = {
			pair = state.pairs[mark_id],
			row = row,
			col = col,
			end_row = details.end_row,
			end_col = details.end_col,
		}
	end
	return result
end

local function tokens_intact(buf, position, line_count)
	local pair = position.pair
	local row, col = position.row, position.col
	local end_row, end_col = position.end_row, position.end_col
	-- Deleted ranges may leave extmarks at the position just past the final line.
	local separated = row < end_row or (row == end_row and col + #pair.open <= end_col - #pair.close)
	if end_row >= line_count or not separated then
		return false
	end
	local first = api.nvim_buf_get_lines(buf, row, row + 1, true)[1]
	local last = row == end_row and first or api.nvim_buf_get_lines(buf, end_row, end_row + 1, true)[1]
	return first:sub(col + 1, col + #pair.open) == pair.open
		and last:sub(end_col - #pair.close + 1, end_col) == pair.close
		and not text.escaped(first:sub(1, col))
end

local function checkpoint(state)
	local snapshot = positions(state)
	local line_count = api.nvim_buf_line_count(state.buf)
	-- Extmarks track positions; editing or escaping a token can end its ownership.
	for mark_id, position in pairs(snapshot) do
		if not tokens_intact(state.buf, position, line_count) then
			snapshot[mark_id], state.pairs[mark_id] = nil, nil
			api.nvim_buf_del_extmark(state.buf, namespace, mark_id)
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
			for mark_id, position in pairs(snapshot) do
				mark(state, position, mark_id)
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
		parents = {}, -- Predecessors remain reachable when old undo entries are pruned.
	}
end

function M.attach(buf)
	local state = new(buf)
	states[buf] = state
	local function on_update(event)
		if states[buf] ~= state then
			-- Returning true unregisters callbacks left over from an earlier attachment.
			return true
		end
		if event == "bytes" then
			local sequence = undo_sequence(buf)
			if not state.replay and sequence ~= state.sequence then
				-- Text is already new, but extmarks still describe the previous undo block.
				-- Save those positions without comparing them against a different buffer version.
				state.history[state.sequence] = positions(state)
				state.parents[sequence] = state.sequence
				state.sequence = sequence
			end
		elseif event == "reload" then
			api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
			state = new(buf)
			states[buf] = state
		elseif event == "changedtick" then
			-- Tick-only notifications can reveal undo/redo replay back to the same sequence.
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
	states[buf] = nil
	api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

function M.sync(buf)
	-- Lifecycle events and buffer-local mappings call this only while attached.
	local state = states[buf]
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
---@param reference integer|string Pair definition id, or the literal dollar token.
function M.track(reference)
	local cursor = api.nvim_win_get_cursor(0)
	local pair
	if type(reference) == "number" then
		pair = delimiters.pairs[reference]
	else
		pair = { open = reference, close = reference, replaceable = false }
	end
	-- Definition ids select pairs; extmark ids identify their individual occurrences.
	add(states[api.nvim_get_current_buf()], pair, cursor[1] - 1, cursor[2])
end

function M.finish(mark_id)
	local state = states[api.nvim_get_current_buf()]
	restore_undo_state(state)
	state.pairs[mark_id] = nil
	api.nvim_buf_del_extmark(state.buf, namespace, mark_id)
	checkpoint(state)
end

function M.at_closer(buf, row, col, typed_prefix_len, merged_len)
	-- The cursor includes this many already-inserted characters of the closing token.
	-- Merged characters already occupy the start of the generated closer.
	merged_len = merged_len or 0
	local state = states[buf]
	local target
	local extmarks = api.nvim_buf_get_extmarks(state.buf, namespace, { row, col }, { row, col }, {
		details = true,
		overlap = true,
	})
	for _, extmark in ipairs(extmarks) do
		local mark_id, start_row, start_col, details = extmark[1], extmark[2], extmark[3], extmark[4]
		---@cast details -nil
		local pair = state.pairs[mark_id]
		-- The closing prefix must lie inside the pair, without borrowing its opener.
		local inside = start_row < row or start_col + #pair.open <= col - typed_prefix_len
		if
			inside
			and details.end_row == row
			and details.end_col == col + #pair.close - merged_len
			and (not target or start_row > target.row or (start_row == target.row and start_col > target.col))
		then
			target = { mark_id = mark_id, pair = pair, row = start_row, col = start_col }
		end
	end
	return target
end

function M.prune(buf)
	local state = states[buf]
	local retained = { [state.sequence] = true }
	local function visit(entries)
		for _, entry in ipairs(entries) do
			retained[entry.seq] = true
			if state.parents[entry.seq] then
				-- Each change can be undone to its predecessor, even if earlier entries were pruned.
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
