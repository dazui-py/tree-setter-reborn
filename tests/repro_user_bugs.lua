-- tests/repro_user_bugs.lua
--
-- One-shot reproducer for the two bugs the user reported (and that
-- post-fix commits address in lua/tree-setter/main.lua + setter.lua):
--   1. `bool isPrime(int n)` followed by Enter does nothing.  The user's
--      bug had two interpretations: the forward-decl form correctly gets
--      `;` today, while the function-def-with-brace form correctly
--      stays untouched (we don't add `;` after `{`).
--   2. When the cursor sits on a line far below an unterminated
--      `printf(...)` inside an `if (...) {`, pressing Enter used to
--      delete a `}` further down and add `;` to the wrong line.
--      Post-fix it does nothing because iter_matches is now scoped to
--      the user's pre-Enter row plus the row above.
--
-- This file is intentionally NOT in tests/run.sh; it's a debug probe.
-- Invoke it headless with:  nvim --headless -c 'luafile tests/repro_user_bugs.lua'

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "c")

for k, _ in pairs(package.loaded) do
   if k:match("^tree%-setter") then package.loaded[k] = nil end
end
local main_mod = require("tree-setter.main")

local function dump(label, b)
  print("  [" .. label .. "]")
  for i, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
    print(string.format("    %2d: %q", i, l))
  end
end

-- =====================================================================
-- Bug 1: `bool isPrime(int n)` (forward declaration) gets a `;` on Enter;
-- `bool isPrime(int n) {` (function-definition opening) does NOT.
-- Both use a realistic 1-line pre-attach buffer so state.last_line_count = 1
-- matches the actual user keypress (cursor at end of line 1, Enter adds
-- line 2).  Iteration scope: row 0 = the typing line.
-- =====================================================================
print("===================================================================")
print("Bug 1: bool isPrime(int n) + Enter (forward decl -> gets ;)")
print("===================================================================")
do
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "bool isPrime(int n)" })
  dump("before", b)
  main_mod.attach(b, "c")
  -- Real keypress: cursor at end of line 1, press Enter.
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  dump("after", b)
end

print()
print("===================================================================")
print("Bug 1 (alt): bool isPrime(int n) { + Enter (function-def -> untouched)")
print("===================================================================")
do
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "bool isPrime(int n) {" })
  dump("before", b)
  main_mod.attach(b, "c")
  vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  dump("after", b)
end

-- =====================================================================
-- Bug 2: cursor far below an unterminated printf inside an if.
-- Reproduces "cursor moves to a line further down + Enter + } gets
-- deleted" the user reported.  After the fix, iter_matches is scoped
-- to the user's pre-Enter row plus the row above, so the well-formed
-- `return 0;` and `}` further down are not touched.
-- =====================================================================
print()
print("===================================================================")
print("Bug 2: cursor far below if-with-printf-no-semicolon + Enter")
print("===================================================================")
do
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\")",  -- missing semicolon, inside if
    "    }",
    "    return 0;",
    "}",
    "appendix;",
    "",                          -- cursor here, user presses Enter
  })
  dump("before", b)
  main_mod.attach(b, "c")
  -- Simulate Enter on the last empty line: insert a blank, push cursor.
  vim.api.nvim_buf_set_lines(b, -1, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 9, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  dump("after", b)
end

-- =====================================================================
-- Bug 2 close variant: cursor directly on the printf line's blank-below.
-- In real usage, pressing <CR> at the end of printf inserts a blank
-- BETWEEN printf and `}`.  The setter then writes the `;`-terminated
-- printf + an indented fresh blank, leaving the `}` line alone.
-- =====================================================================
print()
print("===================================================================")
print("Bug 2b: cursor mid-printf + Enter (printf gets ;, `}` intact)")
print("===================================================================")
do
  vim.cmd("enew!")
  local b = vim.api.nvim_get_current_buf()
  vim.bo[b].filetype = "c"
  vim.api.nvim_set_option_value("modifiable", true, { buf = b })
  vim.api.nvim_buf_set_lines(b, 0, -1, false, {
    "int main() {",
    "    if (x) {",
    "        printf(\"hello\")",  -- missing semicolon
    "    }",
    "    return 0;",
  })
  dump("before", b)
  main_mod.attach(b, "c")
  -- Real Enter mid-printf: insert blank at 0-based row 3 right after printf.
  vim.api.nvim_buf_set_lines(b, 3, 3, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  main_mod.main(b)
  main_mod.detach(b)
  dump("after", b)
end

print()
print("DONE")
vim.cmd("qa!")
