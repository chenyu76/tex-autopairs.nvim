local M = {}
local defaults = {
	-- Enter in a freshly generated empty pair opens a blank line; false disables it.
	newline = true,
	-- open/close: opening token and its matching closing token.
	-- standalone: pair direct input, e.g. ( inserts ).
	-- sized: combine this definition with each modifier below.
	-- replaceable: allow typing ) to replace a generated ], as in [0, 1).
	-- Both tokens must allow replacement and use the same closing size command.
	-- Omitted definition flags default to false.
	definitions = {
		{ open = "(", close = ")", standalone = true, sized = true, replaceable = true },
		{ open = "[", close = "]", standalone = true, sized = true, replaceable = true },
		{ open = "\\{", close = "\\}", standalone = true, sized = true },
		{ open = "\\langle", close = "\\rangle", standalone = true, sized = true },
		{ open = "\\lceil", close = "\\rceil", standalone = true, sized = true },
		{ open = "\\lfloor", close = "\\rfloor", standalone = true, sized = true },
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
		{ open = "|", close = "|", sized = true },
		{ open = "\\vert", close = "\\vert", sized = true, replaceable = true },
		{ open = "\\Vert", close = "\\Vert", sized = true, replaceable = true },
		-- Grouping braces, math markers, and quotes do not take size commands.
		{ open = "{", close = "}", standalone = true, replaceable = true },
		{ open = "\\(", close = "\\)", standalone = true },
		{ open = "\\[", close = "\\]", standalone = true },
		{ open = "`", close = "'", standalone = true },
	},
	-- Prefixes combined with definitions marked sized.
	modifiers = {
		{ open = "\\left", close = "\\right" },
		{ open = "\\bigl", close = "\\bigr" },
		{ open = "\\Bigl", close = "\\Bigr" },
		{ open = "\\biggl", close = "\\biggr" },
		{ open = "\\Biggl", close = "\\Biggr" },
		{ open = "\\big", close = "\\big" },
		{ open = "\\Big", close = "\\Big" },
		{ open = "\\bigg", close = "\\bigg" },
		{ open = "\\Bigg", close = "\\Bigg" },
	},
}

function M.merge(options)
	-- Replace whole lists; empty lists intentionally disable their pairing kind.
	return vim.tbl_extend("force", defaults, options)
end

return M
