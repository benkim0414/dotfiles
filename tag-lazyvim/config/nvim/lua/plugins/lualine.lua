return {
  {
    "nvim-lualine/lualine.nvim",
    config = function()
      require("lualine").setup({
        options = {
          theme = "catppuccin",
          icons_enabled = false,
          component_separators = " ",
          section_separators = { left = "", right = "" },
        },
      })
    end,
  },
}
