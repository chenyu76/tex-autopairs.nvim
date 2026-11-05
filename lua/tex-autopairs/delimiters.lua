local M = {}
local mapped_keys

-- Runtime start builds the catalog before input or tracking can consume its indexes.
function M.load(config)
	local definitions, modifiers = config.definitions, config.modifiers
	M.pairs, M.openers, M.closers = {}, {}, {}

	-- Runtime close_modifier is the closing size command, or "" for unsized tokens.
	local function add_pair(open, close, close_modifier, replaceable)
		table.insert(M.pairs, {
			id = #M.pairs + 1,
			open = open,
			close = close,
			close_modifier = close_modifier,
			replaceable = replaceable == true,
		})
	end

	for _, spec in ipairs(definitions) do
		if spec.standalone then
			add_pair(spec.open, spec.close, "", spec.replaceable)
		end
	end

	-- Explicit right commands also accept opening shapes and invisible delimiters.
	local closer_tokens = {}
	local function add_closer(close, close_modifier, replaceable)
		table.insert(closer_tokens, { close = close, close_modifier = close_modifier, replaceable = replaceable })
	end

	for _, modifier in ipairs(modifiers) do
		for _, spec in ipairs(definitions) do
			if spec.sized then
				add_pair(modifier.open .. spec.open, modifier.close .. spec.close, modifier.close, spec.replaceable)
				if modifier.open ~= modifier.close and spec.open ~= spec.close then
					add_closer(modifier.close .. spec.open, modifier.close, spec.replaceable == true)
				end
			end
		end
		-- A dot after a size command denotes an invisible delimiter.
		add_closer(modifier.close .. ".", modifier.close, true)
	end

	local function add_to_index(index, token, spec)
		-- Mappings run on the final character of a complete token.
		local key = token:sub(-1)
		index[key] = index[key] or {}
		table.insert(index[key], spec)
	end

	for _, spec in ipairs(M.pairs) do
		add_to_index(M.openers, spec.open, spec)
		-- Closers have their own vocabulary; some have no corresponding opener.
		add_closer(spec.close, spec.close_modifier, spec.replaceable)
	end
	for _, spec in ipairs(closer_tokens) do
		add_to_index(M.closers, spec.close, spec)
	end

	-- Dollar input and deletion are handled outside the ordinary token lookup.
	mapped_keys = { ["$"] = true, ["<BS>"] = true }
	-- Openers match buffer suffixes; closers need every character mapped for prefix merging.
	for key in pairs(M.openers) do
		mapped_keys[key] = true
	end
	for _, spec in ipairs(closer_tokens) do
		for key in spec.close:gmatch(".") do
			mapped_keys[key] = true
		end
	end
	for _, openers in pairs(M.openers) do
		table.sort(openers, function(a, b)
			return #a.open > #b.open
		end)
	end
	for _, closers in pairs(M.closers) do
		table.sort(closers, function(a, b)
			return #a.close > #b.close
		end)
	end
	M.keys = vim.tbl_keys(mapped_keys)
	table.sort(M.keys)
end

function M.is_mapped(key)
	return mapped_keys[key] == true
end

function M.can_replace(pair, closer)
	return pair.replaceable and closer.replaceable and pair.close_modifier == closer.close_modifier
end

-- Dollars stay outside the ordinary catalog; only their pair representation is shared.
function M.dollar(token)
	return { id = token, open = token, close = token, close_modifier = "", replaceable = false }
end

return M
