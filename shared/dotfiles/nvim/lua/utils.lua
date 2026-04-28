-- ~/.config/nvim/lua/utils.lua
local M = {}

-- Port of your VisualSelection function
function M.visual_selection()
  local old_reg = vim.fn.getreg('@')
  local old_reg_type = vim.fn.getregtype('@')

  vim.cmd('normal! "vy"') -- Yank the visual selection into the 'v' register
  local selection = vim.fn.getreg('v')
  selection = vim.fn.escape(selection, '\\/.*$') -- Escape special characters
  selection = selection:gsub('\n$', '') -- Remove trailing newline

  vim.fn.setreg('/', selection) -- Set the search register
  vim.fn.setreg('@', old_reg, old_reg_type) -- Restore the old default register
end

-- Port of your BufcloseCloseIt function
function M.bclose()
  local current_buf = vim.api.nvim_get_current_buf()
  local alternate_buf = vim.fn.bufnr('#')

  if alternate_buf > 0 and vim.fn.buflisted(alternate_buf) == 1 then
    vim.cmd.buffer('#')
  else
    vim.cmd.bnext()
  end

  -- If we are still in the same buffer, it means it was the last one. Open a new one.
  if vim.api.nvim_get_current_buf() == current_buf then
    vim.cmd.new()
  end

  -- Now delete the original buffer if it's still listed
  if vim.fn.buflisted(current_buf) == 1 then
    vim.cmd.bdelete(current_buf)
  end
end


return M
