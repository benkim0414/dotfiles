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

      require("mason").setup()
      require("mason-lspconfig").setup {
        ensure_installed = {"lua_ls", "pyright"},
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
