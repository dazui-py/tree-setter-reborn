-- =====================
-- Global variables
-- =====================
local Setter = {}

-- ==============
-- Functions
-- ==============
--
-- What does it do?
--	This function adds the given character to the end of the line.
--  
-- Parameters:
--	@bufnr: The buffer number where to change it (0 for current)
--	@line_num: The line number where the character should be added to
--	@character: The character which should be added to the line (if it's not
--	there yet)
--
function Setter.set_character(bufnr, line_num, end_column, character)
    -- since we're changing the previous line (after hitting enter) vim
    -- will move the indentation of the current line as well. This
    -- variable stores the indent of the previous line which will be
    -- added after adding the given line with the semicolon/comma/double
    -- point.
    -- We are doing `line_num + 1` because remember: Lua indexes start with 1!
    -- So if `line_num` is 1, we are referring to the first line!
    local indent_fix = (' '):rep(vim.fn.indent(line_num + 1))

    -- default to the current buffer if none was given
    bufnr = bufnr or 0

    -- We have an exception if the character is ':', because suppose you write
    -- something like this ("|" represents the cursor):
    --  
    --      case 5:|
    --
    -- If you hit enter now, than your cursor should land like this:
    --
    --      case 5:
    --          |
    --
    -- and not this:
    --
    --      case 5:
    --      |
    -- 
    -- so we have to add the indent given by the `shiftwidth` option
    -- as well!
    if character == ':' then
        indent_fix = indent_fix .. (' '):rep(vim.o.shiftwidth)
    end

    -- get the line where the character should (maybe) be added.
    local line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1] or ""

    -- `end_column` is tree-sitter's *end-exclusive*, 0-based column of the
    -- captured node, i.e. it points right *after* the node's last character.
    -- Our punctuation (`;`/`,`/`:`) belongs exactly at that spot. In Lua's
    -- 1-based string indexing the character sitting in that spot is at index
    -- `end_column + 1`.
    --
    -- We use TWO independent guards against mis-insertion:
    --
    --  1. **Already-terminated** (defensive, line-level): if the user's line
    --     ALREADY ends with the character we want to insert (modulo trailing
    --     whitespace), do nothing. This matters because our C / Lua queries
    --     capture *whole-statement* nodes (e.g. `expression_statement`,
    --     `return_statement`) whose tree-sitter range already INCLUDES the
    --     existing terminator.  When the dispatcher picks such a node,
    --     `end_column` can be *past* the `;` -- the old "next character ==
    --     wanted character" check then saw an empty string and decided to
    --     insert another `;`, producing `return 0;;` and other corrupting
    --     edits.  The line-level trimmed-ends-with guard catches this case
    --     regardless of where exactly `end_column` lands.
    --
    --  2. **Inside parentheses** (positional, the for-loop case): if the
    --     character directly after the captured node is `)`, do nothing. The
    --     captured `i++` in `for (int i = 0; i < 10; i++)` falls here, and
    --     adding a `;` would corrupt a complete statement.
    --
    --  Note (1) is line-level so legitimate statements that simply end with a
    --  `)` -- like `printf("hello")` or `my_func()` -- still receive their `;`,
    --  because their LINE doesn't end with `;` even though the captured
    --  `call_expression` does not span the closing `)`.
    local next_character = line:sub(end_column + 1, end_column + 1)

    local trimmed = line:gsub("%s+$", "")
    if trimmed:sub(-1) == character then
        -- Line already terminates correctly.  Nothing to do.
        return
    end

    if next_character == ')' then
        -- Captured node lives inside a closing paren (e.g. `i++` in a for-loop).
        return
    end

    -- we need the "+ 2" here, because:
    --  1. The column-index is *exclusive* => + 1
    --  2. We need to set even the next line with our new indentation => + 1
    vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 2, false,
                               {line .. character, indent_fix})
end

return Setter
