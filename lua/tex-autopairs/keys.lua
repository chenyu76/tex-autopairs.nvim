local M = {
	-- Automatic cursor moves must stay in the insertion's undo block.
	left = "<C-G>U<Left>",
	right = "<C-G>U<Right>",
}

-- Queue Lua state changes after the preceding native edits have committed.
function M.command(expression)
	return "<Cmd>lua " .. expression .. "<CR>"
end

return M
