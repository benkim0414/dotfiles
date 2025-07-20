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
    config = function()
      local wk = require("which-key")
      
      -- Register group descriptions for better keymap organization
      wk.add({
        { "<leader>f", group = "file" },
        { "<leader>g", group = "git" },
        { "<leader>h", group = "hunk" },
        { "<leader>l", group = "lsp" },
        { "<leader>s", group = "search" },
        { "<leader>t", group = "toggle" },
        { "<leader>w", group = "workspace/window" },
        { "<leader>1", desc = "Harpoon file 1" },
        { "<leader>2", desc = "Harpoon file 2" },
        { "<leader>3", desc = "Harpoon file 3" },
        { "<leader>4", desc = "Harpoon file 4" },
      })
    end,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    event = "VeryLazy",
    main = "ibl",
    opts = {
      scope = { show_start = false, show_end = false },
    },
  }
}