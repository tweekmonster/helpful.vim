let s:base = expand('<sfile>:p:h:h')

" Text around the word that might produce a match, in order of 'usefulness' to
" a developer.
let s:ornaments = [
      \ [':', ''],
      \ ['', '()'],
      \ [':func-', ''],
      \ ["'", "'"],
      \ ['<', '>'],
      \ ['@', ''],
      \ ['"', ''],
      \ ['hl-', ''],
      \ ['syn-', ''],
      \ ['[', ']'],
      \ ['{', '}'],
      \ ['+', ''],
      \ ]


function! s:load_data() abort
  if exists('s:data')
    return
  endif

  let s:data = {}
  for line in readfile(s:base.'/data/tags')
    let parts = split(line, "\x07")
    for flavor in parts[1:]
      let name = matchstr(flavor, '^[^:]\+')
      let versions = split(matchstr(flavor, ':\zs.*'), ',', 1)
      if !has_key(s:data, parts[0])
        let s:data[parts[0]] = {}
      endif

      let s:data[parts[0]][name] = {
            \ '+': versions[0],
            \ '-': versions[1],
            \ }
    endfor
  endfor
endfunction


" Wrap a pattern with an outer pattern that matches likely helptag characters.
function! s:pattern_wrap(pattern, help) abort
  let pattern = a:pattern
  if a:help
    let tagpattern = '\%(\1\@!.\)*'.pattern.'\%(\1\@!.\)*'
    return '\%(\([|*]\)\zs'.tagpattern.'\ze\1\)\|'
          \ .'\%(\zs''[^'']*'.pattern.'[^'']*''\ze\)\|'
          \ .'\%(\zs\%(:\%(\w\|[-_]\)\)\?<[^<>]*'.pattern.'[^<>]*>\ze\)\|'
          \ .'\%(\zs\[[^\[\]]*'.pattern.'[^\[\]]*\]\ze\)\|'
          \ .'\%(\zs{[^{}]*'.pattern.'[^{}]*}\ze\)\|'
          \ .'\zs\%(\k\|[_-]\)*'.pattern.'\%(\k\|[_-]\)*\ze('
  endif
  let word_atom = '\%(\w\|[&:_@#{}/\+-]\)*'
  return word_atom.pattern.word_atom
endfunction


" Get the word under the cursor.
" <cword> and <cWORD> aren't reliable for helpful.vim
function! s:cword() abort
  let pattern = s:pattern_wrap('\%'.col('.').'c', &filetype == 'help')
  let word = matchstr(getline('.'), pattern)

  if &filetype == 'help'
    return word
  endif

  if word =~# '^!'
    let word = word[1:]
  endif

  if empty(word)
    return ''
  endif

  " Force a match on <Key> tags, but make an exception for :map-<whatever>
  if word !~# '^:' && word =~# '<.*>'
    let word = matchstr(word, '<[^>]\+>')
  endif

  " Find some clues about the text under the cursor.
  if word =~# '^&l:'
    let word = "'".word[3:]."'"
  elseif word =~# '^&'
    let word = "'".word[1:]."'"
  elseif word =~# '^end.'
    let word = word[3:]
  endif

  return word
endfunction


" Find the best match for a helptag.  Oranments are put around the the tag if
" there's no first match.  If there is no match, return an empty string.
function! s:match_word(word) abort
  call s:load_data()

  if has_key(s:data, a:word)
    return a:word
  endif

  for [t1, t2] in s:ornaments
    if has_key(s:data, t1.a:word.t2)
      return t1.a:word.t2
    endif
  endfor

  return ''
endfunction


function! s:helptag_version(word, ...) abort
  let word = a:word

  if !exists('b:_helpful_word') || b:_helpful_word[0] != word
    let word = s:match_word(word)
    if empty(word)
      return
    endif

    let info = s:data[word]
    let b:_helpful_word = [a:word, word, info]
  else
    let word = b:_helpful_word[1]
    let info = b:_helpful_word[2]
  endif

  let keys = has('nvim') ? ['neovim', 'vim'] : ['vim', 'neovim']

  if !a:0
    redraw
  endif

  echohl Special
  echo printf('%*S', a:0 ? a:1 : 0, word)
  echohl None

  for k in keys
    if !has_key(info, k) || (empty(info[k]['+']) && empty(info[k]['-']))
      continue
    endif

    echon ' | '
    echon k.': '

    if !empty(info[k]['+'])
      echohl DiffAdd
      echon '+'.info[k]['+']
      echohl None
    endif

    if !empty(info[k]['-'])
      if !empty(info[k]['+'])
        echon ', '
      endif
      echohl DiffDelete
      echon '-'.info[k]['-']
      echohl None
    endif
  endfor
endfunction


