Thank you for wanting to contribute to *tree-setter*!
There are different ways to contribute to this project. Pick up the section from
the table of contents if the title suits your intention. Here's a little image
of how to open the table of contents:

![TOC Image](./Documentation_Images/OpenTOC.png)

# Write Queries
## General
Thank you for wanting to write some queries in order to fill up more cases where
a semicolon/comma/double point has to be set! :)
This should be a little guide on how to write them, which should help you to
improve `tree-setter`!

### Filestructure
Let's start with the file structure first, so you know where to write the
queries:

```
tree-setter
└── queries
   ├── c
   │   └── tsetter.scm
   ├── cpp
   │   └── tsetter.scm
   └── lua
       └── tsetter.scm
```

The interesting directory is `tree-setter/queries` which includes all queries
for their appropriate language. Each directory (for the language) has a
`tsetter.scm` file. They *have* to be named as that since `tree-setter` assumes
that the files are named like that! To sum it up:

1. Look if a directory with the language name exists or not
    - If yes => Navigate into it
    - Otherwise => Create it
2. Look if there's already a `tsetter.scm` file
    - If yes => Open it in ~~your favourite editor~~ neovim!
    - Otherwise => Create it!

### Writing queries
#### Crash-Course
So now we're getting into the interesting part!
I'm using C as the example language here since it's pretty mature. If you want
to see more details about the queries (of C), open
`tree-setter/queries/c/tsetter.scm` in ~~your text-editor~~ neovim (hint, it's
probably worth it, since they include some comments which should make it
understandable) ;).

Let's take a look into the following query-code:

```scheme
(declaration
    type: (_)
    declarator: (_) @semicolon
)
```

