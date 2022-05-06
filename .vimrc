" This option has the effect of making Vim either more Vi-compatible, or make
" Vim behave in a more useful way.
set nocompatible

syntax on
filetype plugin indent on

" Set the character encoding to UTF-8.
set encoding=utf-8

" Show each line with its line number.
set number
" Minimal number of columns to use for the line number.
set numberwidth=5
" Show the line number relative to the line with the cursor in front of
" each line.
set relativenumber
" Show the line and column number of the cursor position, separated by a comma.
set ruler

" Use the appropriate number of spaces to insert a <Tab>.
set expandtab
" Number of spaces that a <Tab> in the file counts for.
set tabstop=2
" Number of spaces to use for each step of (auto)indent. 
set shiftwidth=2

" When on, a <Tab> in front of a line inserts blanks according to 'shiftwidth'.
set smarttab
" Copy indent from current line when starting a new line.
set autoindent

" Write the content of the file automatically.
set autowrite

" When there is a previous search pattern, highlight all its matches.
set hlsearch
" While typing a search command, show where the pattern, as it was typed so far,
" matches.
set incsearch
" If the 'ignorecase' option is on, the case of normal letters is ignored.
" 'smartcase' can be set to ignore case when the pattern contains lowercase
" letters only.
set ignorecase
" Override the 'ignorecase' option if the search pattern contains upper
" case characters.
set smartcase

" Set the "mapleader" variable to comma.
let mapleader = ","

" DO NOT show command-line window.
map q: :q

" Overwrite an existing file.
nnoremap <Leader>w :w!<CR>
" Quit without writing.  
nnoremap <silent> <Leader>q :q!<CR>

" fzf
" Add fzf directory to &runtimepath.
set rtp+=/usr/local/opt/fzf
" Add fzf.vim package.
packadd! fzf.vim

