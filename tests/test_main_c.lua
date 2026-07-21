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
-- complete for-loop (parsed as for_statement, NOT ERROR): tree-setter captures
-- the `i++` update_expression whose next-character is `)`, the setter guards
-- on that, so nothing happens.
run_scenario("complete for(...)",           "for (int i = 0; i < 10; i++)",
                                              "for (int i = 0; i < 10; i++)")

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
