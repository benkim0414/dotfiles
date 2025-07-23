return {
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    keys = {
      { "<C-p>",      "<Cmd>Telescope find_files<CR>",          desc = "Find Files" },
      { "<Leader>/",  "<Cmd>Telescope live_grep<CR>",           desc = "Grep" },
      { "<Leader>:",  "<Cmd>Telescope command_history<CR>",     desc = "Command History" },
      { "<Leader>gC", "<Cmd>Telescope git_commits<CR>",         desc = "Git Commits (browse)" },
      { "<Leader>gS", "<Cmd>Telescope git_status<CR>",          desc = "Git Status (browse)" },
      { "<Leader>s",  "<Cmd>Telescope registers<CR>",           desc = "Registers" },
      { "<Leader>sb", "<Cmd>Telescope buffers<CR>",             desc = "Buffer" },
      { "<Leader>sc", "<Cmd>Telescope command_history<CR>",     desc = "Command History" },
      { "<Leader>sd", "<Cmd>Telescope diagnostics bufnr=0<CR>", desc = "Document Diagnostics" },
      { "<Leader>sh", "<Cmd>Telescope help_tags<CR>",           desc = "Help Pages" },
      { "<Leader>sq", "<Cmd>Telescope quickfix<CR>",            desc = "Quickfix List" },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")

      telescope.setup({
        defaults = {
          mappings = {
            i = {
              ["<Esc>"] = actions.close,
            },
          },
        },
        pickers = {
          find_files = {
            find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
          },
        },
      })
    end,
  }
}
