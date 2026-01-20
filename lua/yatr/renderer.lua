local M = {}

local cli = require('yatr.cli')
local term = require('image.utils.term')
local log = require('yatr.log')

local hl_group = 'YatrMathOverlay'
local error_hl_group = 'YatrMathError'
local parsing_lang = "markdown_inline"

local namespace_id = vim.api.nvim_create_namespace('yatr_math_renderer')
local error_namespace_id = vim.api.nvim_create_namespace('yatr_math_error')

local extmarks_by_buffer = {}
local error_extmarks_by_buffer = {}

local image_cache = require('yatr.cache').new(100)
local images_on_screen = {}

local cursor_in_region = false

M.box_horizontal = '─'
M.box_vertical = '│'
M.box_top_left = '╭'
M.box_top_right = '╮'
M.box_bottom_left = '╰'
M.box_bottom_right = '╯'
M.x_offset = 100


local function setup_highlight()
  vim.cmd(string.format(
    'highlight %s  guifg=White ctermfg=White',
    M.hl_group
  ))
  -- alternatively add: guibg=Black ctermbg=Black
end

local function setup_error_highlight()
  vim.cmd(string.format(
    'highlight %s  guifg=Red ctermfg=Red',
    M.error_hl_group
  ))
end

local function find_math_environments(bufnr)
  local math_regions = {}

  -- Check if Treesitter is available
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, parsing_lang)
  if not ok or not parser then
    log.warn('[Yatr Renderer] Treesitter parser not available for buffer ' .. bufnr)
    return math_regions
  end

  local query_block = vim.treesitter.query.parse(parsing_lang, [[
    ; query
    (latex_block) @math_block
  ]])
  local query_span = vim.treesitter.query.parse(parsing_lang, [[
    ; query
    (latex_span_delimiter) @block_delimiter
  ]])
  local tree = parser:parse()[1]

  -- Iterate over captures
  for capture_id, node in query_block:iter_captures(tree:root(), 0) do
    local capture_name = query_block.captures[capture_id]

    if capture_name == 'math_block' then
      local type = 'block'

      local block_start_row, block_start_col, block_end_row, block_end_col = node:range()

      local offset = 0
      for capture_id, _ in query_span:iter_captures(node, 0) do
        local capture_name = query_span.captures[capture_id]
        log.debug(string.format('[Yatr Renderer] Capture name: %s, node type: %s', capture_name, node:type()))

        if capture_name == 'block_delimiter' then
          -- get the text of the node
          local text = vim.treesitter.get_node_text(node, bufnr)
          -- count the number of $ in the text
          local count = 0
          for char in text:gmatch(".") do
            if char == "$" then
              count = count + 1
            end
          end

          if count == 2 then
            offset = 1
            type = 'inline'

            -- find if contains ( or )
          elseif text:find("%\\%(") or text:find("%\\%)") then
            offset = 1
            type = 'inline'
          else
            offset = 2
            type = 'block'
          end
        end
      end

      log.debug(string.format('[Yatr Renderer] Found latex block region: %d:%d -> %d:%d, type=%s',
        block_start_row, block_start_col, block_end_row, block_end_col, type))

      table.insert(math_regions, {
        type = type,
        block_rect = { block_start_row, block_start_col, block_end_row, block_end_col },
        offset = offset,
      })
    end
  end


  return math_regions
end

local function get_viewport_rows(offset)
  local start_line = vim.fn.line('w0') - offset
  local end_line = vim.fn.line('w$') + offset
  return start_line, end_line
end

