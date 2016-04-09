let s:path = expand('<sfile>:p:h')

if !exists('s:tags')
  let taglines = readfile(s:path.'/tags.txt')
  let s = join(taglines, '')
  let s:tags = eval(s)
endif

function! s:cursor_version()
  let w = expand('<cWORD>')
  let w = matchstr(w, '\(|\|\*\|''\).*\1')
  if w !~ '^'''
    let w = strpart(w, 1, len(w) - 2)
  endif

  let info = get(s:tags, w, '')
  if !empty(info)
    echo w
    if has_key(info, '+')
      let ver = get(info, '+')
      let ver_parts = split(ver, '.')
      let ver0 = join(ver_parts[0:1], '0')
      if str2nr(ver0) > v:version || (len(ver_parts) > 3 && !has('patch-'.ver_parts[2]))
        echohl Error
      else
        echohl Title
      endif
      echon ' +'.ver
      echohl None
    endif
    if has_key(info, '-')
      echohl Error
      echon ' -'.get(info, '-')
      echohl None
    endif
  endif
endfunction

augroup help_versions
  autocmd! FileType help autocmd! CursorMoved <buffer> call s:cursor_version()
augroup END
