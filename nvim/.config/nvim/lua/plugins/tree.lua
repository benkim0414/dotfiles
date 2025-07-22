return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "MunifTanjim/nui.nvim",
  },
  keys = {
    { "<Leader>e", "<Cmd>Neotree toggle<CR>", desc = "Explorer" },
  },
  opts = {
    filesystem = {
      filtered_items = {
        visible = false,     -- Hide filtered items for better performance
        hide_dotfiles = false, -- Show dotfiles (needed for dotfiles repos)
        hide_gitignored = true, -- Hide git-ignored files for faster scanning
        hide_hidden = false,  -- Show hidden files (needed for dotfiles repos)
        hide_by_name = {
          "node_modules",
          ".git",
          ".DS_Store",
          "thumbs.db",
        },
        hide_by_pattern = {
          "*.tmp",
          "*.cache",
        },
        always_show = {
          ".gitignore",
          ".env.example",
        },
        never_show = {
          ".DS_Store",
          "thumbs.db",
        },
      },
      scan_mode = "fast", -- Use fast scanning for better performance
      use_libuv_file_watcher = true, -- Enable file watching for better responsiveness
    },
    window = {
      width = 30, -- Smaller width for better screen usage
      mappings = {
        ["H"] = "toggle_hidden", -- Quick toggle for hidden files when needed
      },
    },
  },
}