function M.render_math_overlays(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local viewport_start_line, viewport_end_line = get_viewport_rows(10)

  -- TODO: better way to clear extmarks
  if extmarks_by_buffer[bufnr] then
    for _, extmark_id in ipairs(extmarks_by_buffer[bufnr]) do
      vim.api.nvim_buf_del_extmark(bufnr, namespace_id, extmark_id)
    end
  end
  extmarks_by_buffer[bufnr] = {}

  setup_highlight()

  local math_regions = find_math_environments(bufnr)
  local images_to_render = {}

  -- Draw rectangle overlay and render SVG for each math region
  for _, region in ipairs(math_regions) do
    local start_line = region.block_rect[1]
    local start_col = region.block_rect[2]
    local end_line = region.block_rect[3]
    local end_col = region.block_rect[4]

    local lines = vim.api.nvim_buf_get_text(bufnr, start_line, start_col, end_line, end_col, {})

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor_pos[1] - 1 -- 0-indexed
    local cursor_col = cursor_pos[2]      -- 0-indexed
    cursor_in_region = false

    if cursor_line >= start_line and cursor_line <= end_line then
      if cursor_line == start_line then
        if cursor_col >= start_col then
          cursor_in_region = true
        end
      elseif cursor_line == end_line then
        if cursor_col < end_col then
          cursor_in_region = true
        end
      else
        cursor_in_region = true
      end
    end


    if cursor_in_region then
      -- clear the error extmarks of the buffer
      log.debug(string.format('[Yatr Renderer] Clearing error extmarks for buffer: %d', bufnr))
      M.clear_error_extmarks(bufnr)
    else
      -- local max_line_width = 0
      -- for _, line in ipairs(lines) do
      --   max_line_width = math.max(max_line_width, #line)
      -- end


      --   if start_line >= viewport_start_line and start_line <= viewport_end_line then
      --     -- Top edge: virt_line above
      --     local virt_line_rect_top = { { string.rep(' ', start_col) .. M.box_top_left .. string.rep(M.box_horizontal, max_line_width) .. M.box_top_right, hl_group } }
      --     local ok_top, top_extmark = pcall(vim.api.nvim_buf_set_extmark,
      --       bufnr,
      --       namespace_id,
      --       start_line,
      --       start_col + 1,
      --       {
      --         virt_lines = { virt_line_rect_top },
      --         virt_lines_above = true,
      --         priority = 1000,
      --       }
      --     )
      --     if ok_top then
      --       table.insert(extmarks_by_buffer[bufnr], top_extmark)
      --     end
      --   end

      --   if end_line >= viewport_start_line and end_line <= viewport_end_line then
      --     -- Bottom edge: virt_line below
      --     local virt_line_rect_bottom = { { string.rep(' ', start_col) .. M.box_bottom_left .. string.rep(M.box_horizontal, max_line_width) .. M.box_bottom_right, hl_group } }
      --     local ok_bottom, bottom_extmark = pcall(vim.api.nvim_buf_set_extmark,
      --       bufnr,
      --       namespace_id,
      --       end_line,
      --       start_col,
      --       {
      --         virt_lines = { virt_line_rect_bottom },
      --         virt_lines_above = false,
      --         priority = 1000,
      --       }
      --     )
      --     if ok_bottom then
      --       table.insert(extmarks_by_buffer[bufnr], bottom_extmark)
      --     end
      --   end

      --   -- Fill rectangle interior: overlay virtual text on each line
      --   for line_idx = start_line, end_line do
      --     -- Calculate column range for this line

      --     if line_idx >= viewport_start_line and line_idx <= viewport_end_line then
      --       -- Begin vertical line
      --       local ok, overlay_extmark = pcall(vim.api.nvim_buf_set_extmark,
      --         bufnr,
      --         namespace_id,
      --         line_idx,
      --         start_col,
      --         {
      --           virt_text = { { M.box_vertical, hl_group } },
      --           virt_text_pos = 'inline',
      --           priority = 500,
      --         }
      --       )
      --       if ok then
      --         table.insert(extmarks_by_buffer[bufnr], overlay_extmark)
      --       end

      --       if max_line_width > 0 then
      --         -- Overlay virtual text to fill the rectangle on this line
      --         local overlay_text = string.rep(' ', max_line_width)
      --         local ok, overlay_extmark = pcall(vim.api.nvim_buf_set_extmark,
      --           bufnr,
      --           namespace_id,
      --           line_idx,
      --           start_col,
      --           {
      --             virt_text = { { overlay_text, hl_group } },
      --             virt_text_pos = 'overlay',
      --             priority = 1000,
      --           }
      --         )
      --         if ok then
      --           table.insert(extmarks_by_buffer[bufnr], overlay_extmark)
      --         end
      --       end

      --       local ok, overlay_extmark = pcall(vim.api.nvim_buf_set_extmark,
      --         bufnr,
      --         namespace_id,
      --         line_idx,
      --         0,
      --         {
      --           virt_text = { { M.box_vertical, hl_group } },
      --           virt_text_win_col = start_col + max_line_width + 1,
      --           priority = 1500,
      --           strict = false,
      --         }
      --       )
      --       if ok then
      --         table.insert(extmarks_by_buffer[bufnr], overlay_extmark)
      --       end
      --     end
      --   end
    end

    -- trim special characters and whitespace
    local tex_string = ''
    for i, line in ipairs(lines) do
      lines[i] = line:gsub("%z", "\n")
      log.debug(string.format('[Yatr Renderer] Line %d: %s', i, lines[i]))
      tex_string = tex_string .. lines[i]
    end
    local len = #tex_string
    log.debug(string.format('[Yatr Renderer] Found latex region: %s', tex_string))
    if len > 2 * region.offset then
      tex_string = tex_string:sub(region.offset + 1, len - region.offset)
      log.debug(string.format('[Yatr Renderer] Trimmed latex region: %s offset: %d type: %s', tex_string, region
        .offset,
        region.type))
      local tex_base64 = vim.base64.encode(tex_string)
      table.insert(images_to_render, {
        tex_string = tex_string,
        tex_base64 = tex_base64,
        bufnr = bufnr,
        start_line = start_line,
        start_col = start_col,
        end_line = end_line,
        end_col = end_col,
      })
    end
  end

  -- clear previous images
  for _, image in ipairs(images_on_screen) do
    image:clear()
  end
  images_on_screen = {}

  -- render new images
  for i, image_to_render in ipairs(images_to_render) do
    cli:convert_tex_to_png(image_to_render.tex_string, image_to_render.tex_base64, function(png_file)
      log.debug(string.format('[Yatr Renderer] Successfully converted tex to png: %s', png_file))
      image_to_render.png_file = png_file
      local start_line = image_to_render.start_line
      local start_col = image_to_render.start_col
      local end_line = image_to_render.end_line
      local end_col = image_to_render.end_col

      local height = math.max(end_line - start_line, 1)

      -- check if linenumber is enabled
      local x_offset = 0
      if vim.opt.number then
        local max_line_number = vim.fn.line('$')
        local line_number_width = #tostring(max_line_number)
        x_offset = line_number_width
      elseif vim.opt.relativenumber then
        local start_line, end_line = get_viewport_rows()
        local line_number_width = #tostring(end_line - start_line)
        x_offset = line_number_width
      end

      local image = M.render_png(png_file, {
        height = height,
        y = start_line + math.floor(height / 2),
        -- y = start_line + 2 * i + math.floor(height / 2),  -- +2i handles virtual lines
        x = x_offset + start_col + M.x_offset,
      })
      table.insert(images_on_screen, image)
    end, function(error)
      M.create_error_extmark(image_to_render.bufnr, image_to_render.start_line, image_to_render.start_col, error)
    end)
  end
end

function M.create_error_extmark(bufnr, start_line, start_col, math_content)
  vim.schedule(function()
    setup_error_highlight()
    local ok, ghost_extmark = pcall(vim.api.nvim_buf_set_extmark,
      bufnr,
      error_namespace_id,
      start_line,
      start_col,
      {
        virt_text = { { math_content, error_hl_group } },
        virt_text_pos = 'overlay',
        priority = 2000,
      }
    )
    if ok then
      if not error_extmarks_by_buffer[bufnr] then
        error_extmarks_by_buffer[bufnr] = {}
      end

      table.insert(error_extmarks_by_buffer[bufnr], ghost_extmark)
      log.debug(string.format('[Yatr Renderer] Created error extmark for buffer: %d', bufnr))
    end
  end)
end

function M.clear_error_extmarks(bufnr)
  if error_extmarks_by_buffer[bufnr] then
    for _, extmark_id in ipairs(error_extmarks_by_buffer[bufnr]) do
      vim.api.nvim_buf_del_extmark(bufnr, error_namespace_id, extmark_id)
    end
    error_extmarks_by_buffer[bufnr] = {}

    log.debug(string.format('[Yatr Renderer] Cleared error extmarks for buffer: %d', bufnr))
  else
    log.debug(string.format('[Yatr Renderer] No error extmarks found for buffer: %d', bufnr))
  end
end

function M.clear_math_overlays(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if extmarks_by_buffer[bufnr] then
    for _, extmark_id in ipairs(extmarks_by_buffer[bufnr]) do
      vim.api.nvim_buf_del_extmark(bufnr, namespace_id, extmark_id)
    end
    extmarks_by_buffer[bufnr] = {}
  end

  -- Clear all extmarks in namespace for this buffer
  vim.api.nvim_buf_clear_namespace(bufnr, namespace_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, error_namespace_id, 0, -1)
  for _, image in ipairs(images_on_screen) do
    image:clear()
  end
  images_on_screen = {}
end

-- Auto-render on buffer changes (optional, can be enabled via setup)
local autocmd_group = nil

function M.enable_auto_render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not autocmd_group then
    autocmd_group = vim.api.nvim_create_augroup('YatrMathRenderer', { clear = true })
  end

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'CursorMoved' }, {
    group = autocmd_group,
    buffer = bufnr,
    callback = function()
      -- remove previous rendered images
      M.render_math_overlays(bufnr)
    end,
  })

  -- Initial render (enabled by default)
  M.render_math_overlays(bufnr)
end

function M.disable_auto_render()
  if autocmd_group then
    vim.api.nvim_clear_autocmds({ group = autocmd_group })
    autocmd_group = nil
  end
end

-- Use image.nvim API for rendering images
local image_api = nil
local function get_image_api()
  if not image_api then
    local ok, api = pcall(require, "image")
    if not ok then
      log.error("[Yatr Renderer] image.nvim not found. Please install it to use image rendering features.")
      return nil
    end
    image_api = api
  end
  return image_api
end

-- Render PNG using image.nvim API
-- @param png_file string: Path to PNG file (absolute path)
-- @param opts table: Optional parameters (same as image.nvim from_file options):
--   - id: Image ID (optional, defaults to random string)
--   - window: Window number to bind image to (optional)
--   - buffer: Buffer number to bind image to (optional, paired with window)
--   - with_virtual_padding: Pad vertically with extmarks (default: false)
--   - inline: Bind image to extmark (default: false, forced true if with_virtual_padding)
--   - x: X position in cells (optional)
--   - y: Y position in cells (optional)
--   - width: Width in cells (optional)
--   - height: Height in cells (optional)
-- @return image object or nil
function M.render_png(png_file, opts)
  opts = opts or {}

  local api = get_image_api()

  log.debug(string.format('[Yatr Renderer] Rendering png file: %s', png_file))
  ---@diagnostic disable-next-line: missing-parameter
  local image = api.from_file(png_file, opts)

  if image then
    image:render()
  else
    log.debug(string.format('[Yatr Renderer] Failed to render png file: %s', png_file))
  end

  return image
end

return M
