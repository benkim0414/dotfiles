return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "mason.nvim" },
    opts = {
      ensure_installed = { "gopls", "lua_ls", "pyright", "ts_ls", "jsonls" },
      automatic_installation = true,
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason.nvim" },
    opts = {
      ensure_installed = {
        "delve",
        "gopls",
        "gofumpt",
        "goimports",
        "golines",
        "markdown-toc",
        "markdownlint-cli2",
        "prettier",
      }
    }
  },
  {
    "jay-babu/mason-nvim-dap.nvim",
    dependencies = { "mason.nvim" },
    cmd = { "DapInstall", "DapUninstall" },
    opts = {
      automatic_installation = true,
      handlers = {},
      ensure_installed = {
        "delve"
      },
    },
    config = function() end,
  },
}