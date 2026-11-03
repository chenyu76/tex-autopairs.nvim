local M = { pairs = {}, openers = {}, closers = {} }

-- open/close: opening token and its matching closing token.
-- standalone: pair direct input, e.g. ( inserts ).
-- sized: generate sized pairs, e.g. \left( and \bigl(.
-- replaceable: allow standalone closer overrides, e.g. [x) replaces the generated ].
-- Both pairs must allow an override; all generated sized pairs allow it.
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
	{ open = "<", close = ">", sized = true },
	{ open = "|", close = "|", sized = true },
	{ open = "\\vert", close = "\\vert", sized = true },
	{ open = "\\Vert", close = "\\Vert", sized = true },
	{ open = "{", close = "}", standalone = true, replaceable = true },
	{ open = "\\(", close = "\\)", standalone = true },
	{ open = "\\[", close = "\\]", standalone = true },
	{ open = "`", close = "'", standalone = true },
}

for _, spec in ipairs(definitions) do
	if spec.standalone then
		table.insert(M.pairs, {
			open = spec.open,
			close = spec.close,
			replaceable = spec.replaceable == true,
		})
	end
end

-- Explicit right commands also accept opening shapes and invisible delimiters.
local closer_tokens = {}
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
			-- All sized pairs allow closer overrides.
			table.insert(M.pairs, {
				open = size.open .. spec.open,
				close = size.close .. spec.close,
				replaceable = true,
			})
			if size.open ~= size.close and spec.open ~= spec.close then
				table.insert(closer_tokens, { close = size.close .. spec.open, replaceable = true })
			end
		end
	end
	-- A dot after a size command denotes an invisible delimiter.
	table.insert(closer_tokens, { close = size.close .. ".", replaceable = true })
end

local function add_to_index(index, token, spec)
	-- Mappings run on the final character of a complete token.
	local key = token:sub(-1)
	index[key] = index[key] or {}
	table.insert(index[key], spec)
end

for id, spec in ipairs(M.pairs) do
	spec.id = id
	add_to_index(M.openers, spec.open, spec)
	-- Closers have their own vocabulary; some have no corresponding opener.
	table.insert(closer_tokens, { close = spec.close, replaceable = spec.replaceable })
end
for _, spec in ipairs(closer_tokens) do
	add_to_index(M.closers, spec.close, spec)
end

-- Dollar input and deletion are handled outside the ordinary token lookup.
local mapped_keys = { ["$"] = true, ["<BS>"] = true }
for key in pairs(M.openers) do
	mapped_keys[key] = true
end
for _, spec in ipairs(closer_tokens) do
	for key in spec.close:gmatch(".") do
		mapped_keys[key] = true
	end
end
M.keys = vim.tbl_keys(mapped_keys)
table.sort(M.keys)
for _, key in ipairs(M.keys) do
	local openers, closers = M.openers[key] or {}, M.closers[key] or {}
	M.openers[key], M.closers[key] = openers, closers
	table.sort(openers, function(a, b)
		return #a.open > #b.open
	end)
	table.sort(closers, function(a, b)
		return #a.close > #b.close
	end)
end

return M
