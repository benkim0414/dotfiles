-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local utils = require("config.utils")
local map = utils.map
local nnoremap = utils.nnoremap
local vnoremap = utils.vnoremap
local onoremap = utils.onoremap
local cnoremap = utils.cnoremap
local inoremap = utils.inoremap

nnoremap("<Leader>w", "<Cmd>w!<CR>")
nnoremap("<Leader>wa", "<Cmd>wa<CR>")
nnoremap("<Leader>q", "<Cmd>q!<CR>")
map("q:", "<Cmd>:q<CR>")

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
