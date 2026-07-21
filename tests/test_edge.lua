-- tests/test_edge.lua
--
-- Edge-case tests for Enter detection (the heuristic `line_count grew`):
--
--   - Multi-line paste (delta > 1): main() runs once, only the FIRST matching
--     statement gets punctuation (matches historical single-statement semantics).
--   - `o` opening a line (delta == 1 from a cursor-on-empty-after-O): triggers.
--   - Deleting lines (`dd` / backspace joining): line_count DROPS.  `main()` is
--     a no-op.
--   - Re-attach on the same buffer number after detach must not leak state.
--
-- These complement the positive tests in test_main_c.lua / test_main_lua.lua.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "c")
pcall(vim.treesitter.language.add, "lua")

for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")

local pass, fail = 0, 0

local function fresh_buf(filetype)
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = filetype
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  return b
end

print("[Multi-line paste: delta > 1, exactly one `;` per TC]")
do
  local b = fresh_buf("c")
  -- Initial buffer: 3 incomplete declarations + a trailing blank (4 lines).
  -- All four declarations are bare (no `;`), so tree-sitter can still
  -- recognise the file as a translation_unit -- it just emits four
  -- `declaration` nodes whose declarators will all match `@semicolon`.
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int a", "int b", "int c", "" })
  main_mod.attach(b, "c")
  local semi_before = 0
  for _, ln in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
     if ln:match(";") then semi_before = semi_before + 1 end
  end
  -- Paste 2 more incomplete declarations.
  vim.api.nvim_buf_set_lines(b, -1, -1, false, { "int d", "int e" })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local semi_after = 0
  for _, ln in ipairs(lines) do
     if ln:match(";") then semi_after = semi_after + 1 end
  end
  -- Invariant: main() runs ONCE per TC, and our add_character early-returns
  -- after the first successful set_character, so exactly ONE new `;` is
  -- added regardless of how many incomplete statements exist.
  local delta = semi_after - semi_before
  local ok = (delta == 1)
  if ok then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s  (delta_semicolons=%d, expected 1)",
    "paste w/ N incomplete statements: exactly one `;` per TC",
    ok and "PASS" or "FAIL", delta))
end

print()
print("[o/O opening a line: delta == 1, triggers (same path as Enter)]")
do
  local b = fresh_buf("c")
  -- Attach BEFORE simulating `o`, so state.last_line_count reflects the
  -- pre-`o` count (1 line).  If we attach after the simulated `o`, the
  -- baseline is already 2 and the `o`-induced delta is invisible.
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int a" })
  main_mod.attach(b, "c")
  -- Simulate `o`: neovim inserts a new blank line below the current line
  -- and positions the cursor there.
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  local got_first = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
  local ok = got_first == "int a;"
  if ok then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s  (got=%q want=%q)",
    "`o` after `int a` triggers ;",
    ok and "PASS" or "FAIL", got_first, "int a;"))
end

print()
print("[dd / backspace across lines: line_count drops, MUST NO-OP]")
do
  local b = fresh_buf("c")
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int a", "int b", "" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  main_mod.attach(b, "c")
  -- Simulate `dd` (delete current line so line_count drops 3 -> 2).
  vim.api.nvim_buf_set_lines(b, 2, 3, false, {})
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  -- Buffer should not have a stray `;` injected.
  local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  local all_clean = true
  for _, ln in ipairs(lines) do
     if ln:match(";") then all_clean = false; break end
  end
  if all_clean then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s",
    "dd does NOT spuriously insert `;`",
    all_clean and "PASS" or "FAIL"))
end

print()
print("[Backspace joining two lines: line_count drops, MUST NO-OP]")
do
  local b = fresh_buf("c")
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int a", "int b", "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.attach(b, "c")
  -- Simulate backspace at col 0 of line 2 -> joined with line above.
  -- We model this as "append line 2's content to line 1 and remove line 2".
  local line2 = vim.api.nvim_buf_get_lines(b, 1, 2, false)[1] or ""
  vim.api.nvim_buf_set_lines(b, 0, 1, false, { "int a" .. line2 })
  vim.api.nvim_buf_set_lines(b, 1, 2, false, {})
  vim.api.nvim_win_set_cursor(0, { 1, 5 })
  main_mod.main(b)
  main_mod.detach(b)
  local all_clean = not (vim.api.nvim_buf_get_lines(b, 0, -1, false)[1] or ""):match(";")
  if all_clean then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s",
    "backspace-join does NOT spuriously insert `;`",
    all_clean and "PASS" or "FAIL"))
end

print()
print("[Re-attach after detach on same bufnr: state is fresh]")
do
  local b = fresh_buf("c")
  -- First cycle: 1 line in pre-Enter state, attach, then add the blank line
  -- so the delta-vs-baseline gate fires on main().  Cursor is set AFTER
  -- the insert to mirror real nvim's `<CR>` behaviour (vim moves the
  -- cursor to the new blank line).  Our row anchor is `cursor_row - 1`,
  -- so the cursor MUST be at the post-Enter blank for the test to align.
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int a" })
  main_mod.attach(b, "c")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  local after_first = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""

  -- Second cycle: detach cleared the per-buffer state, so re-attach starts
  -- a fresh baseline on `int b`.  Cursor after the insert (mirrors `<CR>`).
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "int b" })
  main_mod.attach(b, "c")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  local after_second = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""

  local ok = (after_first == "int a;") and (after_second == "int b;")
  if ok then pass = pass + 1 else fail = fail + 1 end
  print(string.format("  %-50s %s  (after_first=%q after_second=%q)",
    "re-attach + Enter on a different statement still works",
    ok and "PASS" or "FAIL", after_first, after_second))
end

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
