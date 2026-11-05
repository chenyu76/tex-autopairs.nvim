local api = vim.api
local M = {}
local runtime
local options = {}
local loader_group

local function resolve_buf(buf)
	return (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
end

local function load_runtime()
	-- Bootstrap listeners are replaced by the runtime's buffer lifecycle handlers.
	if loader_group then
		api.nvim_del_augroup_by_id(loader_group)
		loader_group = nil
	end
	local config = require("tex-autopairs.config").merge(options)
	runtime = require("tex-autopairs.runtime")
	runtime.start(config)
end

---@param buf? integer
function M.attach(buf)
	buf = resolve_buf(buf)
	if not api.nvim_buf_is_loaded(buf) or vim.bo[buf].filetype ~= "tex" then
		return
	end
	if not runtime then
		load_runtime()
	end
	runtime.attach(buf)
end

---@param buf? integer
function M.detach(buf)
	if runtime then
		runtime.detach(resolve_buf(buf))
	end
end

function M.setup(opts)
	if runtime then
		runtime.stop()
		runtime = nil
	end
	-- Capture options now; the first TeX buffer may be opened much later.
	options = vim.deepcopy(opts or {})
	for _, buf in ipairs(api.nvim_list_bufs()) do
		M.attach(buf)
	end
	if runtime then
		return
	end
	-- Non-TeX sessions need no pairing modules or input listeners.
	loader_group = api.nvim_create_augroup("tex-autopairs-loader", { clear = true })
	api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = loader_group,
		callback = function(event)
			M.attach(event.buf)
		end,
	})
end

return M
