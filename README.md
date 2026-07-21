# WARNING
This module is still in a VEEERY young state and works only (partially, let's
rather say *barely* workking) for the
C programming language! So be prepared for a lot of bugs if you're trying it
out! If you want to know a little bit more, then you can read [this
issue-message](https://github.com/TornaxO7/tree-setter/issues/1#issuecomment-1025161228).

# TreeSetter
TreeSetter is a
[nvim-treesitter-module](https://github.com/nvim-treesitter/module-template)
which **adds semicolons (`;`), commas (`,`) and double points (`:`) automatically**
for you, if you hit enter at the end of a line!

# Demo
![demonstration](./Documentation_Images/demo.gif)

As you can see from in the key-screen-bar
[screenkey](https://gitlab.com/screenkey/screenkey) I almost never pressed the
`;` key. I just needed to write the line of code, what I wanted and pressed the
`<CR>` key. The semicolon was added automatically.

# Installation
With [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'TornaxO7/tree-setter'
```

Then enable it once (for example in your `init.lua`):
```lua
require("tree-setter").setup()
```

That's it! tree-setter now uses Neovim's **native treesitter API** (`vim.treesitter`),
so it no longer depends on the `nvim-treesitter` module framework. It only needs
the treesitter parser for your language to be installed (e.g. via
[`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter) or the
bundled parsers) and a `queries/<lang>/tsetter.scm` file to exist. Languages
without such a query file are simply ignored.

> **Note:** requires a recent Neovim with the native treesitter API
> (`vim.treesitter.query.get`, `vim.treesitter.get_node`, ...).

# Contributing
Take a look into the [CONTRIBUTING.md](./CONTRIBUTING.md) file for that ;)

# Other information
## Why so less commits?
The problem is, that treesitter gives different results if the syntax is wrong
which makes it really hard to write the queries. So we have to wait until it
stabilizes that.
