local M = {}

M.cli = require('yatr.cli')
M.log = require('yatr.log')
M.image_api = require('image')

M.hl_group = 'YatrMathOverlay'
M.error_hl_group = 'YatrMathError'
M.parsing_lang = "markdown_inline"

M.namespace_id = vim.api.nvim_create_namespace('yatr_math_renderer')
M.error_namespace_id = vim.api.nvim_create_namespace('yatr_math_error')

M.extmarks_by_buffer = {}
M.error_extmarks_by_buffer = {}
M.images_on_screen = {}
M.all_loaded_images = {}
M.top_offset = 1

M.x_offset = 100

M.autocmd_group = vim.api.nvim_create_augroup('YatrMathRenderer', { clear = true })

function M.enable_auto_render(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  vim.api.nvim_create_autocmd(
    { 'TextChanged', 'TextChangedI', 'WinScrolled' }, {
      group = M.autocmd_group,
      buffer = bufnr,
      callback = function()
        M.log.debug(string.format('[Yatr Renderer] Text changed in buffer: %d', bufnr))
        M.render_math_overlays(bufnr)
      end,
    })
end

function M.disable_auto_render()
  vim.api.nvim_clear_autocmds({ group = M.autocmd_group })
end

local function setup_highlight()
  vim.cmd(string.format('highlight %s guifg=White ctermfg=White', M.hl_group))
end

local function setup_error_highlight()
  vim.cmd(string.format('highlight %s guifg=Red ctermfg=Red', M.error_hl_group))
end

local function count_dollar_signs(text)
  local count = 0
  for char in text:gmatch(".") do
    if char == "$" then
      count = count + 1
    end
  end
  return count
end

local function determine_block_type(text)
  -- Single dollar sign $...$ is inline mode
  if text == "$" then
    return 'inline', 1
  end
  -- Double dollar signs $$...$$ is block mode (math mode)
  if text == "$$" then
    return 'block', 2
  end
  -- Escaped parentheses \(...\) is inline mode
  if text == "\\(" or text == "\\)" then
    return 'inline', 1
  end
  -- Escaped brackets \[...\] is block mode (math mode)
  if text == "\\[" or text == "\\]" then
    return 'block', 2
  end
  -- Fallback: count dollar signs if text doesn't exactly match
  local dollar_count = count_dollar_signs(text)
  if dollar_count == 1 then
    return 'inline', 1
  elseif dollar_count == 2 then
    return 'block', 2
  end
  -- Default to block mode if none match
  return 'block', 2
end

local function find_math_environments(bufnr)
  local math_regions = {}
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, M.parsing_lang)
  if not ok or not parser then
    M.log.warn(string.format('[Yatr Renderer] Treesitter parser not available for buffer %d', bufnr))
    return math_regions
  end

  local query_block = vim.treesitter.query.parse(M.parsing_lang, [[
    ; query
    (latex_block) @math_block
  ]])
  local query_span = vim.treesitter.query.parse(M.parsing_lang, [[
    ; query
    (latex_span_delimiter) @block_delimiter
  ]])
  local tree = parser:parse()[1]
  if not tree then
    return math_regions
  end

  for capture_id, node in query_block:iter_captures(tree:root(), 0) do
    local capture_name = query_block.captures[capture_id]
    if capture_name ~= 'math_block' then
      goto continue
    end

    local block_start_row, block_start_col, block_end_row, block_end_col = node:range()
    local block_type = 'block'
    local offset = 2

    for span_capture_id, span_node in query_span:iter_captures(node, 0) do
      local span_capture_name = query_span.captures[span_capture_id]
      if span_capture_name == 'block_delimiter' then
        local text = vim.treesitter.get_node_text(span_node, bufnr)
        block_type, offset = determine_block_type(text)
        -- M.log.debug(string.format('[Yatr Renderer] Capture name: %s, node type: %s', span_capture_name, node:type()))
        break
      end
    end

    -- M.log.debug(string.format('[Yatr Renderer] Found latex block region: %d:%d -> %d:%d, type=%s',
    -- block_start_row, block_start_col, block_end_row, block_end_col, block_type))

    table.insert(math_regions, {
      type = block_type,
      block_rect = { block_start_row, block_start_col, block_end_row, block_end_col },
      offset = offset,
    })
    ::continue::
  end

  return math_regions
