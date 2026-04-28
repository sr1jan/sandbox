-- ~/.config/nvim/lua/keymaps.lua
local utils = require('utils')
local map = vim.keymap.set

-- General Mappings
map('n', '<leader>w', ':w!<CR>', { silent = true, desc = 'Save with !' })

-- Clipboard mappings for macOS (ensure pbcopy/pbpaste are available)
map('v', '<C-c>', ':w !pbcopy<CR><CR>', { silent = true, desc = 'Copy to system clipboard' })
map('n', '<C-v>', ':r !pbpaste<CR><CR>', { silent = true, desc = 'Paste from system clipboard' })

-- Sudo write
vim.api.nvim_create_user_command('W', 'w !sudo tee % > /dev/null', {})

-- Search Mappings
map({ 'n', 'v' }, '<Space>', '/', { desc = 'Search forward' })
map({ 'n', 'v' }, '<C-Space>', '?', { desc = 'Search backward' })
map('n', '<leader><CR>', ':noh<CR>', { silent = true, desc = 'Clear search highlight' })
map('v', '*', function()
  utils.visual_selection()
  vim.cmd('normal! /<CR>')
end, { silent = true, desc = 'Search for visual selection' })
map('v', '#', function()
  utils.visual_selection()
  vim.cmd('normal! ?<CR>')
end, { silent = true, desc = 'Search backwards for visual selection' })

-- Window Navigation
map('n', '<C-j>', '<C-W>j', { desc = 'Move to window below' })
map('n', '<C-k>', '<C-W>k', { desc = 'Move to window above' })
map('n', '<C-h>', '<C-W>h', { desc = 'Move to window left' })
map('n', '<C-l>', '<C-W>l', { desc = 'Move to window right' })

-- Buffer Management
map('n', '<leader>l', ':bnext<CR>', { silent = true, desc = 'Next buffer' })
map('n', '<leader>h', ':bprevious<CR>', { silent = true, desc = 'Previous buffer' })
map('n', '<leader>bd', utils.bclose, { desc = 'Close buffer without closing window' })
map('n', '<leader>ba', ':bufdo bdelete<CR>', { silent = true, desc = 'Close all buffers' })

-- Open new tab in current directory
map('n', '<leader>te', ':tabedit %:p:h/<CR>', { desc = 'New tab in current directory' })
map('n', '<leader>tl', ':tabnext <c-r>=g:lasttab<CR><CR>', { desc = 'Toggle to last active tab' })


-- Change CWD to current file's directory
map('n', '<leader>cd', ':cd %:p:h<CR>:pwd<CR>', { desc = 'Change CWD to file directory' })

-- Editing Mappings
map('n', '0', '^', { desc = 'Move to first non-blank character' })

-- Move lines up/down
map('n', '<M-j>', 'mz:m+<CR>`z', { desc = 'Move line down' })
map('n', '<M-k>', 'mz:m-2<CR>`z', { desc = 'Move line up' })
map('v', '<M-j>', ":m'>+<CR>`<my`>mzgv`yo`z", { desc = 'Move selection down' })
map('v', '<M-k>', ":m'<-2<CR>`>my`<mzgv`yo`z", { desc = 'Move selection up' })

-- Spell Checking
map('n', '<leader>ss', ':setlocal spell!<CR>', { desc = 'Toggle spell check' })
map('n', '<leader>sn', ']s', { desc = 'Next spelling error' })
map('n', '<leader>sp', '[s', { desc = 'Previous spelling error' })
map('n', '<leader>sa', 'zg', { desc = 'Add word to dictionary' })
map('n', '<leader>s?', 'z=', { desc = 'Spelling suggestions' })

-- Misc
map('n', '<leader>m', 'mmHmt:%s/<C-V><cr>//ge<cr>`tzt`m', { desc = 'Remove Windows ^M characters' })
map('n', '<leader>q', ':e ~/buffer<CR>', { desc = 'Open scratch buffer' })
map('n', '<leader>x', ':e ~/buffer.md<CR>', { desc = 'Open markdown scratch buffer' })
map('n', '<leader>pp', ':setlocal paste!<CR>', { desc = 'Toggle paste mode' })

-- Fast editing of vim configs
map('n', '<leader>e', ':e ~/.config/nvim/lua/plugins/init.lua<CR>', { desc = 'Edit plugins config' })

-- Parenthesis/bracket helpers from extended.vim
map('v', '$1', '<esc>`>a)<esc>`<i(<esc>', { desc = 'Surround with ()' })
map('v', '$2', '<esc>`>a]<esc>`<i[<esc>', { desc = 'Surround with []' })
map('v', '$3', '<esc>`>a}<esc>`<i{<esc>', { desc = 'Surround with {}' })
map('v', '$$', '<esc>`>a"<esc>`<i"<esc>', { desc = 'Surround with ""' })
map('v', '$q', "<esc>`>a'<esc>`<i'<esc>", { desc = 'Surround with \'\'' })

map('i', '$1', '()<esc>i')
map('i', '$2', '[]<esc>i')
map('i', '$3', '{}<esc>i')
map('i', '$4', '{<esc>o}<esc>O')
map('i', '$q', "''<esc>i")
map('i', '$e', '""<esc>i')



-- Add these keymaps to the 'Search Mappings' section
map('v', '*', function()
  utils.visual_selection()
  vim.cmd('normal! /<CR>')
end, { silent = true, desc = 'Search for visual selection' })

map('v', '#', function()
  utils.visual_selection()
  vim.cmd('normal! ?<CR>')
end, { silent = true, desc = 'Search backwards for visual selection' })

vim.cmd('iab xdate <c-r>=strftime("%d/%m/%y %H:%M:%S")<cr>')
