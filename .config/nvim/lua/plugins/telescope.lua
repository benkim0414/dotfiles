return {
  {
    "nvim-telescope/telescope.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      {"nvim-telescope/telescope-fzf-native.nvim", build = "make"},
      'nvim-telescope/telescope-node-modules.nvim',
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
          file_ignore_patterns = {"node_modules"},
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
      nnoremap("<Leader>h", "<Cmd>Telescope help_tags<CR>")
      nnoremap("<Leader>n", "<Cmd>Telescope node_modules list<CR>")
    end,
  },
}