We can see a code-tree-structure like code. If you take a look into the tsetter
file of the C language, you'll see that I picked the first query of it.
But how did I found out that the query has to look like this in order to let
TreeSitter know that this is a declaration? Well, I'm using
[nvim-treesitter/playground](https://github.com/nvim-treesitter/playground) for
that. Let's create a new C-file and open up the playground! It'll look like
this:

![C query example](./Documentation_Images/TreeSitterPlayground_C_Example.png)

As you can see, there's a similiar structure on the playground:

```scheme
declaration [1, 4] - [1, 10]
    type: primitive_type [1, 4] - [1, 7]
    declarator: identifier [1, 8] - [1, 9]
```

very nice! So all we need to do, is just writing this query down as it's
displayed in the playground.

**Note:** Make sure that you removed the semicolon, because sometimes TreeSitter parses
the query *differently* if there's a semicolon or not!

`(_)` are used, because according to the
[docs](https://tree-sitter.github.io/tree-sitter/using-parsers#named-vs-anonymous-nodes)
we can create anonymous nodes. But why? Well, `type` needn't to be always a
`primitve_type` (here an `int`). It could also be a char or something else, we
don't know. So we are using an anonymous node!

Ok, but how does the module know if it should add a semicolon, comma or a double
point? Well, we are doing this by adding this `@`-thing which is called a
"predicate". Just write after the `@` which character has to be add. If there
should be a comma instead of a semicolon, then write `@comma` instead. There are
four different predicates for this module which you can use:

- `@semicolon`
- `@comma`
- `@double_points`
- `@skip`

Each predicate refers to their appropriate character as the name says. So if
there should be a comma after a declaration instead, than you can write it as
follows:

```scheme
(declaration
    type: (_)
    declarator: (_) @comma
)
```

This will place a comma after a declaration instead of a semicolon:

![C example with a semicolon](./Documentation_Images/C_Example.png)

One "exception" is the `@skip` predicate. As the name says, you say TreeSitter,
that it should *not* check in the current query if a query matches. This happens
for example in the following case (also described in the last lines of the
`tsetter.scm` file in C):

```c
if (test()
```

without the last query from the C queries, `tree-setter` would add a semicolon
after `test()` if you would hit the enter key now! This is not what we want! So
`tree-setter` should skip this part, that's the usage of this `@skip`.

By the way: It *is* important *where* you but the predicate, because
`tree-setter` will put the semicolon, etc. on the place of the predicate!

Now you should be able to write some queries for your language now! :)
Please follow the
[query-code-styles](./CONTRIBUTING.md#query-code-style) (below)
to make it better to maintain and better to understand before creating a pull
request ;)

### Tips
#### General
If you want to know more on how to write queries, than you can read it from the
[official
docs](https://tree-sitter.github.io/tree-sitter/using-parsers#query-syntax).
This should explain you some more features and tricks on how to write them :)

I also recommend to read through `:h lua-treesitter-query` which explains it
partially as well.


#### "Weird" queries
Some queries might be pretty problematic... Look at this query for example (also
from the query file of C):

```scheme
((ERROR
    (call_expression
        function: (identifier)
        arguments: (argument_list)
    )
) @semicolon)
```

This query is used to indicate a user-function which is called. Yes it might
look weird, but that's how TreeSitter evaluates the code if the semicolon is
missing, so keep an eye on the playground what it's displaying!

## Query-Code-Style
Please write the queries in the following style:

```scheme
<Look first, if there is a suitable sub-section where you could add your Query>
;; <Short description of its usage>
;; Example(s):
;;      <a short example which should be triggered>
;;
;; <If needed: A little description if there are "corner cases" or other stuff
;; which has to be considered>
<The query>
```

Here's an example of a C query of `tree-setter/queries/c/tsetter.scm`:

```scheme
;; ===================
;; Action Queries
;; ===================
;; --------------
;; Variables
;; --------------
;; For known declarations and initialisations
;; Example:
;;      char var_name
;;      int var_name = 10

;; Somehow `long` can't be seen as a declaration first, only if the semicolon is
;; added, so we have to use the query below for these cases.
(declaration
    type: (_)
    declarator: (_) @semicolon
)
```

# Expanding/Improving tree-setter code
So this is gonna be about the backend of `tree-setter`. You'll get a rough
overview of how the code works in order to be able to extend the code! So let's
start with the filestructure first!

## Filestructure
Here is the Filestructure with the most important files and a little description
for them on the right:

```
tree-setter
├── CONTRIBUTING.md         The document you're reading
├── Documentation_Images    All images which are used in the documentation
├── lua                     The "heart" directory of this module
│   ├── tree-setter         
│   │   ├── main.lua        This file includes the main functions of the
│   │   │                       module like checking if any queries match for
│   │   │                       the current file or not and looking if the user
│   │   │                       hit enter.
│   │   └── setter.lua      This file holds only one function, which will add
│   │                           the appropriate character to the given line.
│   └── tree-setter.lua     Includes the entry point for a treesitter module
│                              (here: tree-setter)
├── plugin
│   └── tree-setter.vim     Nothing special here, it just calls the
│                               preparation function for the treesitter module
└── queries                 As explained in the previous "chapter" this
                                directory includes all queries for the given
                                filetype
```

So let's move on to the steps!

## General
When the user starts neovim, the init function in
`tree-setter/lua/tree-setter.lua` is called which will look, if we have a
query for the current language and looks, where the main-entry-point of the
module is. Here it's `tree-setter/lua/tree-setter/main.lua`.

So now we're mostly in the `tree-setter/lua/tree-setter/main.lua` file.
TreeSitter will call the `TreeSetter.attach()` function which will load the
appropriate query for our current language and prepares the autocommands.

`tree-setter` needs to check if the user hits the enter-key. But how can we
check, if the user pressed the enter key? Well, if the user pressed the enter
key, than the cursor will move one line down. That's how `tree-setter` tries to
detect if the enter-key is pressed without mapping any keys!

The `TreeSetter.main()` function will check if the enter-key is hit, if yes, the
next function comes in: `TreeSetter.add_character()`. This just picks up the
node of the current cursor position and the parent to get a range to test which
queries match or not.

If we found a match, we're looking which kind of character we need to add
according to their predicate name like `@semicolon` or @comma`. `@skip` will
stop the process which tests which queries matches.

In general that's it. Take a look into the comments of the code, to get a more
detailed explanation. I hope that it roughly helped you to understand the
backend. Feel free to ask by creating a new issue :)

# Tests
The repository ships a headless test suite under `tests/`. New code or query
changes should be covered by a corresponding test before sending a pull
request.

## Layout
```
tests/
├── test_setter.lua       unit tests for lua/tree-setter/setter.lua
├── test_main_c.lua       e2e for C (attach + main + detach)
├── test_main_lua.lua     e2e for the lua/ queries
├── test_edge.lua         paste, o, dd, backspace-join, re-attach
├── test_queries.lua      smoke test for every queries/<lang>/tsetter.scm
└── run.sh                bash driver; runs every test_*.lua headless
```

## Conventions
- Each test file ends with a line `RESULT pass=N fail=M` and a `cq!`
  exit if any assertion failed, `qa!` otherwise.
- `tests/run.sh` walks the directory in sorted order, runs each file via
  `nvim --headless -c "luafile <path>"`, parses the trailing RESULT line,
  and exits non-zero if any test failed.
- A hang in any test is guarded by `PER_TEST_TIMEOUT` (default 20 s, can
  be overridden on the env).

## Writing a new test fixture
- Pick the closest existing test (`setter`, `main_c`, `main_lua`,
  `edge`, `queries`) and mimic its setup style.
- Use one fresh buffer per scenario so per-buffer state never leaks.
- If the test exercises a `@semicolon` insert, attach BEFORE you simulate
  the user keypress so `state.last_line_count` records the pre-event
  baseline (this mirrors what the production `TextChangedI` autocmd
  observes).
- For multi-line paste scenarios, prefer a count-based assertion
  (e.g. "exactly one new `;` added") over pinning a specific line -- the
  produced line depends on cursor-influenced `parent_node:range()`.

## Running
```
bash tests/run.sh                # the whole suite (43/43 when current)
PER_TEST_TIMEOUT=60 bash tests/run.sh
bash tests/run.sh tests/test_main_c.lua   # run just one
```
A failing RESULT line tells you which file, but you can re-run any one
file directly with `nvim --headless -c "luafile tests/<file>.lua"`.

# Install / Development Gotcha
When you clone *tree-setter* into something like `~/.local/share/nvim/site/pack/local/start/tree-setter/`, Neovim **shadows** your working tree with the installed copy on the next launch. If your edits don't seem to take effect, the install is stale:

```sh
# resolve where Neovim is actually loading the plugin from
:lua print(vim.fn.systemlist({"readlink","-f", package.loaded["tree-setter.main"] and require("tree-setter.main") and ""}))
# or simply
:scriptnames
```

To develop against the working copy without re-installing on every change, point your runtimepath at it directly in your init.lua (before any other repo manager):

```lua
vim.opt.runtimepath:prepend("/absolute/path/to/your/tree-setter/checkout")
```

Then `:source %` after a Lua edit, or `:luafile lua/tree-setter/main.lua`, sees your local changes immediately. Without this, you may find yourself debugging a *ghost* copy from the pack dir.

