augroup filetype
  au! BufRead,BufNewFile *.proto setfiletype proto
augroup end

" The |g:ale_linters| option sets a |Dictionary| mapping a filetype to a
" |List| of linter programs to be run when checking particular filetypes.
let b:ale_linters = {'proto': ['buf-lint']}
" This option controls how ALE will check your files as you make changes.
let g:ale_lint_on_text_changed = 'never'
" When set to `1`, only the linters from |g:ale_linters| and |b:ale_linters|
" will be enabled.
let g:ale_linters_explicit = 1

" A mapping from filetypes to |List| values for functions for fixing errors.
let b:ale_fixers = {'proto': ['buf-format']}
" When set to 1, ALE will fix files when they are saved.
let b:ale_fix_on_save = 1
