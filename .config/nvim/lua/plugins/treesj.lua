return {
  'Wansmer/treesj',
  keys = {'<Space>m', '<Space>j', '<Space>s'},
  dependencies = {
    'nvim-treesitter/nvim-treesitter'
  },
  config = function()
    require('treesj').setup()
  end,
}
