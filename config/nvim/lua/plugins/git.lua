return {
  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "sindrets/diffview.nvim",
      "ibhagwan/fzf-lua",
    },
    config = function()
      local nnoremap = require("utils").nnoremap
      require("neogit").setup {
        kind = "split_above",
      }

      nnoremap("<Leader>gg", "<Cmd>Neogit<CR>")
      nnoremap("<Leader>gc", "<Cmd>Neogit commit<CR>")
      nnoremap("<Leader>gl", "<Cmd>Neogit pull<CR>")
      nnoremap("<Leader>gp", "<Cmd>Neogit push<CR>")
    end,
  },
  {
    "whiteinge/diffconflicts",
  },
}
