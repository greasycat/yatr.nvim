---@diagnostic disable: missing-fields
local M = {
  style_path = nil,
  image_height = 256,
  ok = false,
}

local log = require('yatr.log')
local file_cache = require('yatr.cache').new(100)

local function check_dependencies()
  if vim.fn.executable("node") == 0 then
    log.error("Node.js not found. Please install it to use the MathJax CLI.")
    return false
  end

  local script_path = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(script_path, ":h:h:h")
  local cli_script_path = plugin_root .. "/cli/mathjax-cli.js"

  if vim.fn.filereadable(cli_script_path) == 0 then
    log.error("MathJax CLI script not found at: " .. cli_script_path)
    return false
  end

  if vim.fn.executable("rsvg-convert") == 0 then
    log.error("rsvg-convert not found. Please install it to use the MathJax CLI.")
    return false
  end

  local style_path = plugin_root .. "/cli/white.css"
  if vim.fn.filereadable(style_path) == 1 then
    M.style_path = style_path
  end

  M.mathjax_cmd = { "node", cli_script_path, "--display", "false" }
  M.rsvg_cmd = { "rsvg-convert", "--stylesheet", style_path, "--format", "png", "-a", "-h", tostring(M.image_height) }
  M.ok = true
  return true
end

function M.setup()
  check_dependencies()
end

local function trim_string(str)
  if not str then
    return ""
  end
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

local function handle_mathjax_error(error_callback, result)
  vim.schedule(function()
    log.debug(string.format('[Yatr CLI] Mathjax error: %s', vim.inspect(result)))
    pcall(error_callback, result.stderr)
  end)
end

local function handle_rsvg_error(error_callback, temp_file, result)
  vim.schedule(function()
    log.debug(string.format('[Yatr CLI] Rsvg error: %s', vim.inspect(result)))
    vim.fn.delete(temp_file)
    pcall(error_callback, result.stderr)
  end)
end

local function convert_svg_to_png(svg_string, cache_key, success_callback, error_callback)
  local temp_file = vim.fn.tempname() .. ".png"
  local rsvg_cmd = vim.deepcopy(M.rsvg_cmd)
  vim.list_extend(rsvg_cmd, { "-o", temp_file })

  vim.system(rsvg_cmd, { stdin = svg_string, text = true }, function(rsvg)
    if rsvg.code ~= 0 then
      handle_rsvg_error(error_callback, temp_file, rsvg)
      return
    end

    vim.schedule(function()
      log.debug(string.format('[Yatr CLI] Setting cache key: %s', cache_key))
      file_cache:set(cache_key, temp_file)
      log.debug(string.format('[Yatr CLI] Successfully cached image: %s', temp_file))
      pcall(success_callback, temp_file)
    end)
  end)
end

local function run_mathjax(tex_string, cache_key, success_callback, error_callback)
  local mathjax_cmd = vim.deepcopy(M.mathjax_cmd)
  vim.list_extend(mathjax_cmd, { "--tex", tex_string })

  log.debug(string.format('[Yatr CLI] Mathjax cmd: %s', vim.inspect(mathjax_cmd)))

  vim.system(mathjax_cmd, { text = true }, function(mathjax)
    if mathjax.code ~= 0 then
      handle_mathjax_error(error_callback, mathjax)
      return
    end

    local svg_string = trim_string(mathjax.stdout)
    vim.schedule(function()
      convert_svg_to_png(svg_string, cache_key, success_callback, error_callback)
    end)
  end)
end

-- Convert TeX to PNG using the MathJax CLI script
-- @param tex_string string: The LaTeX string to convert
-- @param tex_base64 string: Base64 encoded LaTeX string (used as cache key)
-- @param success_callback function: A function to call when the conversion is successful
-- @param error_callback function: A function to call when the conversion fails
-- @return nil
function M.convert_tex_to_png(tex_string, tex_base64, success_callback, error_callback)
  if not M.ok then
    return
  end

  if not tex_string or tex_string == "" then
    log.error("texString cannot be empty")
    return
  end

  if not tex_base64 or tex_base64 == "" then
    log.error("tex_base64 cannot be empty")
    return
  end

  local cache_key = tex_base64
  log.debug(string.format('[Yatr CLI] Cache key: %s', cache_key))

  local cached_file = file_cache:get(cache_key)
  if cached_file then
    vim.schedule(function()
      pcall(success_callback, cached_file)
    end)
    return
  end

  run_mathjax(tex_string, cache_key, success_callback, error_callback)
end

return M
