-- tests/test_main_lua.lua
--
-- End-to-end tests for the Lua query file.  Same pattern as test_main_c.lua:
-- fresh buffer per scenario, attach/bump/main/detach.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "lua")

for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")

-- Sanity check: the loaded module must come from this repo, not a stale
-- install, AND the Lua queries file must load.
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
    vim.cmd("cq!")
  end
end

local q = vim.treesitter.query.get("lua", "tsetter")
if not q then
   print("FATAL: queries/lua/tsetter.scm failed to load (query.get returned nil).")
   vim.cmd("cq!")
end

local pass, fail = 0, 0

local function run(name, body, want)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "lua"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { body })
  main_mod.attach(b, "lua")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  local ok = pcall(vim.api.nvim_win_set_cursor, 0, { 2, 0 })
  if not ok then print(string.format("  %-50s SKIP no-window", name)); return end

  main_mod.main(b)
  main_mod.detach(b)

  local got = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
  local pass_ok = got == want
  if pass_ok then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s  (got=%q want=%q)",
    name, pass_ok and "PASS" or "FAIL", got, want))
end

print("[Lua @semicolon -- positive]")
run("local x = 1",                "local x = 1",          "local x = 1;")
run("local x = a + b",            "local x = a + b",      "local x = a + b;")
run("print('hello')",             "print('hello')",       "print('hello');")
run("my_func()",                  "my_func()",            "my_func();")
run("return 1",                   "return 1",             "return 1;")
run("bare assignment x = 2",      "x = 2",                "x = 2;")

print()
print("[Lua @skip -- negative (unchanged)]")
run("if x then  (skip)",          "if x then",            "if x then")
run("while true do  (skip)",      "while true do",        "while true do")
run("for i = 1, 10 do  (skip)",   "for i = 1, 10 do",     "for i = 1, 10 do")
run("do  (skip)",                 "do",                   "do")
run("function f(  (skip)",        "function f(",          "function f(")
run("repeat  (skip)",             "repeat",               "repeat")

print()
print("[Lua: NOT captured -- explicitly unchanged]")
-- Complete `local function f() end` parses as function_declaration.  The query
-- file deliberately does NOT capture it (Lua style: no `;` after `end`).
run("local function f() end",     "local function f() end", "local function f() end")
run("function f() end",           "function f() end",       "function f() end")

print()
print("[Lua @comma -- table constructors]  (deferred; see queries/lua/tsetter.scm)")
-- The @comma capture on `table_constructor` fields was prototyped but
-- caused real production regressions on multi-line unclosed tables: the
-- Lua grammar's `field:range()` for the LAST field of an unclosed
-- `table_constructor` is environment-sensitive across Lua grammar
-- versions.  Rather than ship a feature that turns `local t = {1, 2, 3}`
-- into `local t = {1, 2, 3,}` correctly on some hosts and
-- `local t = {1, 2, 3},` on others, we drop the capture and document
-- it as a future extension in the query file.
print("  (no @comma scenarios today)")

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
