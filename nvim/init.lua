local o = vim.o
local opt = vim.opt
local g = vim.g
local utils = require("utils")
local map = utils.map
local nmap = utils.nmap
local nnoremap = utils.nnoremap
local vnoremap = utils.vnoremap
local onoremap = utils.onoremap
local cnoremap = utils.cnoremap
local inoremap = utils.inoremap

o.termguicolors = true

opt.number = true
opt.numberwidth = 5
opt.relativenumber = true

opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.smarttab = true
opt.autoindent = true

opt.autowrite = true

opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

g.mapleader = " "
g.maplocalleader = " "

nnoremap("<Leader>w", "<Cmd>w!<CR>")
nnoremap("<Leader>wa", "<Cmd>wa<CR>")
nnoremap("<Leader>q", "<Cmd>q<CR>")
nnoremap("<Leader>Q", "<Cmd>q!<CR>")

nnoremap("<C-Space>", "<Esc>:noh<CR>")
vnoremap("<C-Space>", "<Esc>gV")
onoremap("<C-Space>", "<Esc>")
cnoremap("<C-Space>", "<C-c>")
inoremap("<C-Space>", "<Esc>")
nnoremap("<C-@>", "<Esc>:noh<CR>")
vnoremap("<C-@>", "<Esc>gV")
onoremap("<C-@>", "<Esc>")
cnoremap("<C-@>", "<C-c>")
inoremap("<C-@>", "<Esc>")

require("config.lazy")
