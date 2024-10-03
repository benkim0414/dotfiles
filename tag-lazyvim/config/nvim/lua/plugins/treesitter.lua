return {
  {
    "folke/which-key.nvim",
    keys = {
      { "<BS>", mode = "x", false },
      { "<C-Space>", mode = { "x", "n" }, false },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      incremental_selection = {
        enable = false,
      },
    },
  },
}
