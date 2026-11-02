local M = {}

function M.escaped(before)
	return #(before:match("\\+$") or "") % 2 == 1
end

function M.ends_with_unescaped(value, token)
	return vim.endswith(value, token) and not M.escaped(value:sub(1, #value - #token))
end

return M
