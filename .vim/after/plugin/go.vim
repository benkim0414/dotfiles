autocmd BufNewFile,BufRead *.go setlocal ts=4 sw=4

" Run `:GoBuild` or `:GoTestCompile` based on the go file.
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#test#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction

" Show the name of each failed test before the errors and logs output by the test.
let g:go_test_show_name = 1
" Use only quickfix instead of `location-list`.
let g:go_list_type = "quickfix"

" Use this option to disable showing a location list when 'g:go_fmt_command' fails.
let g:go_fmt_fail_silently = 1

" Specifies whether `gopls` should include suggestions from unimported packages.
let g:go_gopls_complete_unimported = 1
" Specifies whether `gopls` should use `gofumpt` for formatting.
let g:go_gopls_gofumpt = 1

" Specifies the `gopls` diagnostics level. 2 is for errors and warnings.
let g:go_diagnostics_level = 2

" Use camelcase for struct tags.
let g:go_addtags_transform = "camelcase"

let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1

let g:rehash256 = 1
let g:molokai_original = 1
colorscheme molokai

nmap <C-g> :GoDecls<CR>
imap <C-g> <Esc>:<C-u>GoDecls<CR>

augroup go
  autocmd FileType go nmap <silent> <Leader>b :<C-u>call <SID>build_go_files()<CR>
  autocmd FileType go nmap <silent> <Leader>r <Plug>(go-run)
  autocmd FileType go nmap <silent> <Leader>t <Plug>(go-test)
  autocmd FileType go nmap <silent> <Leader>c <Plug>(go-coverage-toggle)

  " Switch between *.go and *_test.go.
  autocmd FileType go map <C-a> :GoAlternate<CR>
  " Add commands to open the alternate file with split and tab.
  autocmd FileType go command! -bang A call go#alternate#Switch(<bang>0, 'edit')
  autocmd FileType go command! -bang AV call go#alternate#Switch(<bang>0, 'vsplit')
  autocmd FileType go command! -bang AS call go#alternate#Switch(<bang>0, 'split')
  autocmd FileType go command! -bang AT call go#alternate#Switch(<bang>0, 'tabe')

  autocmd FileType go nmap <silent> <Leader>v <Plug>(go-def-vertical)
  autocmd FileType go nmap <silent> <Leader>s <Plug>(go-def-split)

  " Go documentation shortcuts.
  autocmd FileType go nmap <silent> <Leader>d <Plug>(go-doc)
  autocmd FileType go nmap <silent> <Leader>i <Plug>(go-info)
augroup end

