# helpful.vim

A plugin for plugin developers to get the version of Vim and Neovim that
introduced or removed features.

![helpful](https://cloud.githubusercontent.com/assets/111942/16898497/2bf0a402-4baa-11e6-9f9b-3793384d5894.png)


## Usage

The command `:HelpfulVersion` searches helptags for a subject and displays the
version information.

Use `:HelpfulVersion!` to match the exact help tag name instead of doing a
broader search.

Examples:

```vim
" Search for a matching name
:HelpfulVersion matchaddpos
" Search for the exact name
:HelpfulVersion! matchaddpos()
```


## Options

- `b:helpful` - If set to `1`, display version information about the text under
  the cursor on `CursorMoved` in `help` or `vim` filetypes.
- `g:helpful` - Same as above but always on.  It's also less humorous to read
  out loud.

## License

MIT
