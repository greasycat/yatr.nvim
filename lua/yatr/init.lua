local M = {}
local cli = require('yatr.cli')
local api = require('yatr.api')
local renderer = require('yatr.renderer')
local term = require('image.utils.term')

local check_supports = function()
	if not vim.base64 or not vim.base64.encode then
		return false
	end
	return true
end

function M.setup()
	cli.setup()

	local yatr_group = vim.api.nvim_create_augroup('YatrMarkdownRenderer', { clear = true })
	
	-- vim.api.nvim_create_autocmd('FileType', {
	-- 	group = yatr_group,
	-- 	pattern = 'markdown',
	-- 	callback = function(event)
	-- 		renderer.enable_auto_render(event.buf)
	-- 	end,
	-- })
	
	-- Also enable for existing markdown buffers
	vim.api.nvim_create_autocmd('BufWinEnter', {
		group = yatr_group,
		pattern = '*.md',
		callback = function(event)
			if vim.bo[event.buf].filetype == 'markdown' then
				renderer.enable_auto_render(event.buf)
			end
		end,
	})
	
end

-- Expose CLI functions
M.cli = cli

-- Expose API functions
M.api = api

-- Expose renderer functions
M.renderer = renderer

return M
