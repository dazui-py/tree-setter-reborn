-- tests/test_main_lua.lua
--
-- End-to-end tests for Lua language: drive the same code path that the
-- TextChangedI autocmd uses (attach() -> mutate buffer -> main()).
-- Uses one fresh buffer per scenario so per-buffer state never leaks between
-- scenarios.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "lua")

-- Make sure the local repo (not a stale install) is loaded.
for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")
local loader   = require("tree-setter")

-- Sanity: the loaded module must come from this repo, not a stale install.
local function realpath(p)
  return (vim.fn.systemlist({ "readlink", "-f", p })[1] or ""):gsub("\\n$", "")
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

local function run_scenario(name, body, want_first_line)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "lua"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { body })
  main_mod.attach(b, "lua")                      -- pre-Enter baseline = 1
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

local function run_multi(name, source_lines, mutations, cursor_1based, expected_first_n)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "lua"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, source_lines)
  main_mod.attach(b, "lua")
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

print("[Lua @semicolon -- positive]")
run_scenario("local x = 1",               "local x = 1",      "local x = 1;")
run_scenario("x = 2",                     "x = 2",            "x = 2;")
run_scenario('print("hello")',           'print("hello")',   'print("hello");')
run_scenario("my_func()",                 "my_func()",        "my_func();")
run_scenario("return 1",                  "return 1",         "return 1;")
run_scenario("indented local",            "    local x = 5",  "    local x = 5;")
run_scenario("x = a + b",                 "x = a + b",        "x = a + b;")

print()
print("[Lua @semicolon -- negative / skip]")
-- Incomplete if: tree-sitter wraps in ERROR, @skip should fire.
run_scenario("if x then      (skip)",      "if x then",        "if x then")
-- Incomplete while.
run_scenario("while true do  (skip)",      "while true do",    "while true do")
-- Incomplete for.
run_scenario("for i=1,10 do  (skip)",      "for i=1,10 do",    "for i=1,10 do")
-- Incomplete repeat.
run_scenario("repeat         (skip)",      "repeat",           "repeat")
-- Incomplete do.
run_scenario("do             (skip)",      "do",               "do")

print()
print("[Lua no semicolon -- function defs and control flow]")
-- Function declarations must not get ; (Lua style).
run_scenario("function f() end  unchanged", "function f() end", "function f() end")
run_scenario("local function f() end unchanged",
              "local function f() end",
              "local function f() end")

-- Tables: table_constructor is not captured, but `t = { }` is an
-- assignment_statement which IS captured.  So `t = { }` gets `;`.
run_scenario("t = { }            + ;",       "t = { }",         "t = { };")

print()
print("[Lua buffer isolation -- attach then re-attach with different lang]")
-- Simulate user opening a C file, then doing `:e` to switch to Lua.
-- Pre-fix: the C query would stay active on the Lua buffer, adding
-- semicolons to Lua code in C style.  Post-fix: re-attach with the
-- new language must replace the old query with the Lua one.
--
-- We use `break` as the differentiator: the C query captures
-- `ERROR "break" @semicolon` and would add `;`, while the Lua
-- query has no `break` capture at all.  So with the old buggy
-- code, `break` in a Lua buffer would get `;` (C query leaks in).
-- With the fix, it stays as `break` (no `;`).
do
  local name = "C -> Lua via :e  Lua query takes over"
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()

  -- Step 1: attach as C, set C content.
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int x" })
  main_mod.attach(b, "c")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  main_mod.main(b)       -- C query in use

  -- Step 2: simulate `:e` — replace content, filetype changes, re-attach.
  vim.bo[b].filetype = "lua"
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "break" })
  main_mod.attach(b, "lua")    -- pre-fix: no-op (states[b] existed)
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  main_mod.main(b)       -- post-fix: Lua query used; break NOT captured

  main_mod.detach(b)
  local got = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
  -- Pre-fix bug: C query `ERROR "break" @semicolon` would make got = "break;"
  -- Post-fix: Lua query doesn't capture break, so got = "break"
  if got == 'break' then
    pass = pass + 1
    print(string.format("  %-50s PASS", name))
  else
    fail = fail + 1
    print(string.format("  %-50s FAIL  (got=%q want='break')", name, got))
  end
end

-- Test that @skip on the incomplete `if x then` line fires, but
-- `return 1` on the NEXT line is OUTSIDE the ERROR node (it's a
-- standalone return_statement) and should STILL get `;`.
-- This validates that the row window correctly scopes the @skip
-- to only the lines inside the ERROR node.
print()
print("[Lua ERROR skip -- scoped to error line only]")
run_multi("if x then (skip), return 1 + ;",
  { "if x then", "    return 1" },
  { { 2, "" } },     -- Enter after `return 1`
  3,
  { "if x then", "    return 1;", "" })

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
