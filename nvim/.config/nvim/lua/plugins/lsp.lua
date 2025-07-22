return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      local lspconfig = require("lspconfig")

      local default_capabilities = vim.lsp.protocol.make_client_capabilities()
      -- Update for blink.cmp compatibility
      local capabilities = require("blink.cmp").get_lsp_capabilities(default_capabilities)

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

          -- Use Neovim's default LSP keymaps
          vim.keymap.set("n", "grn", vim.lsp.buf.rename, { buffer = ev.buf, desc = "LSP rename" })
          vim.keymap.set({ "n", "v" }, "gra", vim.lsp.buf.code_action, { buffer = ev.buf, desc = "LSP code action" })
          vim.keymap.set("n", "grr", vim.lsp.buf.references, { buffer = ev.buf, desc = "LSP references" })
          vim.keymap.set("n", "gri", vim.lsp.buf.implementation, { buffer = ev.buf, desc = "LSP implementation" })
          vim.keymap.set("n", "grt", vim.lsp.buf.type_definition, { buffer = ev.buf, desc = "LSP type definition" })
          vim.keymap.set("n", "gO", vim.lsp.buf.document_symbol, { buffer = ev.buf, desc = "LSP document symbols" })
          
          -- Keep some common non-default keymaps that are widely used
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = ev.buf, desc = "LSP go to definition" })
          vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = ev.buf, desc = "LSP hover" })
          
          -- Format keymap (not part of defaults but commonly needed)
          vim.keymap.set("n", "<Space>f", function()
            vim.lsp.buf.format { async = true }
          end, { buffer = ev.buf, desc = "LSP format" })
        end,
      })

      require("mason-lspconfig").setup {
        handlers = {
          function(server_name)
            lspconfig[server_name].setup {
              capabilities = capabilities,
              flags = {
                debounce_text_changes = 300,  -- Increased from 150ms for better performance
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
              capabilities = capabilities,
              settings = {
                Lua = {
                  runtime = {
                    version = "LuaJIT",
                  },
                  diagnostics = {
                    globals = { "vim" },
                  },
                  workspace = {
                    library = vim.api.nvim_get_runtime_file("", true),
                    checkThirdParty = false,
                  },
                  telemetry = {
                    enable = false,
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