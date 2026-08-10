-- =====================
-- Global variables
-- =====================
local Setter = {}

-- ==============
-- Functions
-- ==============
--
-- What does it do?
--	This function adds the given terminator (`;`, `,`, or `:`) to a
--	buffer line in a way that does NOT clobber the user's other content.
--
-- Parameters:
--	@bufnr:   The buffer number (0 for current)
--	@line_num: 0-based row of the line to annotate
--	@end_column: tree-sitter's *end-exclusive*, 0-based column of the
--	             captured node (right after its last character)
--	@character: the punctuation to insert (`;`, `,`, or `:`)
--
-- Behaviour:
--  * Two line-level guards prevent insert-into-already-terminated and
--    insert-into-`)` (positions inside a closing paren -- the for-loop
--    `i++` case).
--  * For `;` and `,`: insert just the character at the END of `line_num`
--    via `nvim_buf_set_text`.  We DO NOT modify `line_num + 1`.  This is
--    the fix for the user-reported bug where pressing Enter after typing
--    `printf` inside a nested `for { if { ... } }` block would clobber
--    the user's pre-typed `}` closing braces on the next row.
--  * For `:` (case-statement body): if the next row is empty/whitespace,
--    perform the original 2-row `set_lines` replace with a deeper-indent
--    blank row, so the cursor lands cleanly inside the case body.  If
--    the user has already typed content on the next row (rare but possible),
--    fall back to the single-char `set_text` insertion so we never erase
--    their work.
function Setter.set_character(bufnr, line_num, end_column, character)
	-- default to the current buffer if none was given
	bufnr = bufnr or 0

	-- get the line where the character should (maybe) be added.
	local line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1] or ""
	-- and the next line, so the `:`-case-statement path can decide whether
	-- it's safe to insert a deeper-indented blank below without erasing
	-- the user's content (e.g. a typed `}`).
	local next_line = vim.api.nvim_buf_get_lines(bufnr, line_num + 1, line_num + 2, false)[1] or ""

	-- `end_column` is tree-sitter's *end-exclusive*, 0-based column of the
	-- captured node (one past the node's last char).  We use it for one
	-- guard (`next_character` below) but we DO NOT use it as the actual
	-- insertion column because the captured node can end mid-line (e.g.
	-- `printf(...)`'s `)` is the end of `expression_statement`, but the
	-- user may have trailing whitespace after it).  Insertion happens
	-- at `#line` (visual end-of-line) so the terminator sits at the
	-- end of what the user sees, matching the original `line .. char`
	-- semantics.
	--
	-- Guard 1 -- already-terminated: if the user's line already ends with
	-- the wanted character (modulo trailing whitespace), do nothing.
	-- Whole-statement captures (return_statement, expression_statement)
	-- have `end_column` past the existing `;`, so the historical
	-- `next_character == ''` check used to fire and re-add `;`, producing
	-- `return 0;;` or `printf(...);;`.  The trimmed-ends-with guard
	-- catches this regardless of where exactly `end_column` lands.
	--
	-- Guard 2 -- inside parens: if the character directly after the
	-- captured node is `)`, this is the for-loop `i++` capture --
	-- inserting `;` between `i++` and `)` would corrupt the statement.
	local next_character = line:sub(end_column + 1, end_column + 1)

	local trimmed = line:gsub("%s+$", "")
	if trimmed:sub(-1) == character then
		-- Line already terminates correctly.  Nothing to do.
		return
	end

	if trimmed:sub(-1) == "{" then
		-- A line ending with `{` opens a block (function body, struct,
		-- table, ...): a terminator right after `{` is always wrong, no
		-- matter which character is requested.  This is what keeps the
		-- function_definition query in queries/c/tsetter.scm safe -- it
		-- captures the declarator of EVERY function_definition, and this
		-- guard is what stops `bool f(int n) {` from turning into
		-- `bool f(int n) {;`.
		return
	end

	if next_character == ')' then
		-- Captured node lives inside a closing paren (e.g. `i++` in a for-loop).
		return
	end

	-- SPECIAL CASE for ':' (case-statement body).  After `case 5:` the
	-- user expects the cursor on a deeper-indented blank line.  Vim's
	-- cindent usually handles this, but we enforce it for safety AND
	-- match the historical tree-setter behaviour.  Critically, we only
	-- take this 2-row replace path when `line_num + 1` is empty or
	-- whitespace-only -- if the user has typed a `}` or any other
	-- content there, we MUST NOT overwrite it.  Falls back to the
	-- safe single-char set_text path below.
	if character == ':' and next_line:match("^%s*$") then
		local deeper_indent = (' '):rep(vim.fn.indent(line_num + 1) + vim.o.shiftwidth)
		vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 2, false,
		                           {line .. character, deeper_indent})
		return
	end

	-- DEFAULT (semicolon, comma, etc.): insert just the character at
	-- the end of `line_num`.  We do NOT modify `line_num + 1` -- the
	-- original 2-row set_lines was destroying the user's typed `}` and
	-- any auto-indented next line.  Vim's auto-indent handles the next
	-- line on its own.
	vim.api.nvim_buf_set_text(bufnr, line_num, #line, line_num, #line, {character})
end

return Setter
