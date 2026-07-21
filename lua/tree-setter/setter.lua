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
    local line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1]

    -- `end_column` is tree-sitter's *end-exclusive*, 0-based column of the
    -- captured node, i.e. it points right *after* the node's last character.
    -- Our punctuation (`;`/`,`/`:`) belongs exactly at that spot. In Lua's
    -- 1-based string indexing the character sitting in that spot is at index
    -- `end_column + 1`.
    --
    -- `next_character` is therefore what directly follows the captured node.
    -- We use it for two checks:
    --
    --  1. Avoid duplicates: if the wanted character is already there, don't
    --     add a second one, e.g. we mustn't turn
    --
    --          int a;   into   int a;;
    --
    --  2. Protect the *complete* for-loop case:
    --
    --          for (int var = 0; var < 10; var++)
    --
    --     Here the `var++` (an `update_expression`) is captured for a
    --     semicolon, but it lives *inside* the parentheses, so the character
    --     right after it is `)`. In that case we must NOT add a semicolon.
    --
    --  Note: we deliberately look at the character *after the node* and not at
    --  the last character of the whole line. Otherwise legitimate statements
    --  that simply end with a `)` -- like `printf("hello")` or `my_func()` --
    --  would wrongly be skipped too.
    local next_character = line:sub(end_column + 1, end_column + 1)

    -- is our character already placed, or are we inside a closing paren? If
    -- neither => Place it!
    if (next_character ~= character) and (next_character ~= ')') then
        -- we need the "+ 2" here, because:
        --  1. The column-index is *exclusive* => + 1
        --  2. We need to set even the next line with our new indentation => + 1
        vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 2, false,
                                   {line .. character, indent_fix})
    end
end

return Setter