end

local function get_viewport_rows(offset)
  offset = offset or 0
  return vim.fn.line('w0') - offset, vim.fn.line('w$') + offset
end

local function is_region_in_viewport(start_line, end_line, viewport_start, viewport_end)
  -- Check if region overlaps with viewport
  -- A region is in viewport if it starts before viewport_end and ends after viewport_start
  return start_line <= viewport_end and end_line >= viewport_start
end

-- local function is_cursor_in_region(cursor_line, cursor_col, start_line, start_col, end_line, end_col)
--   if cursor_line < start_line or cursor_line > end_line then
--     return false
--   end
--   if cursor_line == start_line and cursor_col < start_col then
--     return false
--   end
--   if cursor_line == end_line and cursor_col >= end_col then
--     return false
--   end
--   return true
-- end

local function clear_extmarks(bufnr, namespace, extmarks_table)
  local extmarks = extmarks_table[bufnr]
  if not extmarks then
    return
  end
  for _, extmark_id in ipairs(extmarks) do
    vim.api.nvim_buf_del_extmark(bufnr, namespace, extmark_id)
  end
  extmarks_table[bufnr] = {}
end

local function get_line_number_width(bufnr)
  if vim.opt.number:get() then
    return #tostring(vim.fn.line('$'))
  end
  if vim.opt.relativenumber:get() then
    local start_line, end_line = get_viewport_rows()
    return #tostring(end_line - start_line)
  end
  return 0
end

local function process_region_text(lines, offset)
  local processed_lines = {}
  for i, line in ipairs(lines) do
    processed_lines[i] = line:gsub("%z", "\n")
  end
  local tex_string = table.concat(processed_lines)
  local len = #tex_string

  if len <= 2 * offset then
    return nil
  end

  return tex_string:sub(offset + 1, len - offset)
end

------------------------------------------------ RENDERING ------------------------------------------------

local function render_image(image_to_render, png_file, viewport_start)
  local start_line = image_to_render.start_line
  local start_col = image_to_render.start_col
  local end_line = image_to_render.end_line
  local height = math.max(end_line - start_line, 1)

  local image = M.render_png(png_file, {
    height = height,
    y = start_line + M.top_offset - viewport_start,
    x = start_col + M.x_offset,
  })

  if image then
    M.all_loaded_images[image_to_render.bufnr][image_to_render.tex_base64_with_pos] = {
      image = image,
      rendered = true,
    }
  else
    M.log.error(string.format('[Yatr Renderer] Failed to render image: %s', png_file))
  end
end

