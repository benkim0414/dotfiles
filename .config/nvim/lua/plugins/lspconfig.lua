return {
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/nvim-cmp",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-vsnip",
      "hrsh7th/vim-vsnip",
    },
    config = function()
      local api = vim.api
      local fn = vim.fn
      local utils = require("utils")
      local nnoremap = utils.nnoremap

      local servers = {"lua_ls", "tsserver"}
      require("mason").setup()
      require("mason-lspconfig").setup {
        ensure_installed = servers,
        automatic_installation = true,
      }

      local function on_attach(client, bufnr)
        local buf_nnoremap = utils.make_keymap_fn("n", {bufnr = bufnr, noremap = ture, silent = true})
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
        end, opts)
      end

      local default_capabilities = vim.lsp.protocol.make_client_capabilities()
      local capabilities = require("cmp_nvim_lsp").default_capabilities(default_capabilities)

      local lspconfig = require("lspconfig")
      for _, lsp in pairs(servers) do
        lspconfig[lsp].setup {
          on_attach = on_attach,
          capabilities = capabilities,
          flags = {
            debounce_text_changes = 150,
          }
        }
      end

      nnoremap("<Space>e", "<Cmd>lua vim.diagnostic.open_float()<CR>")
      nnoremap("[d", "<Cmd>lua vim.diagnostic.goto_prev()<CR>")
      nnoremap("]d", "<Cmd>lua vim.diagnostic.goto_next()<CR>")
      nnoremap("<Space>q", "<Cmd>lua vim.diagnostic.setloclist()<CR>")

      local has_words_before = function()
        if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then return false end
        local line, col = unpack(api.nvim_win_get_cursor(0))
        return col ~= 0 and api.nvim_buf_get_text(0, line-1, 0, line-1, col, {})[1]:match("^%s*$") == nil
      end

      local function feedkey(key, mode)
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, true, true), mode, true)
      end

      local cmp = require("cmp")
      cmp.setup({
        snippet = {
          expand = function(args)
            fn["vsnip#anonymous"](args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({select = true}),
          ["<Tab>"] = vim.schedule_wrap(function(fallback)
            if cmp.visible() and has_words_before() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            elseif fn['vsnip#available'](1) == 1 then
              feedkey('<plug>(vsnip-expand-or-jump)', '')
            else
              fallback()
            end
          end),
          ["<S-Tab>"] = cmp.mapping(function()
            if cmp.visible() then
              cmp.select_prev_item()
            elseif fn["vsnip#jumpable"](-1) == 1 then
              feedkey("<Plug>(vsnip-jump-prev)", "")
            end
          end, {"i", "s"}),
        }),
        sources = cmp.config.sources({
          {name = "copilot"},
          {name = "nvim_lsp"},
          {name = "vsnip"},
          {name = "buffer"},
        }),
      })
    end,
  },
}
