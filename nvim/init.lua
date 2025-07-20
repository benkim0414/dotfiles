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

nnoremap("<Leader>w", "<Cmd>w!<CR>", { desc = "Save file" })
nnoremap("<Leader>wa", "<Cmd>wa<CR>", { desc = "Save all files" })
nnoremap("<Leader>q", "<Cmd>q<CR>", { desc = "Quit" })
nnoremap("<Leader>Q", "<Cmd>q!<CR>", { desc = "Force quit" })

nnoremap("<C-Space>", "<Esc>:noh<CR>", { desc = "Clear search highlight" })
vnoremap("<C-Space>", "<Esc>gV", { desc = "Exit visual mode" })
onoremap("<C-Space>", "<Esc>", { desc = "Exit operator mode" })
cnoremap("<C-Space>", "<C-c>", { desc = "Exit command mode" })
inoremap("<C-Space>", "<Esc>", { desc = "Exit insert mode" })
nnoremap("<C-@>", "<Esc>:noh<CR>", { desc = "Clear search highlight" })
vnoremap("<C-@>", "<Esc>gV", { desc = "Exit visual mode" })
onoremap("<C-@>", "<Esc>", { desc = "Exit operator mode" })
cnoremap("<C-@>", "<C-c>", { desc = "Exit command mode" })
inoremap("<C-@>", "<Esc>", { desc = "Exit insert mode" })

require("config.lazy")
