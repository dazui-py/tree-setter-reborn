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
tree-setter-reborn supports all the usual plugin managers:

</details>

<details>
  <summary>vim-plug</summary>

```vim
Plug 'TornaxO7/tree-setter'
```

</details>

<details>
  <summary>lazy.nvim</summary>

```lua
{ "dazui-py/tree-setter-reborn", opts = {} }
```
</details>

<details>
  <summary>vim.pack (Neovim 0.12+)</summary>

```lua
vim.pack.add({'https://github.com/dazui-py/tree-setter-reborn'})
```

</details>

<details>
  <summary>Neovim native package</summary>

```sh
git clone --depth=1 https://github.com/dazui-py/tree-setter-reborn.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/pack/tsetter/start/tree-setter-reborn
```

</details>

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

### Developing tip:

When you want your changes in this repository to be the ones Neovim *actually*
runs, install the plugin as a symlink into one of Neovim's auto-loaded
locations so it isn't shadowed by a stale copy shipped through your plugin
manager. The cleanest way is:

```bash
# Remove any pre-existing install (avoid an OLD copy of this plugin shadowing
# your edits -- this was a real issue that took me some time to realize, and since I use vim.pack had to do this workaround).
rm -rf ~/.local/share/nvim/site/pack/*/start/tree-setter-reborn
rm -rf ~/.local/share/nvim/site/pack/*/opt/tree-setter-reborn

# Symlink your working clone into the auto-load `start/` directory.
mkdir -p ~/.local/share/nvim/site/pack/core/start
ln -s "$PWD" ~/.local/share/nvim/site/pack/core/start/tree-setter-reborn
```

After this, edits in this directory are picked up the moment you restart
Neovim -- no copying back into a checkout, no `packadd` incantation.

# Contributing
Take a look into the [CONTRIBUTING.md](./CONTRIBUTING.md) file for that ;)

# Other information
## Why so less commits?
The problem is, that treesitter gives different results if the syntax is wrong
which makes it really hard to write the queries. So we have to wait until it
stabilizes that.
