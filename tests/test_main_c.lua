-- tests/test_main_c.lua
--
-- End-to-end tests for C language: drive the same code path that the
-- TextChangedI autocmd uses (attach() -> mutate buffer -> main()).
-- Uses one fresh buffer per scenario so per-buffer state never leaks between
-- scenarios.
--
-- Note: we bypass the autocmd and call main_mod.main(bufnr) directly.  This
-- sidesteps the headless TextChangedI timing but exercises EXACTLY the
-- production logic the autocmd would.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "c")

-- The case-statement test expects a specific deeper-indent width.
-- Pin shiftwidth so the expected value is deterministic.
vim.o.shiftwidth = 4

-- Make sure the local repo (not a stale install) is loaded.
for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")
local loader   = require("tree-setter")

-- Sanity: the loaded module must come from this repo, not a stale install.
-- We resolve symlinks by shelling out to `readlink -f`, which works on every
-- POSIX system and avoids relying on either `vim.fs.realpath` (missing in
-- older nvim) or `vim.fn.resolve` (which doesn't accept arguments in this
-- nvim build's vim.fn interface).
local function realpath(p)
  return (vim.fn.systemlist({ "readlink", "-f", p })[1] or ""):gsub("\n$", "")
end

do
  local src = debug.getinfo(main_mod.main, "S").source or ""
  local actual_path = realpath(src:gsub("^@", ""))
  local expected_path = realpath("/home/dazuii/tree-setter-reborn/lua/tree-setter/main.lua")
  if expected_path == "" or actual_path ~= expected_path then
    print("FATAL: tree-setter.main loaded from: " .. src)
    print("       expected (resolved): " .. expected_path)
    print("       (see README's 'Developing' section to symlink the repo into")
    print("        pack/core/start/ -- a stale install is shadowing your edits)")
    vim.cmd("cq!")
  end
end

local pass, fail = 0, 0

-- Helper: create a fresh scratch buffer, attach tree-setter with the
-- buffer in its PRE-Enter state (just the source line), then simulate the
-- Enter keypress by inserting a blank line BELOW.  This mirrors the
-- production autocmd path: attach() captures line_count=1, Enter grows it
-- to 2 (delta=1), main() fires and processes.
local function run_scenario(name, body, want_first_line)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { body })
  main_mod.attach(b, "c")                       -- pre-Enter baseline = 1
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })  -- simulate <CR>: add the blank line
  local ok = pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  if not ok then
    print(string.format("  %-50s SKIP (no window)", name))
    return
  end

  main_mod.main(b)
  main_mod.detach(b)

  local got = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
  local ok = got == want_first_line
  if ok then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s  (got=%q want=%q)",
    name, ok and "PASS" or "FAIL", got, want_first_line))
end

