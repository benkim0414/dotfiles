colorscheme molokai

" A mapping from filetypes to List values for functions for fixing errors.
let b:ale_fixers = {
\ 'javascript': ['prettier', 'eslint'],
\ 'typescript': ['prettier', 'eslint'],
\ 'javascriptreact': ['prettier', 'eslint'],
\ 'typescriptreact': ['prettier', 'eslint'],
\ 'json': ['prettier'],
\}
