return {
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "hrsh7th/cmp-vsnip",
      "hrsh7th/vim-vsnip",
    },
    config = function()
      local api = vim.api
      local fn = vim.fn
      local utils = require("utils")
      local nnoremap = utils.nnoremap

      nnoremap("<Space>e", "<Cmd>lua vim.diagnostic.open_float()<CR>")
      nnoremap("[d", "<Cmd>lua vim.diagnostic.goto_prev()<CR>")
      nnoremap("]d", "<Cmd>lua vim.diagnostic.goto_next()<CR>")
      nnoremap("<Space>q", "<Cmd>lua vim.diagnostic.setloclist()<CR>")

      local function has_words_before()
        unpack = unpack or table.unpack
        if api.nvim_buf_get_option(0, "buftype") == "prompt" then
          return false
        end
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
            if cmp.visible() then
              cmp.select_next_item({behavior = cmp.SelectBehavior.Select})
            elseif fn["vsnip#available"](1) == 1 then
              feedkey("<plug>(vsnip-expand-or-jump)", "")
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, {"i", "s"}),
          ["<S-Tab>"] = cmp.mapping(function()
            if cmp.visible() then
              cmp.select_prev_item()
            elseif fn["vsnip#jumpable"](-1) == 1 then
              feedkey("<Plug>(vsnip-jump-prev)", "")
            end
          end, {"i", "s"}),
        }),
        sources = cmp.config.sources({
          {name = "nvim_lsp"},
          {name = "buffer"},
          {name = "path"},
          {name = "vsnip"},
          {name = "nvim_lua"},
        }),
      })

      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          {name = "buffer"},
        },
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          {name = "path"}
        }, {
          {
            name = "cmdline",
            option = {
              ignore_cmds = { "Man", "!" },
            },
          },
        })
      })
    end,
  },
}
