return {
  {
    "preservim/nerdtree",
    config = function()
      local nnoremap = require("utils").nnoremap

      nnoremap("<C-n>", "<Cmd>:NERDTreeToggle<CR>")
      nnoremap("<C-f>", "<Cmd>:NERDTreeFind<CR>")
    end,
  },
}
