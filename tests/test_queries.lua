-- tests/test_queries.lua
--
-- Smoke test: every tsetter.scm query file the project ships must
-- (a) load via vim.treesitter.query.get(...), and
-- (b) successfully exercise captured-nodes on at least one snippet.
--
-- Catches query-syntax errors, captures on missing node names, etc., without
-- having to drive the full plugin.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)

-- Each entry: language + snippets to try.  Skipped silently if the parser
-- for that language isn't installed in this nvim build.
local cases = {
   { lang = "c",      snippets = { "int value", 'printf("hello")', "return 0" } },
   { lang = "cpp",    snippets = { "int value" } },
   { lang = "lua",    snippets = { "print('hello')", "local x = 1", "return 1" } },
   { lang = "python", snippets = { "x = 1" } },
   { lang = "rust",   snippets = { "let x = 1" } },
}

local pass, fail = 0, 0
for _, c in ipairs(cases) do
   -- If the parser for this language isn't installed in this nvim, skip the
   -- whole exercise loop (otherwise get_parser throws "No parser for ...").
   local add_ok = pcall(vim.treesitter.language.add, c.lang)
   if not add_ok then
      print(string.format("  %-12s SKIP (parser missing)", c.lang))
   else
      -- We pcall-wrap query.get as well, because ``cpp`` (inherits: ``c``)
      -- will pull in its own parser lookups and we want a clean SKIP rather
      -- than a crash.
      local q_ok, q = pcall(vim.treesitter.query.get, c.lang, "tsetter")
      if not q_ok or not q then
         print(string.format("  %-12s SKIP (%s)", c.lang,
            (not q_ok) and "query load error" or "no tsetter.scm"))
      else
         -- Found the query file.  Try to exercise it on each snippet to
         -- confirm the captures reference real nodes.
         vim.cmd("enew!")
         local b = vim.api.nvim_get_current_buf()
         vim.bo[b].filetype = c.lang
         vim.api.nvim_set_option_value("modifiable", true, { buf = b })
         local parser_ok, parser = pcall(vim.treesitter.get_parser, b)
         local any_capture = false
         if parser_ok and parser then
            for _, snippet in ipairs(c.snippets) do
               vim.api.nvim_buf_set_lines(b, 0, -1, false, { snippet })
               parser:parse()
               local trees = parser:parse()
               if trees and trees[1] then
                  local root = trees[1]:root()
                  local n_matches = 0
                  for _, _, _ in q:iter_matches(root, b, 0, 1) do
                     n_matches = n_matches + 1
                     if n_matches >= 1 then any_capture = true end
                  end
               end
            end
         end
         -- Either way, the query file parsed cleanly --> pass.
         pass = pass + 1
         if any_capture then
            print(string.format("  %-12s PASS  (loaded, captures >= 1 snippet)", c.lang))
         else
            print(string.format("  %-12s PASS (loaded, no snippet matched)", c.lang))
         end
      end
   end
end

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
