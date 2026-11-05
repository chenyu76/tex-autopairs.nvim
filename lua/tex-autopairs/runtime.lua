-- Loaded by init on the first TeX buffer; start() precedes all buffer operations.
local api = vim.api
local delimiters = require("tex-autopairs.delimiters")
local input = require("tex-autopairs.input")
local tracking = require("tex-autopairs.tracking")
local environment = require("tex-autopairs.environment")
local M = {}
local mappings_by_buffer = {}
local on_key_namespace = api.nvim_create_namespace("tex-autopairs-input")
local group

---@param buf integer
function M.detach(buf)
	local mappings = mappings_by_buffer[buf]
	if not mappings then
		return
	end
	mappings_by_buffer[buf] = nil
	input.cancel_closing(buf)
	environment.cancel(buf)
	-- maparg/mapset operate in the current buffer, even for hidden buffers.
	api.nvim_buf_call(buf, function()
		for lhs, mapping in pairs(mappings) do
			local current = vim.fn.maparg(lhs, "i", false, true)
			if current.buffer == 1 and current.callback == mapping.callback then
				vim.keymap.del("i", lhs, { buffer = buf })
				if mapping.previous then
					vim.fn.mapset("i", false, mapping.previous)
				end
			end
		end
	end)
	tracking.detach(buf)
end

---@param buf integer
function M.attach(buf)
	local mappings = mappings_by_buffer[buf]
	if not mappings then
		mappings = {}
		mappings_by_buffer[buf] = mappings
		tracking.attach(buf)
	end
	-- maparg has no buffer argument; inspect mappings in their buffer's context.
	api.nvim_buf_call(buf, function()
		for _, lhs in ipairs(delimiters.keys) do
			local previous = vim.fn.maparg(lhs, "i", false, true)
			local mapping = mappings[lhs]
			-- Earlier FileType handlers can replace mappings without detaching pair tracking.
			if not mapping or previous.callback ~= mapping.callback then
				local callback = function()
					-- :noautocmd can change filetype without removing these mappings.
					if vim.bo.filetype == "tex" then
						input.insert(lhs)
					else
						input.feed(lhs)
					end
				end
				mappings[lhs] = {
					callback = callback,
					-- Detaching restores the buffer-local mapping displaced by this installation.
					previous = previous.buffer == 1 and previous or nil,
				}
				-- A non-expression callback sees preceding literal input after it commits.
				vim.keymap.set("i", lhs, callback, {
					buffer = buf,
					desc = "tex-autopairs: " .. lhs,
				})
			end
		end
	end)
end

function M.stop()
	for _, buf in ipairs(vim.tbl_keys(mappings_by_buffer)) do
		M.detach(buf)
	end
	vim.on_key(nil, on_key_namespace)
	api.nvim_del_augroup_by_id(group)
end

function M.start(config)
	delimiters.load(config)
	group = api.nvim_create_augroup("tex-autopairs", { clear = true })
	vim.on_key(input.observe, on_key_namespace)

	-- Buffer events maintain mappings without rebuilding the catalog or pair tracking.
	api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = group,
		callback = function(event)
			if vim.bo[event.buf].filetype == "tex" then
				M.attach(event.buf)
			else
				M.detach(event.buf)
			end
		end,
	})
	api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(event)
			M.detach(event.buf)
		end,
	})

	-- End transient input sessions and reconcile durable tracking with native edits.
	api.nvim_create_autocmd({ "BufLeave", "InsertLeavePre", "BufReadPre" }, {
		group = group,
		callback = function(event)
			input.cancel_closing(event.buf)
			environment.cancel(event.buf)
		end,
	})
	api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function(event)
			input.validate_cursor(event.buf)
		end,
	})
	api.nvim_create_autocmd({ "InsertEnter", "InsertLeavePre", "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(event)
			if mappings_by_buffer[event.buf] then
				-- Mappings also sync; the changedtick check makes duplicate calls cheap.
				tracking.sync(event.buf)
				if event.event == "InsertLeavePre" then
					tracking.prune(event.buf)
				end
			end
		end,
	})
	-- Mirror environment names after text edits and completion have settled.
	api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "CompleteDone" }, {
		group = group,
		callback = function(event)
			if environment.active(event.buf) then
				input.sync_environment()
			end
		end,
	})
end

return M
