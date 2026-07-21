-- tests/test_main_rust.lua
--
-- End-to-end tests for the Rust query file.  Same pattern as test_main_lua.lua:
-- fresh buffer per scenario, attach/bump/main/detach.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)

-- If the Rust parser isn't installed, skip gracefully (same pattern as
-- test_queries.lua).  The pcall on `language.add` succeeds on some nvim
-- builds even when the parser binary is missing, so we also guard
-- `query.get` with a pcall.
local add_ok = pcall(vim.treesitter.language.add, "rust")
local q_ok, q = pcall(vim.treesitter.query.get, "rust", "tsetter")
if not add_ok or not q_ok or not q then
   print("Rust parser or query not available -- SKIP all")
   print("RESULT pass=0 fail=0")
   vim.cmd("qa!")
end

for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")

-- Sanity check: the loaded module must come from this repo, not a stale install.
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

local pass, fail = 0, 0

local function run(name, body, want)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "rust"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { body })
  main_mod.attach(b, "rust")
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

-- Helper for multi-line scenarios, same pattern as test_main_c.lua.
local function run_multi(name, source_lines, mutations, cursor_1based, expected_first_n)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "rust"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, source_lines)
  main_mod.attach(b, "rust")
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

print("[Rust @semicolon -- positive]")
run("let x = 1",                   "let x = 1",               "let x = 1;")
run("let x = a + b",               "let x = a + b",           "let x = a + b;")
run("my_func()",                    "my_func()",               "my_func();")

print()
print("[Rust @comma -- struct fields]")
-- Struct field declarations use `,` as separator, not `;`.
-- Both single-line (run_scenario equivalent) and multi-line (run_multi)
-- forms are tested.
run_multi("struct Point { x: i32 }   + ,",
  {
    "struct Point {",
    "    x: i32",
    "    y: i32,",
    "}",
  },
  { { 2, "" } },          -- Enter after `x: i32` (insert blank at 0-based row 2)
  3,                       -- cursor on 1-based line 3 (the post-Enter blank)
  {
    "struct Point {",
    "    x: i32,",          -- should get comma
    "",                     -- the post-Enter blank, untouched
    "    y: i32,",
    "}",
  })

print()
print("[Rust @skip -- negative (unchanged)]")
run("if x > 0 {  (skip)",           "if x > 0 {",             "if x > 0 {")
run("while true {  (skip)",         "while true {",           "while true {")
run("fn foo(  (skip)",              "fn foo(",                "fn foo(")

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
