" This option has the effect of making Vim either more Vi-compatible, or make
" Vim behave in a more useful way.
set nocompatible

call plug#begin('~/.vim/bundle')
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-flagship'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-unimpaired'

Plug 'kana/vim-textobj-user'
Plug 'kana/vim-textobj-line'
Plug 'kana/vim-textobj-indent'
Plug 'kana/vim-textobj-entire'

Plug 'christoomey/vim-system-copy'
Plug 'christoomey/vim-tmux-navigator'

Plug 'pbrisbin/vim-mkdir'

Plug 'vim-scripts/ReplaceWithRegister'

Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'

Plug 'preservim/nerdtree'

Plug 'whiteinge/diffconflicts'

Plug 'dense-analysis/ale'
Plug 'bufbuild/vim-buf'

Plug 'vim-test/vim-test'
Plug 'christoomey/vim-tmux-runner'

Plug 'puremourning/vimspector'

Plug 'fatih/vim-go', { 'do': ':GoInstallBinaries' }
Plug 'AndrewRadev/splitjoin.vim'
Plug 'SirVer/ultisnips'

Plug 'fatih/molokai'
Plug 'morhetz/gruvbox'

Plug 'mustache/vim-mustache-handlebars'
call plug#end()

colorscheme gruvbox

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

" Move between wrapped lines, rather than jumping over wrapped segements.
nmap j gj
nmap k gk

" Use C-Space to Esc out of any mode.
nnoremap <C-Space> <Esc>:noh<cr>
vnoremap <C-Space> <Esc>gV
onoremap <C-Space> <Esc>
cnoremap <C-Space> <C-c>
inoremap <C-Space> <Esc>
" Terminal sees <C-@> as <C-space>
nnoremap <C-@> <Esc>:noh<cr>
vnoremap <C-@> <Esc>gV
onoremap <C-@> <Esc>
cnoremap <C-@> <C-c>
inoremap <C-@> <Esc>

nnoremap <Leader>cc :ClearEmAll<CR>

command! ClearEmAll call s:ClearEmAll()

function! s:ClearEmAll()
  nohlsearch
  cclose
  pclose
  lclose
  call popup_clear()
endfunction

" Swap 0 and ^.
nnoremap 0 ^
nnoremap ^ 0

" Rebalance windows on vim resize
autocmd VimResized * :wincmd =

" Zoom a vim pane, <C-w>= to re-balance
nnoremap <Leader>- :wincmd _<CR>:wincmd \|<CR>
nnoremap <Leader>= :wincmd =<CR>

" fzf
nnoremap <C-p> :Files<CR>
let $FZF_DEFAULT_OPTS .= ' --inline-info'
let $FZF_DEFAULT_COMMAND="rg --files --hidden --follow --glob '!.git'"

if exists('$TMUX')
  let g:fzf_layout = { 'tmux': '-p90%,60%' }
else
  let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.6 } }
endif

nnoremap <silent> <Leader>B :Buffers<CR>
nnoremap <silent> <Leader>bl :BLines<CR>
nnoremap <silent> <Leader>rg :Rg<CR>
nnoremap <silent> <Leader>RG :RG<CR>

" Delegate search responsibliity to ripgrep process by making it restart ripgrep
" whenever the query string is updated.
function! RipgrepFzf(query, fullscreen)
  let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case -- %s || true'
  let initial_command = printf(command_fmt, shellescape(a:query))
  let reload_command = printf(command_fmt, '{q}')
  let spec = {'options': ['--phony', '--query', a:query, '--bind', 'change:reload:'.reload_command]}
  call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
endfunction

command! -nargs=* -bang RG call RipgrepFzf(<q-args>, <bang>0)

" Program to use for the :grep command.
set grepprg=rg\ --vimgrep\ --smart-case\ --follow

nnoremap <C-n> :NERDTreeToggle<CR>

" ALE
" When this option is set to `1`, completion support will be enabled.
let g:ale_completion_enabled = 1

" A completion function to use with 'omnifunc'.
set omnifunc=ale#completion#OmniFunc

" ALE supports jumping to the files and locations where symbols are defined
" through any enabled LSP linters.
nnoremap gd :ALEGoToDefinition<CR>
nnoremap gds :ALEGoToDefinition -split<CR>
nnoremap gdv :ALEGoToDefinition -vsplit<CR>

" Find references in the codebase for the symbol under the cursor using the
" enabled LSP linters for the buffer.
nnoremap <silent> <Leader>fr :ALEFindReferences<CR>

" Print information about the symbol at the cursor.
nnoremap K :ALEHover<CR>

" Move between warnings or errors in a buffer.
nnoremap ]d :ALENext<CR>
nnoremap [d :ALEPrevious<CR>

" Rename a symbol using `tsserver` or a Language Server.
nnoremap <silent> <Leader>rn :ALERename<CR>
" Rename a file and fix imports using `tsserver`.
nnoremap <silent> <Leader>frn :ALEFileRename<CR>
" Apply a code action via LSP servers or `tsserver`.
nnoremap <silent> <Leader>a :ALECodeAction<CR>

" vim-test
nmap <silent><Leader>t :TestNearest<CR>
nmap <silent><Leader>T :TestFile<CR>
nmap <silent><Leader>a :TestSuite<CR>
nmap <silent><Leader>l :TestLast<CR>
nmap <silent><Leader>g :TestVisit<CR>

" Runs test commands in a small Tmux pane. Requires the Vim Timux Runner plugin
" and Tmux.
let g:test#strategy = 'vtr'
let g:test#javascript#runner = 'jest'
let g:test#javascript#jest#executable = 'yarn jest --config jest.config.js'

" Vimspector
let g:vimspector_install_gadgets = ['vscode-js-debug', 'vscode-node-debug2']

nmap <Leader>dc <Plug>VimspectorContinue
nmap <Leader>ds <Plug>VimspectorStop
nmap <Leader>dr <Plug>VimspectorRestart

nmap <Leader>dB <Plug>VimspectorBreakpoints
nmap <Leader>db <Plug>VimspectorToggleBreakpoint

nmap <Leader>dl <Plug>VimspectorStepOver
nmap <Leader>dj <Plug>VimspectorStepInto
nmap <Leader>dk <Plug>VimspectorStepOut
nmap <Leader>dn <Plug>VimspectorJumpToNextBreakpoint
nmap <Leader>dp <Plug>VimspectorJumpToPreviousBreakpoint

nmap <Leader>di <Plug>VimspectorBalloonEval
xmap <Leader>di <Plug>VimspectorBalloonEval

nmap <Leader>dq :call vimspector#Reset()<CR>
nmap <Leader>dd :call vimspector#ClearBreakpoints()<CR>
