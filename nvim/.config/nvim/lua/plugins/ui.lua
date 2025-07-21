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
    dependencies = {
      'nvim-tree/nvim-web-devicons',
      'ThePrimeagen/harpoon'
    },
    config = function()
      vim.opt.termguicolors = true
      local utils = require("utils")
      local colors = require("catppuccin.palettes").get_palette()

      require("bufferline").setup {
        options = {
          numbers = function(opts)
            -- Get harpoon number for this buffer
            local harpoon_num = utils.get_harpoon_number_for_buffer(opts.id)

            if harpoon_num then
              -- Show harpoon number for pinned buffers
              return tostring(harpoon_num)
            end

            -- Return empty string for non-harpoon buffers
            return ""
          end,
          separator_style = "thin",
          show_buffer_close_icons = false,
          show_close_icon = false,
          always_show_bufferline = true,
        },
        highlights = {
          indicator_selected = {
            fg = colors.mauve,
            bg = colors.base,
          },
          indicator_visible = {
            fg = colors.overlay2,
            bg = colors.base,
          },
        },
      }
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
        { "<leader>s", group = "search" },
        { "<leader>t", group = "toggle" },
        { "<leader>w", group = "workspace/window" },
        { "<leader>1", desc = "Harpoon file 1" },
        { "<leader>2", desc = "Harpoon file 2" },
        { "<leader>3", desc = "Harpoon file 3" },
        { "<leader>4", desc = "Harpoon file 4" },
        { "gr", group = "lsp" },
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
