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

      nnoremap("<leader>le", "<Cmd>lua vim.diagnostic.open_float()<CR>", { desc = "Show line diagnostics" })
      nnoremap("[d", "<Cmd>lua vim.diagnostic.goto_prev()<CR>", { desc = "Previous diagnostic" })
      nnoremap("]d", "<Cmd>lua vim.diagnostic.goto_next()<CR>", { desc = "Next diagnostic" })
      nnoremap("<leader>lq", "<Cmd>lua vim.diagnostic.setloclist()<CR>", { desc = "Diagnostics to loclist" })

      local function has_words_before()
        unpack = unpack or table.unpack
        if api.nvim_buf_get_option(0, "buftype") == "prompt" then
          return false
        end
        local line, col = unpack(api.nvim_win_get_cursor(0))
        return col ~= 0 and api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
      end

      local function feedkey(key, mode)
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, true, true), mode, true)
      end

      local cmp = require("cmp")
      local utils = require("utils")
      
      -- Dynamic sources based on file size for performance
      local function get_sources()
        if utils.is_medium_file() then
          -- For larger files, use only essential sources to improve performance
          return cmp.config.sources({
            { name = "nvim_lsp" },
            { name = "path" },
            { name = "vsnip" },
          })
        else
          -- Full sources for smaller files
          return cmp.config.sources({
            { name = "copilot" },
            { name = "nvim_lsp" },
            { name = "buffer" },
            { name = "path" },
            { name = "vsnip" },
            { name = "nvim_lua" },
          })
        end
      end
      
      cmp.setup({
        performance = {
          debounce = 300,
          throttle = 60,
          fetching_timeout = 200,
          confirm_resolve_timeout = 80,
          async_budget = 1,
          max_view_entries = 200,
        },
        snippet = {
          expand = function(args)
            fn["vsnip#anonymous"](args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = vim.schedule_wrap(function(fallback)
            if cmp.visible() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Select })
            elseif fn["vsnip#available"](1) == 1 then
              feedkey("<plug>(vsnip-expand-or-jump)", "")
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function()
            if cmp.visible() then
              cmp.select_prev_item()
            elseif fn["vsnip#jumpable"](-1) == 1 then
              feedkey("<Plug>(vsnip-jump-prev)", "")
            end
          end, { "i", "s" }),
        }),
        sources = get_sources(),
      })

      cmp.setup.cmdline("/", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = {
          { name = "buffer" },
        },
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" }
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
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({
        suggestion = { enabled = false },
        panel = { enabled = false },
      })
    end,
  },
  {
    "zbirenbaum/copilot-cmp",
    config = function()
      require("copilot_cmp").setup()
    end
  }
}