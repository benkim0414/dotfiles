return {
  {
    "nvim-lualine/lualine.nvim",
    dependencies = 'tpope/vim-fugitive',
    config = function()
      require("lualine").setup {
        options = {
          theme = "catppuccin",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },
        sections = {
          lualine_b = {
            { "FugitiveHead", icons_enabled = true, icon = "" },
          },
          lualine_c = {
            {
              "filename",
              path = 1, -- 0: just filename, 1: relative path, 2: absolute path, 3: absolute path with tilde
              symbols = {
                readonly = "[RO]",
              },
            },
            { "diff" },
          },
          lualine_x = {
            {
              "diagnostics",
              symbols = { error = 'E', warn = 'W', info = 'I', hint = 'H' },
            }
          },
        },
      }
    end,
  },
  {
    'akinsho/bufferline.nvim',
    version = "*",
    dependencies = 'nvim-tree/nvim-web-devicons',
    config = function()
      vim.opt.termguicolors = true
      require("bufferline").setup{}
    end,
  },
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      cmdline = {
        format = {
          cmdline = { pattern = "^:", icon = ":", lang = "vim" },
          search_down = { kind = "search", pattern = "^/", icon = "/", lang = "regex" },
          search_up = { kind = "search", pattern = "^%?", icon = "?", lang = "regex" },
        },
      },
      messages = {
        enabled = false,
      },
      notify = {
        enabled = false,
      },
      lsp = {
        message = {
          enabled = false,
        },
      },
    },
    dependencies = {
      "MunifTanjim/nui.nvim",
    }
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    keys = {
      {
        "<Leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    opts = {
      scope = { show_start = false, show_end = false },
    },
  }
}