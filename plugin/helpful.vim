augroup help_versions
  autocmd! FileType vim,help call helpful#setup()
  autocmd! FileType vim,help command! -nargs=+ -complete=help HelpfulVersion call helpful#lookup('<args>')
augroup END
