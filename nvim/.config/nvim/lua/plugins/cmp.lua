return {
  {
    "saghen/blink.cmp",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "giuxtaposition/blink-cmp-copilot",
    },
    version = "v0.*",
    opts = {
      keymap = {
        preset = "default",
        ['<CR>'] = { 'select_and_accept', 'fallback' },
      },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono"
      },
      sources = {
        default = function()
          local utils = require("utils")
          if utils.is_medium_file() then
            -- For larger files, use only essential sources
            return { "lsp", "path", "snippets" }
          else
            -- Full sources for smaller files
            return { "lsp", "path", "snippets", "buffer", "copilot" }
          end
        end,
        providers = {
          copilot = {
            name = "copilot",
            module = "blink-cmp-copilot",
            score_offset = 100,
            async = true,
          },
        },
      },
      cmdline = {
        sources = function()
          local type = vim.fn.getcmdtype()
          if type == "/" or type == "?" then return { "buffer" } end
          if type == ":" then return { "cmdline" } end
          return {}
        end,
      },
      completion = {
        accept = {
          create_undo_point = false,
          auto_brackets = {
            enabled = true,
          },
        },
        menu = {
          draw = {
            treesitter = { "lsp" },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
        },
      },
    },
    opts_extend = { "sources.default" }
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
}