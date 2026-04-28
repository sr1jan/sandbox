-- ~/.config/nvim/lua/options.lua
local opt = vim.opt -- for conciseness

-- ==> General
opt.history = 500
opt.autoread = true

-- ==> VIM user interface
opt.relativenumber = true -- Shows relative line numbers
opt.number = true         -- And the absolute line number of the current line
opt.so = 7                -- Keep 7 lines of context around the cursor
opt.wildmenu = true
opt.ruler = true
opt.cmdheight = 1
opt.hidden = true -- A buffer becomes hidden when it is abandoned
opt.wildignore:append('*.o,*.obj,*.pyc,*/.git/*,*/.hg/*,*/.svn/*,*/.DS_Store')


-- ==> Searching
opt.ignorecase = true -- Ignore case when searching
opt.smartcase = true  -- Be smart about case
opt.hlsearch = true   -- Highlight search results
opt.incsearch = true  -- Makes search act like search in modern browsers
opt.lazyredraw = true -- Don't redraw while executing macros

-- ==> Backspace and Wrapping
opt.backspace = 'eol,start,indent'
opt.whichwrap:append('<,>,h,l')

-- ==> Brackets and Matching
opt.showmatch = true
opt.matchtime = 2

-- ==> Errors

-- ==> Folding
opt.foldmethod = 'indent'
opt.foldcolumn = '0' -- No extra margin on the left
opt.foldenable = false -- Disable folding by default

-- ==> Colors and Fonts
opt.termguicolors = true
opt.background = 'dark'

-- ==> Encoding and File Formats
opt.encoding = 'utf8'
opt.ffs = 'unix,dos,mac'

-- ==> Files, backups and undo
-- Turn persistent undo on
opt.undodir = vim.fn.stdpath('data') .. '/undodir'
opt.undofile = true

-- ==> Text, tab and indent related
-- NOTE: Using values from your my_configs.vim which override basics.vim
opt.shiftwidth = 2
opt.tabstop = 2
opt.expandtab = true   -- Use spaces instead of tabs
opt.smarttab = true
opt.autoindent = true
opt.smartindent = true
opt.wrap = true
opt.textwidth = 500 -- This is very high, you might want to reduce to 80 or 120
opt.linebreak = true

-- ==> Status line
opt.laststatus = 2 -- Always show statusline

opt.switchbuf = 'useopen,usetab,newtab'
opt.showtabline = 2 -- This is the Lua equivalent of 'set stal=2'

-- List characters for better whitespace visibility
opt.list = false
opt.listchars = 'space:⋅,eol:↴'