function M.render_math_overlays(bufnr)
  setup_highlight()
  clear_extmarks(bufnr, M.namespace_id, M.extmarks_by_buffer)
  if M.all_loaded_images[bufnr] == nil then
    M.all_loaded_images[bufnr] = {}
  end

  -- Get viewport with buffer for smooth scrolling (render slightly outside viewport)
  local viewport_buffer = 0 -- Number of lines to render outside viewport
  local viewport_start, viewport_end = get_viewport_rows(viewport_buffer)
  -- Convert to 0-indexed
  viewport_start = viewport_start - 1
  viewport_end = viewport_end - 1

  local math_regions = find_math_environments(bufnr)
  local images_to_render = {}
  local cursor_pos = vim.api.nvim_win_get_cursor(0)

  for _, region in ipairs(math_regions) do
    local start_line, start_col, end_line, end_col =
        region.block_rect[1], region.block_rect[2], region.block_rect[3], region.block_rect[4]

    -- TODO: Add preloading
    if not is_region_in_viewport(start_line, end_line, viewport_start, viewport_end) then
      goto continue
    end

    local lines = vim.api.nvim_buf_get_text(bufnr, start_line, start_col, end_line, end_col, {})

    local tex_string = process_region_text(lines, region.offset)
    if tex_string then
      local tex_base64 = vim.base64.encode(tex_string)
      local tex_base64_with_pos = vim.base64.encode(string.format("%d:%d:%d:%d:%s", bufnr, start_line, start_col,
        end_line,
        tex_string))


      images_to_render[tex_base64_with_pos] = {
        tex_string = tex_string,
        tex_base64 = tex_base64,
        tex_base64_with_pos = tex_base64_with_pos,
        bufnr = bufnr,
        start_line = start_line,
        start_col = start_col,
        end_line = end_line,
        end_col = end_col,
      }

      M.log.debug(string.format('[Yatr Renderer] Added image to render: %s, %d:%d:%d:%d', tex_base64_with_pos, bufnr,
        start_line,
        start_col, end_line))
    end
    ::continue::
  end

  vim.schedule(function()
    for _, image in pairs(M.all_loaded_images[bufnr]) do
      image.image:clear()
    end
  end)

  M.clear_error_extmarks(bufnr)

  -- Render new images
  for _, image_to_render in pairs(images_to_render) do
    M.log.debug(string.format('[Yatr Renderer] Rendering image: %s', image_to_render.tex_base64))
    M.cli.convert_tex_to_png(
      image_to_render.tex_string,
      image_to_render.tex_base64,
      function(png_file)
        vim.schedule(function()
          render_image(image_to_render, png_file, viewport_start)
        end)
      end,
      function(error)
        vim.schedule(function()
          M.create_error_extmark(image_to_render, error)
        end)
      end
    )
  end
end

function M.create_error_extmark(image_to_render, error_message)
  vim.schedule(function()
    setup_error_highlight()
    local ok, error_extmark = pcall(vim.api.nvim_buf_set_extmark,
      image_to_render.bufnr,
      M.error_namespace_id,
      image_to_render.start_line,
      image_to_render.start_col,
      {
        virt_text = { { error_message, M.error_hl_group } },
        virt_text_pos = 'overlay',
        virt_text_win_col = image_to_render.start_col + M.x_offset,
        strict = false,
        priority = 2000,
      }
    )
    if ok then
      if not M.error_extmarks_by_buffer[image_to_render.bufnr] then
        M.error_extmarks_by_buffer[image_to_render.bufnr] = {}
      end
      table.insert(M.error_extmarks_by_buffer[image_to_render.bufnr], error_extmark)
      M.log.debug(string.format('[Yatr Renderer] Created error extmark for buffer: %d', image_to_render.bufnr))
    end
  end)
end

function M.clear_error_extmarks(bufnr)
  if not M.error_extmarks_by_buffer[bufnr] then
    return
  end
  for _, error_extmark in ipairs(M.error_extmarks_by_buffer[bufnr]) do
    vim.api.nvim_buf_del_extmark(bufnr, M.error_namespace_id, error_extmark)
  end
  M.error_extmarks_by_buffer[bufnr] = {}
end

function M.clear_math_overlays(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  clear_extmarks(bufnr, M.namespace_id, M.extmarks_by_buffer)
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, M.error_namespace_id, 0, -1)

  for tex_string, image in pairs(M.images_on_screen) do
    if image and image.clear then
      image:clear()
    end
  end
  M.images_on_screen = {}
  if M.all_loaded_images[bufnr] then
    M.all_loaded_images[bufnr] = {}
  end
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

  -- M.log.debug(string.format('[Yatr Renderer] Rendering png file: %s', png_file))
  ---@diagnostic disable-next-line: missing-parameter
  local image = M.image_api.from_file(png_file, opts)

  if image then
    image:render()
  else
    M.log.debug(string.format('[Yatr Renderer] Failed to render png file: %s', png_file))
  end

  return image
end

return M
