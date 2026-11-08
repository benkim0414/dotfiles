return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = {
      "nvim-lua/plenary.nvim"
    },
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup()

      local function refresh_bufferline()
        vim.schedule(function()
          vim.cmd("redrawtabline")
        end)
      end

      vim.keymap.set("n", "<leader>a", function()
        harpoon:list():add()
        refresh_bufferline()
      end, { desc = "Add file to harpoon" })

      vim.keymap.set("n", "<leader>r", function()
        harpoon:list():remove()
        refresh_bufferline()
      end, { desc = "Remove file from harpoon" })

      vim.keymap.set("n", "<leader>c", function()
        harpoon:list():clear()
        refresh_bufferline()
      end, { desc = "Clear all files from harpoon" })

      vim.keymap.set("n", "<leader>1", function() harpoon:list():select(1) end, { desc = "Harpoon file 1" })
      vim.keymap.set("n", "<leader>2", function() harpoon:list():select(2) end, { desc = "Harpoon file 2" })
      vim.keymap.set("n", "<leader>3", function() harpoon:list():select(3) end, { desc = "Harpoon file 3" })
      vim.keymap.set("n", "<leader>4", function() harpoon:list():select(4) end, { desc = "Harpoon file 4" })

      local conf = require("telescope.config").values
      local function toggle_telescope(harpoon_files)
        local file_paths = {}
        for _, item in ipairs(harpoon_files.items) do
          table.insert(file_paths, item.value)
        end

        require("telescope.pickers").new({}, {
          prompt_title = "Harpoon",
          finder = require("telescope.finders").new_table({
            results = file_paths,
          }),
          previewer = conf.file_previewer({}),
          sorter = conf.generic_sorter({}),
        }):find()
      end

      vim.keymap.set("n", "<C-e>", function()
        toggle_telescope(harpoon:list())
      end, { desc = "Open harpoon window" })
    end,
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
    },
  },
  {
    "christoomey/vim-tmux-navigator",
    -- Keep this clone for `herdr plugin link`; the editor hook is pinned locally.
    dependencies = { { "paulbkim-dev/vim-herdr-navigation", branch = "master" } },
    lazy = false,
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    config = function()
      -- Local editor hook validates stale HERDR_BIN_PATH values after updates.
      -- The Herdr-side vim-herdr-navigation plugin still forwards these keys.
      require("herdr_navigation").setup()
      -- Keep tmux muscle memory for last-focused split. The local hook owns C-hjkl but
      -- has no "previous" action, so this uses the TmuxNavigate command (tmux, or
      -- wincmd fallback in plain vim); it does not cross into a herdr pane.
      vim.keymap.set("n", "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>",
        { silent = true, desc = "Navigate previous" })
    end,
  }
}