" Find a helptag using a word under the cursor
function! helpful#cursor_word() abort
  if mode() ==? 'v'
    " Need to save the original visual marks?  Visual marks aren't updated
    " until visual mode is left.
    let view = winsaveview()
    let v1 = getpos("'<")
    let v2 = getpos("'>")

    execute "normal! \<esc>gv"

    let p1 = getpos("'<")[1:2]
    let p2 = getpos("'>")[1:2]

    call winrestview(view)
    call setpos("'<", v1)
    call setpos("'>", v2)

    if p1[0] != p2[0]
      return
    endif

    let word = getline(p1[0])[p1[1]-1:p2[1]-1]
  else
    let word = s:cword()
  endif

  if empty(word)
    echo ''
    return
  endif

  call s:helptag_version(word)
endfunction


" Normalize Vim's goofy old versions so they can be compared with the other
" versions.
"
" Where M = major, m = minor, R = rev, A = alpha
" MmRRRRA
"
" Vim:
" 7.4.300  = 7403000
" 7.2.1234 = 7212340
" 7.1a     = 7100001
"
" Neovim:
" 0.1.3    =  100030
" 1.0.1    = 1000010
" 2.5.22   = 2500220
function! s:parse_version(version) abort
  let vparts = split(matchstr(a:version, '\d.*'), '\.')
  if empty(vparts)
    return 0
  endif

  let major = str2nr(vparts[0])
  let minor = 0
  let alpha = 0
  let rev = 0

  if vparts[1] =~ '\D'
    let minor = str2nr(matchstr(vparts[1], '\d'))
    let alpha = char2nr(tolower(matchstr(vparts[1], '\D'))) - 96
  elseif len(vparts) == 2 && vparts[1] =~# '\d\{4}'
    let minor = 0
    let rev = str2nr(vparts[1])
  else
    let minor = str2nr(vparts[1])
  endif

  if len(vparts) > 2
    let rev = str2nr(vparts[2])
  endif

  return major * 1000000 +
        \ minor * 100000 +
        \ rev * 10 +
        \ alpha
endfunction


" Reverses the result of s:parse_version()
function! s:unparse_version(version) abort
  if !a:version
    return '???'
  endif

  let v = a:version
  let major = a:version / 1000000
  let v -= major * 1000000
  let minor = v / 100000
  let v -= minor * 100000
  let rev = v / 10
  let v -= rev * 10

  if v
    return printf('v%d.%d%s', major, minor, nr2char(v + 96))
  elseif major == 7 && minor == 0
    return printf('v%d.0%03d', major, rev)
  endif

  return printf('v%d.%d.%0*d', major, minor, major >= 7 ? 3 : 0, rev)
endfunction


function! s:_lookup_sort(a, b) abort
  if a:a[1] < a:b[1]
    return -1
  elseif a:a[1] > a:b[1]
    return 1
  endif

  let al = strlen(a:a[0])
  let bl = strlen(a:b[0])

  if al < bl
    return -1
  elseif al > bl
    return 1
  endif

  return 0
endfunction


" Find helptag using a pattern and print the results.
function! helpful#lookup(pattern) abort
  call s:load_data()
  let tags = []
  let width = 0

  for tag in keys(s:data)
    let m = match(tag, a:pattern)
    if m != -1
      call add(tags, [tag, m])
      let width = max([width, strlen(tag)])
    endif
  endfor

  let s:search_pattern = a:pattern
  for [tag, _] in sort(tags, 's:_lookup_sort')
    call s:helptag_version(tag, width)
  endfor
endfunction


" Find functions in the buffer and print min and max versions that are
" required.  Only a proof of concept, there is no plan for it to be smarter.
function! helpful#buffer_version() abort
  call s:load_data()

  let view = winsaveview()
  let s = @/
  let b = getreg('b')
  let bt = getregtype('b')
  normal! qbq
  g/\k\+(/normal! gn"By
  let @/ = s
  call histdel('search', -1)

  let funcs = map(split(getreg('b'), '('), 'v:val."()"')
  call setreg('b', b, bt)
  call winrestview(view)

  let neovim_min = 0
  let neovim_max = 99999999
  let vim_min = 0
  let vim_max = 99999999

  for f in funcs
    if has_key(s:data, f)
      let vinfo = s:data[f]

      if has_key(vinfo, 'neovim')
        let neovim_max = min([neovim_max, s:parse_version(vinfo['neovim']['-'])])
        let neovim_min = max([neovim_min, s:parse_version(vinfo['neovim']['+'])])
      endif

      if has_key(vinfo, 'vim')
        let vim_max = min([vim_max, s:parse_version(vinfo['vim']['-'])])
        let vim_min = max([vim_min, s:parse_version(vinfo['vim']['+'])])
      endif
    endif
  endfor

  echo 'Neovim:' s:unparse_version(neovim_min) ' - ' s:unparse_version(neovim_max)
  echo 'Vim:' s:unparse_version(vim_min) ' - ' s:unparse_version(vim_max)
endfunction


function! s:enabled() abort
  return get(b:, 'helpful', get(g:, 'helpful', 0))
endfunction


function! helpful#setup() abort
  augroup helpful
    autocmd! * <buffer>
    autocmd CursorMoved <buffer> if s:enabled() | call helpful#cursor_word() | endif
  augroup END
endfunction
