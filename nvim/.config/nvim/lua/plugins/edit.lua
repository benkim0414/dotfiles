return {
  -- Fast Lua-based commenting (matches vim-commentary keymaps)
  {
    "echasnovski/mini.comment",
    event = "VeryLazy",
    opts = {
      options = {
        custom_commentstring = function()
          return require("ts_context_commentstring.internal").calculate_commentstring() or vim.bo.commentstring
        end,
      },
      mappings = {
        comment = "gc",         -- Toggle comment in both Normal and Visual modes
        comment_line = "gcc",   -- Toggle comment on current line
        comment_visual = "gc",  -- Toggle comment on selection
        textobject = "gc",      -- Define 'comment' textobject
      },
    },
  },
  
  -- Fast Lua-based surround operations (matches vim-surround keymaps)
  {
    "echasnovski/mini.surround",
    event = "VeryLazy",
    opts = {
      mappings = {
        add = "ys",             -- Add surrounding (matches vim-surround ys)
        delete = "ds",          -- Delete surrounding (matches vim-surround ds)  
        find = "gsf",           -- Find surrounding (to the right)
        find_left = "gsF",      -- Find surrounding (to the left)
        highlight = "gsh",      -- Highlight surrounding
        replace = "cs",         -- Replace surrounding (matches vim-surround cs)
        update_n_lines = "gsn", -- Update `n_lines`
      },
    },
  },
  
  -- Keep vim-repeat as many plugins depend on it
  "tpope/vim-repeat",
  
  -- Replace vim-unimpaired with mini.misc
  {
    "echasnovski/mini.misc",
    event = "VeryLazy",
    config = function()
      require("mini.misc").setup()
      -- Setup exact vim-unimpaired mappings
      vim.keymap.set("n", "[b", "<Cmd>bprevious<CR>", { desc = "Previous buffer" })
      vim.keymap.set("n", "]b", "<Cmd>bnext<CR>", { desc = "Next buffer" })
      vim.keymap.set("n", "[q", "<Cmd>cprevious<CR>", { desc = "Previous quickfix" })
      vim.keymap.set("n", "]q", "<Cmd>cnext<CR>", { desc = "Next quickfix" })
      vim.keymap.set("n", "[l", "<Cmd>lprevious<CR>", { desc = "Previous location" })
      vim.keymap.set("n", "]l", "<Cmd>lnext<CR>", { desc = "Next location" })
      vim.keymap.set("n", "[<Space>", "O<Esc>j", { desc = "Add blank line above" })
      vim.keymap.set("n", "]<Space>", "o<Esc>k", { desc = "Add blank line below" })
    end,
  },
  
  -- Auto-pair brackets and quotes
  {
    "echasnovski/mini.pairs",
    event = "VeryLazy",
    opts = {
      modes = { insert = true, command = true, terminal = false },
      -- skip autopair when next character is one of these
      skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
      -- skip autopair when the cursor is inside these treesitter nodes
      skip_ts = { "string" },
      -- skip autopair when next character is closing pair
      -- and there are more closing pairs than opening pairs
      skip_unbalanced = true,
      -- better deal with markdown code blocks
      markdown = true,
    },
  },
  
  -- Replace with register content
  "vim-scripts/ReplaceWithRegister",
  
  -- System clipboard integration
  "christoomey/vim-system-copy",
  
}