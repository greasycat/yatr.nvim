local M = {}
local cli = require('yatr.cli')
local renderer = require('yatr.renderer')

function M.setup(opts)
	cli.setup()

	local yatr_group = vim.api.nvim_create_augroup('YatrMarkdownRenderer', { clear = true })

	vim.api.nvim_create_autocmd('BufWinEnter', {
		group = yatr_group,
		pattern = { '*.md' },
		callback = function(event)
			if vim.bo[event.buf].filetype == 'markdown' then
				renderer.enable_auto_render(event.buf)
			end
		end,
	})
end

-- Expose CLI functions
M.cli = cli

-- Expose renderer functions
M.renderer = renderer

return M
