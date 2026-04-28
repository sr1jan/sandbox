-- ~/.config/nvim/lua/plugins/lsp.lua

vim.diagnostic.config({
  virtual_text = true,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})


return {
  -- LSP-related plugins
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- These are required for the setup below
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },

      -- Useful status updates for LSP
      { 'j-hui/fidget.nvim',                opts = {} },

      -- Additional completion capabilities
      { 'hrsh7th/cmp-nvim-lsp' },
    },
    config = function()
      -- 1. Define the on_attach function.
      -- This is our custom function that will run every time a language server attaches to a buffer
      local on_attach = function(client, bufnr)
        -- This is where we set our keymaps for LSP actions
        local opts = { buffer = bufnr, remap = false }

        vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
        vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, opts)
        vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, opts)
        vim.keymap.set({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, opts)

        -- You can add more keymaps here if you like
      end

      -- 2. Setup mason.nvim
      require("mason").setup()

      -- 3. Setup mason-lspconfig.nvim
      -- This is the key part that bridges Mason with lspconfig.
      -- It ensures that any server you install with Mason is automatically set up by lspconfig.
      require("mason-lspconfig").setup({
        -- A list of servers to automatically install if they're not already installed
        ensure_installed = { "lua_ls", "ruff", "pyright", "rust_analyzer", "ts_ls" },
        -- This is where we connect the on_attach function to lspconfig
        handlers = {
          function(server_name) -- The default handler
            require("lspconfig")[server_name].setup({
              on_attach = on_attach,
            })
          end,
          -- You can add custom handlers for specific servers here
          ["lua_ls"] = function()
            require("lspconfig").lua_ls.setup({
              on_attach = on_attach,
              settings = {
                Lua = {
                  diagnostics = { globals = { "vim" } },
                },
              },
            })
          end,
        },
      })
    end,
  },

  -- Autocompletion Engine (nvim-cmp)
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      -- Snippet engine & its source for nvim-cmp
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",

      -- Other useful completion sources
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      -- nvim-cmp setup
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-d>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
        }),
        -- The order of sources matters!
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