-- Helper for multi-line scenarios with explicit mutations.  `mutations` is
-- a list of {pos_0based, line} where pos_0based=-1 means "append at end";
-- otherwise the mutation inserts `line` AT row pos_0based (range [pos,
-- pos) -> [pos, pos+1)), shifting existing rows down.  `cursor_1based` is
-- the 1-based cursor position after all mutations -- mirrors what nvim
-- would do for a real <CR> in insert mode.
local function run_multi(name, source_lines, mutations, cursor_1based, expected_first_n)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, source_lines)
  main_mod.attach(b, "c")
  for _, mut in ipairs(mutations) do
    if mut[1] == -1 then
      vim.api.nvim_buf_set_lines(b, -1, -1, false, { mut[2] })
    else
      vim.api.nvim_buf_set_lines(b, mut[1], mut[1], false, { mut[2] })
    end
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { cursor_1based, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  local got = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local same = true
  for i, want in ipairs(expected_first_n) do
    if got[i] ~= want then
      same = false
      print(string.format("    line %d mismatch: got=%q want=%q", i, got[i] or "<missing>", want))
    end
  end
  if same then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s", name, same and "PASS" or "FAIL"))
end

print("[C @semicolon -- positive]")
run_scenario("int value",                   "int value",        "int value;")
run_scenario("printf(\"hello\")",            'printf("hello")',   'printf("hello");')
run_scenario("my_func()",                   "my_func()",        "my_func();")
run_scenario("return 0",                    "return 0",         "return 0;")
run_scenario("indented decl",               "    int x = 5",    "    int x = 5;")
run_scenario("declaration with assignment", "int x = a + b",    "int x = a + b;")

print()
print("[C @skip -- negative]")
-- `if (test()` parses as ERROR and the (@skip) rule covers it -> main() should
-- return without modifying the line.
run_scenario("if (test()  (skip)",          "if (test()",       "if (test()")
run_scenario("while (x < 10)  (skip)",      "while (x < 10)",   "while (x < 10)")
run_scenario("for (int i=0;  (skip)",        "for (int i=0;",    "for (int i=0;")
-- complete for-loop (parsed as for_statement, NOT ERROR): tree-sitter captures
-- the `i++` update_expression whose next-character is `)`, the setter guards
-- on that, so nothing happens.
run_scenario("complete for(...)",           "for (int i = 0; i < 10; i++)",
                                              "for (int i = 0; i < 10; i++)")

print()
print("[Bug 1: forward-decl vs function-def-with-brace]")
-- Regression tests for the user's bug 1 report.  Two interpretations:
--   (a) `bool isPrime(int n)` is a forward declaration -> needs `;`.
--   (b) `bool isPrime(int n) {` is a function-definition opening -> must
--       stay untouched (the `{` already opens the body; `;` after `{` would
--       corrupt the pending definition).
-- Both pass under the post-fix iter_matches scope (1-line buffer pre-attach
-- sets state.last_line_count = 1, target_row = 0 = the typing row).
run_scenario("bool isPrime(int n)         + ;",
              "bool isPrime(int n)",
              "bool isPrime(int n);")
run_scenario("bool isPrime(int n) {       unchanged",
              "bool isPrime(int n) {",
              "bool isPrime(int n) {")

-- =============================================================
-- Empty parameter lists: `void test()`, `int main()`, `bool f()`, etc.
-- Tree-sitter C wraps these in an ERROR node (they're parsed as
-- primitive_type + function_declarator, not declaration + declarator).
-- A dedicated ERROR-wrapped function_declarator query is needed to
-- capture them (see queries/c/tsetter.scm).
-- =============================================================

-- Without braces: should all get `;` (forward declarations).
print()
print("[Empty-param function declarations  + ;]")
run_scenario("void test()                  + ;",
              "void test()",
              "void test();")
run_scenario("int test()                   + ;",
              "int test()",
              "int test();")
run_scenario("char test()                  + ;",
              "char test()",
              "char test();")
run_scenario("float test()                 + ;",
              "float test()",
              "float test();")
run_scenario("double test()                + ;",
              "double test()",
              "double test();")
run_scenario("long test()                  + ;",
              "long test()",
              "long test();")
run_scenario("bool isPrime()               + ;",
              "bool isPrime()",
              "bool isPrime();")

-- With braces: function definitions must stay untouched (the `{` opens the body).
print()
print("[Empty-param function-def-with-brace  unchanged]")
run_scenario("void test() {                unchanged",
              "void test() {",
              "void test() {")
run_scenario("int main() {                 unchanged",
              "int main() {",
              "int main() {")
run_scenario("char test() {                unchanged",
              "char test() {",
              "char test() {")
run_scenario("bool isPrime() {             unchanged",
              "bool isPrime() {",
              "bool isPrime() {")

-- =============================================================
-- More prototype return types: typedef names, struct returns,
-- pointer returns, qualified types.  All should get `;`.
-- =============================================================
print()
print("[More prototype return types  + ;]")
run_scenario("struct S test()            + ;",
              "struct S test()",
              "struct S test();")
run_scenario("my_type test()             + ;",
              "my_type test()",
              "my_type test();")
run_scenario("unsigned int test()        + ;",
              "unsigned int test()",
              "unsigned int test();")
run_scenario("int *test()                + ;",
              "int *test()",
              "int *test();")
run_scenario("const char *test()         + ;",
              "const char *test()",
              "const char *test();")

-- Pointer return types: the signature nests one pointer_declarator level
-- per `*`.  The plugin resolves ANY depth in Lua (resolve_func_decl() in
-- lua/tree-setter/main.lua) instead of enumerating query branches.  In the
-- plain 2-line shape tree-sitter's error recovery also collapses any
-- pointer depth into a single ERROR wrapper, so these all work.
run_scenario("int **test()                + ;",
              "int **test()",
              "int **test();")
run_scenario("const char **test()         + ;",
              "const char **test()",
              "const char **test();")
run_scenario("int ***test()               + ;",
              "int ***test()",
              "int ***test();")
run_scenario("int ****test()              + ;",
              "int ****test()",
              "int ****test();")
-- Definition-with-brace variant of the new 2-level branch: the `{` guard in
-- the setter must keep it untouched.
run_scenario("int **test() {              unchanged",
              "int **test() {",
              "int **test() {")
run_scenario("int ***test() {             unchanged",
              "int ***test() {",
              "int ***test() {")

-- =============================================================
-- Function prototypes typed ABOVE an already-existing function
-- definition (the user's real flow: write main() first, then go
-- back up and add the prototype).  Tree-sitter merges the
-- prototype with the definition below into one ERROR or
-- function_definition node; the queries must still pin `;` to
-- the prototype's own row, never touching the `{` line below.
-- =============================================================
print()
print("[Prototype typed above an existing function  + ;]")
local protomain = { "int main() {", "    return 0;", "}" }
run_multi("bool proto above main        + ; on proto",
  { "bool isPrime(int n)", unpack(protomain) },
  { { 1, "" } },           -- Enter after the prototype (insert blank at row 1)
  2,                       -- cursor on 1-based line 2 (the post-Enter blank)
  { "bool isPrime(int n);", "", "int main() {", "    return 0;", "}" })
run_multi("int proto above main         + ; on proto",
  { "int test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int test();", "", "int main() {", "    return 0;", "}" })
run_multi("void proto above main        + ; on proto",
  { "void test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "void test();", "", "int main() {", "    return 0;", "}" })
run_multi("empty-param proto above main + ; on proto",
  { "bool isPrime()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "bool isPrime();", "", "int main() {", "    return 0;", "}" })
run_multi("multi-arg proto above main   + ; on proto",
  { "int test(int a, char b)", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int test(int a, char b);", "", "int main() {", "    return 0;", "}" })
run_multi("ptr proto above main         + ; on proto",
  { "int *test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int *test();", "", "int main() {", "    return 0;", "}" })
run_multi("ptr-ptr proto above main     + ; on proto",
  { "int **test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int **test();", "", "int main() {", "    return 0;", "}" })

-- Pointer return types typed above an existing definition: the @func_decl
-- query capture is resolved to the innermost parameter_list in Lua, so ANY
-- pointer depth works here too (no per-depth query branches needed).
run_multi("ptr-ptr-ptr proto above main + ; on proto",
  { "int ***test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int ***test();", "", "int main() {", "    return 0;", "}" })
run_multi("ptr^4 proto above main       + ; on proto (any depth)",
  { "int ****test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "int ****test();", "", "int main() {", "    return 0;", "}" })

-- Regression (code review): an unterminated parameterized proto sitting
-- ABOVE a definition must NOT be annotated when the user presses Enter on a
-- LOWER line.  During the merge the @func_decl wrapper declarator spans
-- rows 0..2; the resolved parameter_list's OWN range (row 0) is what must
-- reach the row filter, otherwise `;` would land two rows above the edit.
run_multi("Enter on main() line  proto above stays unchanged",
  { "bool isPrime(int n)", "", "int main() {" },
  { { -1, "" } },        -- Enter at the end of `int main() {` (append blank)
  4,                     -- cursor on 1-based line 4 (the new blank)
  { "bool isPrime(int n)", "", "int main() {", "" })
run_multi("unsigned proto above main    + ; on proto",
  { "unsigned int test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "unsigned int test();", "", "int main() {", "    return 0;", "}" })
run_multi("struct proto above main      + ; on proto",
  { "struct S test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "struct S test();", "", "int main() {", "    return 0;", "}" })
run_multi("typedef proto above main     + ; on proto",
  { "my_type test()", unpack(protomain) },
  { { 1, "" } },
  2,
  { "my_type test();", "", "int main() {", "    return 0;", "}" })

-- The user's exact flow: main() with a real body already typed below,
-- prototype added afterwards.  `;` must land on the prototype only.
run_multi("user flow: bool proto above body  + ; on proto",
  { "bool isPrime(int n)", "int main() {", "    printf(\"hello\")", "    return 0;", "}" },
  { { 1, "" } },
  2,
  { "bool isPrime(int n);", "", "int main() {", "    printf(\"hello\")", "    return 0;", "}" })
run_multi("user flow: void proto above body  + ; on proto",
  { "void test()", "int main() {", "    printf(\"hello\")", "    return 0;", "}" },
  { { 1, "" } },
  2,
  { "void test();", "", "int main() {", "    printf(\"hello\")", "    return 0;", "}" })

print()
print("[Bug 2 regression: cursor far below an unterminated if-body + Enter]")
-- Exact scenario from the user's bug 2 report: an unterminated printf
-- inside an if, a complete `return 0;` further down, the cursor sits on
-- a fresh blank line far below everything, and pressing Enter must NOT
-- touch any of the well-formed lines.  Pre-fix this corrupted
-- `return 0;` with a duplicate `;` and replaced the `}` line with the
-- indent_fix whitespace, effectively erasing `}`.
run_multi("cursor far below  no `}` deletion  no `;;`",
  {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\")",  -- missing ; inside if (the bug 2 trigger)
    "    }",
    "    return 0;",
    "}",
    "appendix;",
  },
  { { -1, "" } },          -- simulate Enter on a fresh blank line below EVERYTHING
  8,                       -- post-Enter cursor at 1-based line 8 (the new blank)
  {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\")",  -- still missing ; -- cursor is far below, no annotation
    "    }",
    "    return 0;",              -- NOT `    return 0;;`
    "}",                          -- NOT `    ` (indent_fix leaked pre-fix)
    "appendix;",
  })

-- Companion: cursor DIRECTLY ON the unterminated printf's blank-below
-- (the realistic Enter mid-printf flow).  Insert the blank BETWEEN
-- printf and `}` so the setter's `set_lines(b, 2, 4, ...)` correctly
-- touches only the printf + the new blank, leaving `}` untouched.
run_multi("cursor mid-printf       + ; on printf, `}` intact",
  {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\")",  -- missing ;
    "    }",
  },
  { { 3, "" } },           -- insert blank at 0-based row 3 == between printf and `}`
  4,                       -- cursor on 1-based line 4 (the new blank)
  {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\");",  -- gets the ;
    "",                            -- the manually-inserted blank, untouched by set_text
    "    }",                       -- `}` shifted down, intact
  })

-- =============================================================
-- Regression: nested for/if/printf from tests/test.c.
-- The user typed the nested block, then pressed Enter after `printf`.
-- Pre-fix symptoms were (1) the printf line got `;;` instead of `;`,
-- and (2) the `}` of the if-block AND the `}` of the for-block were
-- DELETED.  Post-fix: only printf gets `;`; the if's `}`, the for's
-- `}`, and main's `}` all stay untouched.
-- =============================================================
run_multi("  nested for/if/printf  only printf gets ;  `}` intact",
  {
    "#include <stdio.h>",
    "#include <stdbool.h>",
    "",
    "bool isPrime(int n);",
    "",
    "int main(){",
    "    for (int i = 0; i <= 100; i++) {",
    "        if(isPrime(i)){",
    "            printf(\"%d\\n\", i)",     -- missing ;
    "        }",
    "    }",
    "}",
  },
  { { 9, "" } },                       -- Enter after printf (insert blank at 0-based row 9)
  10,                                   -- cursor on 1-based line 10 (the post-Enter blank)
  {
    "#include <stdio.h>",
    "#include <stdbool.h>",
    "",
    "bool isPrime(int n);",
    "",
    "int main(){",
    "    for (int i = 0; i <= 100; i++) {",
    "        if(isPrime(i)){",
    "            printf(\"%d\\n\", i);",  -- got ;
    "",                            -- the post-Enter blank, untouched by set_text
    "        }",                       -- if's `}` intact
    "    }",                         -- for's `}` intact
    "}",                           -- main's `}` intact
  })

-- =============================================================
-- Regression: top-down editing after a bottom-up session from tests/test2.c.
-- The user wrote `int main(){ ... return 0; ... }` first, then went
-- back UP and added `printf(...)` on a body row mid-file, then
-- pressed Enter.  Pre-fix: plugin missed the `;` because its row
-- anchor came from `state.last_line_count - 1` (which matched the
-- bottom of the file, not the line the user just edited).  Post-fix:
-- row anchor is `cursor_row - 1`, the line ABOVE the post-Enter
-- cursor, which pins printf regardless of where in the file it lives.
-- =============================================================
run_multi("  top-down edit after bottom-up  printf gets ;",
  {
    "#include <stdio.h>",
    "",
    "int main(){",
    "    printf(\"Hello, World!\")",   -- missing ;
    "",
    "",
    "",
    "",
    "",
    "    return 0;",
    "",
    "",
    "",
    "}",
  },
  { { 4, "" } },                       -- Enter after printf (insert blank at 0-based row 4)
  5,                                   -- cursor on 1-based line 5 = post-Enter blank
  {
    "#include <stdio.h>",
    "",
    "int main(){",
    "    printf(\"Hello, World!\");",  -- got ;
    "",                                -- the post-Enter blank, untouched
    "",                                -- an extra blank pushed down by the new blank
    "",
    "",
    "",
    "",
    "    return 0;",                     -- intact
    "",
    "",
    "",
    "}",
  })

print()
print("[Additional C regression tests]")

-- =============================================================
-- Multi-arg function definition with body brace: must stay untouched.
-- `bool isPrime(int n, int k) {` is a function_definition; the query
-- deliberately does NOT capture function_definition for @semicolon.
-- =============================================================
run_scenario("bool isPrime(int n, int k) { unchanged",
              "bool isPrime(int n, int k) {",
              "bool isPrime(int n, int k) {")

-- Multi-arg forward declaration (no body brace): should get semicolon.
-- Parsed as `declaration` by tree-sitter, captured by the (declaration)
-- query regardless of how many parameters.
run_scenario("bool isPrime(int n, int k)   + ;",
              "bool isPrime(int n, int k)",
              "bool isPrime(int n, int k);")

-- =============================================================
-- Struct member declaration: `int x` inside a struct body.
-- Tree-sitter C represents struct members as `field_declaration`
-- nodes, NOT `declaration` nodes.  Whether this test passes depends
-- on whether the current queries or error-recovery path capture it.
-- =============================================================
run_multi("struct member decl            + ; on field",
  {
    "struct Point {",
    "    int x",
    "    int y;",
    "};",
  },
  { { 2, "" } },          -- Enter after `int x` (insert blank at 0-based row 2)
  3,                       -- cursor on 1-based line 3 (the post-Enter blank)
  {
    "struct Point {",
    "    int x;",            -- should get ;
    "",                      -- the post-Enter blank, untouched
    "    int y;",
    "};",
  })

-- =============================================================
-- Multi-arg printf call: a function call with several arguments
-- should still get `;` just like a single-arg printf.
-- =============================================================
run_scenario('printf("sum: %d", a, b)   + ;',
              'printf("sum: %d", a, b)',
              'printf("sum: %d", a, b);')

print()
print("[C edge cases -- setter guards & reentrancy]")

-- =============================================================
-- Already-terminated line: a line that already ends with `;`
-- must NOT get a double semicolon when Enter is pressed after it.
-- Tests the setter's `trimmed:sub(-1) == character` guard.
-- =============================================================
run_multi("already has ;  no double ;;",
  {
    "int x;",
  },
  { { 1, "" } },           -- Enter after `int x;` (insert blank at 0-based row 1)
  2,                        -- cursor on 1-based line 2 (the post-Enter blank)
  {
    "int x;",                -- unchanged: no double ;;
    "",                       -- the post-Enter blank
  })

-- =============================================================
-- Update expression `i++`: tree-sitter captures the `i++` argument
-- whose next-character is `)`.  The setter's inside-paren guard must
-- skip the insertion, otherwise `i++;)` corrupts the for-loop.
-- =============================================================
run_multi("i++  inside for  skip ;",
  {
    "for (int i = 0; i < 10; i++)",
  },
  { { 1, "" } },
  2,
  {
    "for (int i = 0; i < 10; i++)",  -- unchanged
    "",
  })

-- =============================================================
-- Update expression on its own line (standalone `i++`): should get `;`.
-- =============================================================
run_scenario("i++ standalone              + ;",
              "i++",
              "i++;")

-- =============================================================
-- Double Enter, real reentrancy: insert first blank → main() →
-- insert second blank → main().  The first main() sets
-- `state.applying = true` (and schedules a deferred reset).
-- The second main() must return immediately because `applying`
-- is still true, preventing an insertion loop.  After both calls
-- the line must have exactly ONE `;`.
-- =============================================================
do
  local name = "double Enter  reentrancy guard"
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int x" })
  main_mod.attach(b, "c")                       -- last_line_count = 1

  -- First Enter: insert a blank below, call main().
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  main_mod.main(b)                              -- adds ;, sets applying = true

  -- Second Enter (before the deferred reset fires): insert another blank.
  vim.api.nvim_buf_set_lines(b, 2, 2, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 3, 0 })
  main_mod.main(b)                              -- must be a no-op (applying guard)

  main_mod.detach(b)
  local got = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local want = { "int x;", "", "" }
  local same = true
  for i = 1, 3 do
    if got[i] ~= want[i] then
      same = false
      print(string.format("    line %d mismatch: got=%q want=%q", i, got[i] or "<missing>", want[i]))
    end
  end
  if same then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s", name, same and "PASS" or "FAIL"))
end

-- =============================================================
-- Trailing whitespace: `int x   ` with trailing spaces should
-- still get `;`.  The setter strips trailing whitespace for the
-- guard check but inserts at #line (end of line), so `;` goes
-- after the spaces.
-- =============================================================
run_scenario("trailing spaces             + ;",
              "int x   ",
              "int x   ;")

print()
print("[C edge cases -- special types & macros]")

-- `long x` is captured by the `sized_type_specifier` query.
run_scenario("long x                      + ;",
              "long x",
              "long x;")

-- `unsigned int x` is a declaration with a sized_type_specifier type.
run_scenario("unsigned int x              + ;",
              "unsigned int x",
              "unsigned int x;")

-- `free(ptr)` is captured by the expression_statement > call_expression query.
run_scenario("free(ptr)                   + ;",
              "free(ptr)",
              "free(ptr);")

-- `break` without semicolon: tree-sitter sees it as ERROR containing "break".
run_scenario("break                       + ;",
              "break",
              "break;")

print()
print("[C edge cases -- case statement & buffer isolation]")

-- =============================================================
-- Case statement: `case 1` should get `:` (double_points), not `;`.
-- The setter's `:` path does a 2-row set_lines for the deeper indent.
-- =============================================================
run_multi("case 1  -> case 1:",
  {
    "switch(x) {",
    "    case 1",
    "}",
  },
  { { 2, "" } },           -- Enter after `case 1` (insert blank at 0-based row 2)
  3,                        -- cursor on 1-based line 3 = post-Enter blank
  {
    "switch(x) {",
    "    case 1:",            -- should get : (not ;)
    "        ",               -- deeper-indented blank (shiftwidth=4 here)
    "}",
  })

-- =============================================================
-- Row scoping: two adjacent declarations.  Only the line above
-- the cursor gets annotated; the other is outside the row window.
-- =============================================================
run_multi("adjacent decls  only cursor-row gets ;",
  { "int x", "int y" },
  { { 1, "" } },      -- Enter after "int x"
  2,
  { "int x;", "", "int y" })

-- =============================================================
-- Reverse buffer isolation: attach Lua first, then `:e` to C.
-- The differentiator is `break`: Lua doesn't capture `break` at
-- all, while C captures `ERROR "break" @semicolon` and adds `;`.
-- Pre-fix: Lua query would persist after :e to C, and `break`
-- would NOT get `;`.  Post-fix: C query takes over, `break;`.
-- =============================================================
print()
print("[Reverse isolation: Lua -> C via :e]")
do
  local name = "Lua -> C via :e  C query takes over, break + ;"
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()

  -- Step 1: attach as Lua, set Lua content.
  vim.bo[b].filetype = "lua"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "local x = 1" })
  main_mod.attach(b, "lua")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  main_mod.main(b)       -- Lua query in use

  -- Step 2: simulate `:e` to C -- replace content, filetype changes, re-attach.
  vim.bo[b].filetype = "c"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "break" })
  main_mod.attach(b, "c")      -- pre-fix: no-op (states[b] existed with lang="lua")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  main_mod.main(b)       -- post-fix: C query used; break -> break;

  main_mod.detach(b)
  local got = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
  -- Pre-fix bug: Lua query doesn't capture break, so got = "break"
  -- Post-fix: C query `ERROR "break" @semicolon` makes got = "break;"
  if got == 'break;' then
    pass = pass + 1
    print(string.format("  %-50s PASS", name))
  else
    fail = fail + 1
    print(string.format("  %-50s FAIL  (got=%q want='break;')", name, got))
  end
end

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
