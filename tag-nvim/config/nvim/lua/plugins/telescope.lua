return {
  {
    "nvim-telescope/telescope.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {"nvim-telescope/telescope-fzf-native.nvim", build = "make"},
    },
    config = function()
      local config = require("telescope.config")
      local vimgrep_arguments = {unpack(config.values.vimgrep_arguments)}
      table.insert(vimgrep_arguments, "--hidden")
      table.insert(vimgrep_arguments, "--glob")
      table.insert(vimgrep_arguments, "!**/.git/*")
      table.insert(vimgrep_arguments, "--trim")

      require("telescope").setup {
        defaults = {
          mappings = {
            i = {
              ["<Esc>"] = require("telescope.actions").close,
            },
          },
          vimgrep_arguments = vimgrep_arguments,
        },
        pickers = {
          find_files = {
            find_command = {"rg", "--files", "--hidden", "--glob", "!**/.git/*"},
          },
        },
      }

      require("telescope").load_extension("fzf")

      local nnoremap = require("utils").nnoremap
      nnoremap("<C-p>", "<Cmd>Telescope find_files<CR>")
      nnoremap("<Leader>g", "<Cmd>Telescope git_files<CR>")
      nnoremap("<Leader>rg", "<Cmd>Telescope live_grep<CR>")
      nnoremap("<Leader>B", "<Cmd>Telescope buffers<CR>")
      nnoremap("<Leader>ht", "<Cmd>Telescope help_tags<CR>")
    end,
  },
}
