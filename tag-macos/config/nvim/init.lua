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

g.mapleader = ","
g.maplocalleader = ","

nnoremap("<Leader>w", "<Cmd>w!<CR>")
nnoremap("<Leader>wa", "<Cmd>wa<CR>")
nnoremap("<Leader>q", "<Cmd>q!<CR>")
map("q:", "<Cmd>:q<CR>")

nmap("j", "gj")
nmap("k", "gk")
nnoremap("0", "^")
nnoremap("^", "0")

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

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins")
