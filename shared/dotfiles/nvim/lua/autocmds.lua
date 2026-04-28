-- ~/.config/nvim/lua/autocmds.lua

local group = vim.api.nvim_create_augroup('MyAutocmds', { clear = true })
local autocmd = vim.api.nvim_create_autocmd

-- Return to last edit position when opening files
autocmd('BufReadPost', {
  group = group,
  pattern = '*',
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    if mark[1] > 1 and mark[1] <= vim.api.nvim_buf_line_count(0) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

-- Reload my_configs.vim when saved (now points to plugins file)
-- autocmd('BufWritePost', {
--   group = group,
--   pattern = vim.fn.expand('~/.config/nvim/**/*.lua'),
--   command = 'source %'
-- })

-- Clean trailing whitespace on save
autocmd('BufWritePre', {
  group = group,
  pattern = { '*.txt', '*.js', '*.py', '*.wiki', '*.sh', '*.coffee' },
  command = [[%s/\s\+$//e]],
})

-- ==> Filetype-Specific Autocommands

-- Python
autocmd('FileType', {
  pattern = 'python',
  group = group,
  callback = function()
    vim.g.python_highlight_all = 1
    vim.cmd('syntax keyword pythonDecorator True None False self')
    vim.bo.cindent = true
    vim.cmd('setlocal cinkeys-=0#')
    vim.cmd('setlocal indentkeys-=0#')
    vim.keymap.set('i', '$r', 'return', { buffer = true })
    vim.keymap.set('i', '$i', 'import', { buffer = true })
    vim.keymap.set('i', '$p', 'print', { buffer = true })
  end,
})

-- Jinja and Mako
autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.jinja',
  command = 'set syntax=htmljinja',
  group = group,
})
autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = '*.mako',
  command = 'set filetype=mako',
  group = group,
})

-- JavaScript
autocmd('FileType', {
  pattern = 'javascript',
  group = group,
  callback = function()
    vim.wo.fen = true       -- ✅ Corrected to use vim.wo for a window-local option
    vim.bo.nocindent = true -- This one is correct, as 'cindent' is a buffer-local option
    vim.keymap.set('i', '<c-t>', '$log();<esc>hi', { buffer = true })
    vim.keymap.set('i', '<c-a>', 'alert();<esc>hi', { buffer = true })
    vim.keymap.set('i', '$r', 'return', { buffer = true })
  end,
})

-- TypeScript
autocmd({ 'BufNewFile', 'BufRead' }, {
  pattern = { '*.ts', '*.tsx' },
  command = 'setlocal filetype=typescript.tsx',
  group = group,
})

-- Git Commit
autocmd('FileType', {
  pattern = 'gitcommit',
  callback = function()
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
  end,
  group = group,
})

-- Twig
autocmd('BufRead', {
  pattern = '*.twig',
  command = 'set syntax=html filetype=html',
  group = group,
})

-- Track last active tab
autocmd('TabLeave', {
  group = group,
  pattern = '*',
  callback = function()
    vim.g.lasttab = vim.fn.tabpagenr()
  end,
})


-- Custom surround mapping for Mako files
autocmd('FileType', {
  pattern = 'mako',
  callback = function()
    vim.keymap.set('v', 'Si', 'S"i${ _(<esc>2f"a) }<esc>', { buffer = true, desc = 'Surround with gettext' })
  end,
  group = group,
})


-- Custom prompt
vim.api.nvim_create_autocmd("User", {
  pattern = "ToggleMyPrompt",
  callback = function() require("avante.config").override({ system_prompt = "MY CUSTOM SYSTEM PROMPT" }) end,
})

vim.keymap.set("n", "<leader>am", function() vim.api.nvim_exec_autocmds("User", { pattern = "ToggleMyPrompt" }) end,
  { desc = "avante: toggle my prompt" })
