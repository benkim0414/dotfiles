return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      local lspconfig = require("lspconfig")

      local default_capabilities = vim.lsp.protocol.make_client_capabilities()
      local capabilities = require("cmp_nvim_lsp").default_capabilities(default_capabilities)

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspConfig', {}),
        callback = function(ev)
          vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

          local opts = {buffer = ev.buf}
          vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, opts)
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, opts)
          vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, opts)
          vim.keymap.set('n', '<Space>wa', vim.lsp.buf.add_workspace_folder, opts)
          vim.keymap.set('n', '<Space>wr', vim.lsp.buf.remove_workspace_folder, opts)
          vim.keymap.set('n', '<Space>wl', function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, opts)
          vim.keymap.set('n', '<Space>D', vim.lsp.buf.type_definition, opts)
          vim.keymap.set('n', '<Space>rn', vim.lsp.buf.rename, opts)
          vim.keymap.set({'n', 'v'}, '<Space>ca', vim.lsp.buf.code_action, opts)
          vim.keymap.set('n', 'gr', vim.lsp.buf.references, opts)
          vim.keymap.set('n', '<Space>f', function()
            vim.lsp.buf.format {async = true}
          end, opts)
        end,
      })

      require("mason").setup()
      require("mason-lspconfig").setup {
        ensure_installed = {"lua_ls", "tsserver"},
        automatic_installation = true,
        handlers = {
          function(server_name)
            lspconfig[server_name].setup {
              capabilities = capabilities,
              flags = {
                debounce_text_changes = 150,
              },
            }
          end,
          ["lua_ls"] = function()
             lspconfig.lua_ls.setup {
               settings = {
                 Lua = {
                   diagnostics = {
                       globals = {"vim"},
                   },
                 },
               },
             }
          end,
        },
      }
    end,
  },
}
