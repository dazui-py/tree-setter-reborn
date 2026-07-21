-- tests/test_setter.lua
--
-- Unit tests for lua/tree-setter/setter.lua.  We bypass attach/main entirely so
-- the tests run quickly and deterministically (no autocmds, no parser rounds,
-- no `vim.schedule`).  Each test just sets a buffer's lines and calls
-- Setter.set_character with explicit (row, end_column, character) arguments,
-- then inspects the result.
--
-- Hardening notes (post-audit):
--   * Tests share buffer 0 for speed; we snapshot+restore vim.o.shiftwidth
--     and any pre-existing autocmds per scenario so leftover state from a
--     prior case can't pollute the next one.
--   * Per-iteration `vim.defer_fn(qa!, 3000)` so a hang in one expect() can't
--     deadlock the whole file (the global 8 s guard at the top is a
--     back-stop).
--   * The case-5 block runs OUTSIDE expect() and owns its own shiftwidth
--     snap/restore so it is deterministic regardless of host env.

local setter = require("tree-setter.setter")
local pass, fail = 0, 0

-- Hard back-stop: if the script somehow stalls (autocmds, infinite loop)
-- a headless nvim hangs forever.  Anything inside an expect() should also
-- install its own per-iteration guard, but this top-level one ensures the
-- suite as a whole dies if we ever regress.
vim.defer_fn(function() vim.cmd("qa!") end, 8000)

-- Snapshot global options so each expect() can restore them and a leak
-- from a prior case can't bleed across files.  `setter.set_character`
-- doesn't touch these today, so this is forward-looking defensive code
-- for any future setter edits.
local function snapshot_env()
    return {
        shiftwidth = vim.o.shiftwidth,
        expandtab  = vim.o.expandtab,
        tabstop    = vim.o.tabstop,
    }
end

local function restore_env(snap)
    vim.o.shiftwidth = snap.shiftwidth
    vim.o.expandtab  = snap.expandtab
    vim.o.tabstop    = snap.tabstop
end

local function expect(name, buf_lines_before, ec, char, want_line_1)
    -- Per-iteration hang guard.
    vim.defer_fn(function() vim.cmd("qa!") end, 3000)

    local snap = snapshot_env()
    -- Force deterministic indent behaviour so the @double_points assertions
    -- below are reproducible across hosts.
    vim.o.shiftwidth = 4
    vim.o.expandtab = true

    -- Re-use the same single buffer so we don't allocate 30 buffers, but
    -- always reset to a known baseline.
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buf_lines_before)
    setter.set_character(0, 0, ec, char)
    local got = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or ""
    local ok = got == want_line_1
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(string.format("  %-50s %s  (got=%q want=%q)",
      name, ok and "PASS" or "FAIL", got, want_line_1))

    restore_env(snap)
end

print("[Positive @semicolon]")
expect("int value",                   { "int value",       "" }, 9,  ';', "int value;")
expect("printf('hello') (was broken)",{ 'printf("hello")', "" }, 15, ';', 'printf("hello");')
expect("my_func() (was broken)",      { "my_func()",       "" }, 9,  ';', "my_func();")
expect("return 0",                    { "return 0",        "" }, 8,  ';', "return 0;")
expect("indented decl",               { "    int x = 5",   "" }, 13, ';', "    int x = 5;")
expect("two decls on a line",         { "int a;int b;int c","" }, 13, ';', "int a;int b;int c;")

print()
print("[Negative @skip (setter sees ')' at end_column+1)]")
-- `i++` is captured by the C update_expression query at columns [24, 27)
-- (the bytes "i", "+", "+"), so end_column = 27 (one past the second '+').
-- The character at Lua index 28 is ')', so the next-character guard trips and
-- the setter must NOT add a ';'.
expect("for-loop i++ (inside parens)",
       { "for (int i = 0; i < 10; i++)", "" }, 27, ';',
       "for (int i = 0; i < 10; i++)")
expect("printf already-;",                  { 'printf("hello");', "" }, 15, ';', 'printf("hello");')
expect("my_func already-;",                 { "my_func();",       "" }, 9,  ';', "my_func();")
expect("int value already-;",               { "int value;",       "" }, 9,  ';', "int value;")

print()
print("[Indent-fix: @double_points (':')]")
-- This block runs OUTSIDE expect() so the restore_env() in expect() doesn't
-- apply; the case-5 test owns its own shiftwidth snap/restore so the result
-- is deterministic regardless of the host env.
local saved_sw  = vim.o.shiftwidth
local saved_et  = vim.o.expandtab
vim.o.shiftwidth = 4
vim.o.expandtab = true

-- With shiftwidth = 4 the setter computes indent_fix = "" (line 1's
-- `vim.fn.indent` = 0 because "case 5" has no leading whitespace) +
-- shiftwidth(4) (because character == ':') = "    " total.  So line 2
-- ends up with EXACTLY 4 spaces, not 8.  We assert that exact count.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "case 5", "" })
setter.set_character(0, 0, 7, ':')
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local got_l1, got_l2 = lines[1] or "", lines[2] or ""
local l1_ok = got_l1 == "case 5:"
local l2_ok = got_l2 == "    " -- 4 spaces: 0 (indent of "case 5") + shiftwidth(4)
if l1_ok and l2_ok then pass = pass + 2 else fail = fail + 2 end

vim.o.shiftwidth = saved_sw
vim.o.expandtab = saved_et
print(string.format("  case 5 -> %q         %s", got_l1, l1_ok and "PASS" or "FAIL"))
print(string.format("  case 5 indent_fix   %s  (got=%q, want %q)",
  l2_ok and "PASS" or "FAIL", got_l2, "    "))

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
