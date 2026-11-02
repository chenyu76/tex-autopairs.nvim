local M = { pairs = {}, openers = {}, closers = {} }

-- open/close: opening token and its matching closing token.
-- standalone: pair direct input, e.g. ( inserts ).
-- sized: generate sized pairs, e.g. \left( and \bigl(.
-- replaceable: allow closer overrides, e.g. [x) replaces the generated ]; both pairs must allow it.
-- Omitted boolean flags default to false.
local definitions = {
	{ open = "(", close = ")", standalone = true, sized = true, replaceable = true },
	{ open = "[", close = "]", standalone = true, sized = true, replaceable = true },
	{ open = "\\{", close = "\\}", standalone = true, sized = true, replaceable = true },
	{ open = "\\langle", close = "\\rangle", standalone = true, sized = true, replaceable = true },
	{ open = "\\lceil", close = "\\rceil", standalone = true, sized = true, replaceable = true },
	{ open = "\\lfloor", close = "\\rfloor", standalone = true, sized = true, replaceable = true },
	{ open = "\\lbrace", close = "\\rbrace", standalone = true, sized = true, replaceable = true },
	{ open = "\\lbrack", close = "\\rbrack", standalone = true, sized = true, replaceable = true },
	{ open = "\\lparen", close = "\\rparen", standalone = true, sized = true, replaceable = true },
	{ open = "\\lvert", close = "\\rvert", standalone = true, sized = true, replaceable = true },
	{ open = "\\lVert", close = "\\rVert", standalone = true, sized = true, replaceable = true },
	{ open = "\\lgroup", close = "\\rgroup", standalone = true, sized = true, replaceable = true },
	{ open = "\\lmoustache", close = "\\rmoustache", standalone = true, sized = true, replaceable = true },
	{ open = "\\|", close = "\\|", standalone = true, sized = true, replaceable = true },
	-- Bare angles and bars also serve as relations or separators.
	{ open = "<", close = ">", sized = true, replaceable = true },
	{ open = "|", close = "|", sized = true, replaceable = true },
	{ open = "\\vert", close = "\\vert", sized = true, replaceable = true },
	{ open = "\\Vert", close = "\\Vert", sized = true, replaceable = true },
	{ open = "{", close = "}", standalone = true, replaceable = true },
	{ open = "\\(", close = "\\)", standalone = true },
	{ open = "\\[", close = "\\]", standalone = true },
	{ open = "`", close = "'", standalone = true },
}

for _, spec in ipairs(definitions) do
	if spec.standalone then
		table.insert(M.pairs, spec)
	end
end

-- Explicit right commands also accept opening shapes and invisible delimiters.
local extra_closers = {}
for _, size in ipairs({
	{ open = "\\left", close = "\\right" },
	{ open = "\\bigl", close = "\\bigr" },
	{ open = "\\Bigl", close = "\\Bigr" },
	{ open = "\\biggl", close = "\\biggr" },
	{ open = "\\Biggl", close = "\\Biggr" },
	{ open = "\\big", close = "\\big" },
	{ open = "\\Big", close = "\\Big" },
	{ open = "\\bigg", close = "\\bigg" },
	{ open = "\\Bigg", close = "\\Bigg" },
}) do
	for _, spec in ipairs(definitions) do
		if spec.sized then
			table.insert(M.pairs, {
				open = size.open .. spec.open,
				close = size.close .. spec.close,
				replaceable = spec.replaceable,
			})
			if size.open ~= size.close and spec.open ~= spec.close then
				table.insert(extra_closers, { close = size.close .. spec.open, replaceable = spec.replaceable })
			end
		end
	end
	table.insert(extra_closers, { close = size.close .. ".", replaceable = true })
end

local function add_to_index(index, token, spec)
	local key = token:sub(-1)
	index[key] = index[key] or {}
	table.insert(index[key], spec)
end

for id, spec in ipairs(M.pairs) do
	spec.id = id
	add_to_index(M.openers, spec.open, spec)
	add_to_index(M.closers, spec.close, spec)
end
for _, spec in ipairs(extra_closers) do
	add_to_index(M.closers, spec.close, spec)
end

local mapped = { ["$"] = true, ["<BS>"] = true }
for key, specs in pairs(M.openers) do
	mapped[key] = true
	table.sort(specs, function(a, b)
		return #a.open > #b.open
	end)
end
for key, specs in pairs(M.closers) do
	mapped[key] = true
	table.sort(specs, function(a, b)
		return #a.close > #b.close
	end)
end
M.keys = vim.tbl_keys(mapped)
table.sort(M.keys)

function M.escaped(before)
	return #(before:match("\\+$") or "") % 2 == 1
end

return M
