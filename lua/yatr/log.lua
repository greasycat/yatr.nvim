local M = {}

M.WRITE_LEVEL = "DEBUG"

local LOG_FILE = "/tmp/yalr.log"

-- Log level constants
M.levels = {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

-- Helper function to write log to file
local function write_log(level, message)
  if level < M.WRITE_LEVEL then
    return
  end

  local timestamp = os.date("%Y-%m-%dT%H:%M:%S.000Z")
  local log_entry = string.format("[%s] [%s] %s\n", timestamp, level, message)

  -- Safely write to log file (append mode)
  local ok, err = pcall(function()
    local file = io.open(LOG_FILE, "a")
    if file then
      file:write(log_entry)
      file:close()
    end
  end)

  -- Silently fail if we can't write to log file
  if not ok then
    -- Don't notify to avoid recursion
  end
end

-- Log functions for each level
function M.debug(message)
  write_log(M.levels.DEBUG, message)
end

function M.info(message)
  write_log(M.levels.INFO, message)
end

function M.warn(message)
  write_log(M.levels.WARN, message)
end

function M.error(message)
  write_log(M.levels.ERROR, message)
end

-- Convenience function that accepts vim.log.levels for compatibility
function M.log(level, message)
  if level == vim.log.levels.DEBUG then
    M.debug(message)
  elseif level == vim.log.levels.INFO then
    M.info(message)
  elseif level == vim.log.levels.WARN then
    M.warn(message)
  elseif level == vim.log.levels.ERROR then
    M.error(message)
  else
    -- Default to INFO if level is unknown
    M.info(message)
  end
end

return M
