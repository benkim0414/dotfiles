return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
    config = function()
      local api = vim.api
      local utils = require("utils")
      local lspconfig = require("lspconfig")

      local function on_attach(_, bufnr)
        local buf_nnoremap = utils.make_keymap_fn("n", {bufnr = bufnr, noremap = true, silent = true})
        api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")
        buf_nnoremap("gD", "<Cmd>lua vim.lsp.buf.declaration()<CR>")
        buf_nnoremap("gd", "<Cmd>lua vim.lsp.buf.definition()<CR>")
        buf_nnoremap("K", "<Cmd>lua vim.lsp.buf.hover()<CR>")
        buf_nnoremap("gi", "<Cmd>lua vim.lsp.buf.implementation()<CR>")
        buf_nnoremap("<Space>wa", "<Cmd>lua vim.lsp.buf.add_workspace_folder()<CR>")
        buf_nnoremap("<Space>wr", "<Cmd>lua vim.lsp.buf.remove_workspace_folder()<CR>")
        buf_nnoremap("<Space>wl", "<Cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>")
        buf_nnoremap("<Space>D", "<Cmd>lua vim.lsp.buf.type_definition()<CR>")
        buf_nnoremap("<Space>rn", "<Cmd>lua vim.lsp.buf.rename()<CR>")
        buf_nnoremap("<Space>ca", "<Cmd>lua vim.lsp.buf.code_action()<CR>")
        buf_nnoremap("gr", "<Cmd>lua vim.lsp.buf.references()<CR>")
        buf_nnoremap("<Space>f", function()
          vim.lsp.buf.format {async = true}
        end)
      end

      local default_capabilities = vim.lsp.protocol.make_client_capabilities()
      local capabilities = require("cmp_nvim_lsp").default_capabilities(default_capabilities)

      require("mason").setup()
      require("mason-lspconfig").setup {
        ensure_installed = {"lua_ls", "tsserver"},
        automatic_installation = true,
        handlers = {
          function(server_name)
            lspconfig[server_name].setup {
              on_attach = on_attach,
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
