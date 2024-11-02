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

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = ev.buf, desc = "Go to declaration" })
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = ev.buf, desc = "Go to definition" })
          vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = ev.buf })
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { buffer = ev.buf, desc = "Go to implementation" })
          vim.keymap.set("n", "<Space>wa", vim.lsp.buf.add_workspace_folder,
            { buffer = ev.buf, desc = "Add workspace folder" })
          vim.keymap.set("n", "<Space>wr", vim.lsp.buf.remove_workspace_folder,
            { buffer = ev.buf, desc = "Remove workspace folder" })
          vim.keymap.set("n", "<Space>wl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, { buffer = ev.buf, desc = "List workspace folders" })
          vim.keymap.set("n", "<Space>D", vim.lsp.buf.type_definition, { buffer = ev.buf, desc = "Type definition" })
          vim.keymap.set("n", "<Space>rn", vim.lsp.buf.rename, { buffer = ev.buf, desc = "Rename" })
          vim.keymap.set({ "n", "v" }, "<Space>ca", vim.lsp.buf.code_action, { buffer = ev.buf, desc = "Code action" })
          vim.keymap.set("n", "<Space>r", vim.lsp.buf.references, { buffer = ev.buf, desc = "References" })
          vim.keymap.set("n", "<Space>f", function()
            vim.lsp.buf.format { async = true }
          end, { buffer = ev.buf, desc = "Format" })
        end,
      })

      require("mason").setup()
      require("mason-lspconfig").setup {
        ensure_installed = { "gopls", "lua_ls", "pyright", "ts_ls" },
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
          gopls = function()
            lspconfig.gopls.setup {
              capabilities = capabilities,
              settings = {
                gopls = {
                  gofumpt = true,
                  completeUnimported = true,
                  usePlaceholders = true,
                  analyses = {
                    unusedparams = true,
                  }
                }
              }
            }
          end,
          ["lua_ls"] = function()
            lspconfig.lua_ls.setup {
              settings = {
                Lua = {
                  diagnostics = {
                    globals = { "vim" },
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
