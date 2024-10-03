return {
  "hrsh7th/nvim-cmp",
  dependencies = { "hrsh7th/cmp-cmdline" },
  opts = function(_, opts)
    table.insert(opts.sources, { name = "cmdline" })
  end,
}
