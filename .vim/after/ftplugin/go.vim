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

" Use only quickfix instead of `location-list`.
let g:go_list_type = "quickfix"

" Use `goimports` over `gofmt`.
let g:go_fmt_command = "goimports"

" Use camelcase for struct tags.
let g:go_addtags_transform = "camelcase"

let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1

let g:rehash256 = 1
let g:molokai_original = 1
colorscheme molokai

" Use `godef` for `:GoDef` command.
let g:go_def_mode = "godef"

" Set `gopls` to the renaming tool.
let g:go_rename_command = "gopls"

augroup go
  autocmd FileType go nmap <Leader>b :<C-u>call <SID>build_go_files()<CR>
  autocmd FileType go nmap <Leader>r <Plug>(go-run)
  autocmd FileType go nmap <Leader>t <Plug>(go-test)
  autocmd FileType go nmap <Leader>c <Plug>(go-coverage-toggle)

  " Switch between *.go and *_test.go.
  autocmd FileType go map <C-a> :GoAlternate<CR>
  " Add commands to open the alternate file with split and tab.
  autocmd Filetype go command! -bang A call go#alternate#Switch(<bang>0, 'edit')
  autocmd Filetype go command! -bang AV call go#alternate#Switch(<bang>0, 'vsplit')
  autocmd Filetype go command! -bang AS call go#alternate#Switch(<bang>0, 'split')
  autocmd Filetype go command! -bang AT call go#alternate#Switch(<bang>0, 'tabe')

  " Go documentation shortcuts.
  autocmd FileType go nmap <Leader>d <Plug>(go-doc)
  autocmd FileType go nmap <Leader>i <Plug>(go-info)
augroup end

