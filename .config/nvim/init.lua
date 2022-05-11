vim.o.number = true
vim.o.numberwidth = 5
vim.o.relativenumber = true
vim.o.ruler = true

vim.o.expandtab = true
vim.o.tabstop = 2
vim.o.shiftwidth = 2
vim.o.smarttab = true
vim.o.autoindent = true

vim.o.autowrite = true

vim.o.hlsearch = true
vim.o.incsearch = true
vim.o.ignorecase = true
vim.o.smartcase = true

vim.g.mapleader = ','
vim.g.maplocalleader = ','
vim.keymap.set('', 'q:', '<cmd>:q<cr>')
vim.api.nvim_set_keymap('n', '<leader>w', '<cmd>w!<cr>', {noremap = true})
vim.api.nvim_set_keymap('n', '<leader>q', '<cmd>q!<cr>', {noremap = true})

