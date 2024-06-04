return {
  {
    "vim-test/vim-test",
    config = function()
      local nmap = require("utils").nmap

      nmap("<Leader>t", "<Cmd>:TestNearest<CR>")
      nmap("<Leader>T", "<Cmd>:TestFile<CR>")
      nmap("<Leader>a", "<Cmd>:TestSuite<CR>")
      nmap("<Leader>l", "<Cmd>:TestLast<CR>")
      nmap("<Leader>g", "<Cmd>:TestVisit<CR>")

      vim.g["test#strategy"] = "vtr"
      vim.g["test#javascript#jest#options"] = "--coverage=false"
    end,
  },
}
