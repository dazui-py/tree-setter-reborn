-- =================
-- Requirements
-- =================
-- all functions, which can modify the buffer, like adding the semicolons and
-- commas
local setter = require("tree-setter.setter")

-- =====================
-- Global variables
-- =====================
-- this variable is also known as `local M = {}` which includes the stuff of the
-- module
local TreeSetter = {}

-- Per-buffer state. Since tree-setter can be attached to multiple buffers (with
-- possibly different languages) at the same time, we musn't share a single
-- global query or line-number across buffers. Otherwise the query of one buffer
-- could leak into another buffer.
--
-- `states[bufnr]` looks like this:
--      {
--          query = <the tsetter query for this buffer's language>,
--          -- the last line num where the cursor was. It's mainly used as a
--          -- control variable to check if the cursor moved down or not (see
--          -- `TreeSetter.main`).
--          last_line_num = <number>,
--      }
local states = {}

-- ==============
-- Functions
-- ==============
function TreeSetter.add_character(bufnr, state)
    -- Make sure the tree reflects the current buffer content before we ask for
    -- the node under the cursor. Calling `get_node` on a stale/unparsed tree
    -- can yield an invalid node.
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
        return
    end
    parser:parse()

    -- get the relevant nodes to be able to judge the current case (if we need
    -- to add a semicolon/comma/... or not).
    --
    -- We intentionally don't pass a `bufnr` here: `get_node` then defaults to
    -- the current buffer and uses the window-local cursor position. Since the
    -- `CursorMovedI` autocommand is buffer-local, the buffer we were attached
    -- to is guaranteed to be the current one at this point.
    local curr_node = vim.treesitter.get_node()
    if not curr_node then
        return
    end

    local parent_node = curr_node:parent()
    if not parent_node then
        parent_node = curr_node
    end

    -- Reduce the searching-range on the size of the parent node (and not the
    -- whole buffer)
    local start_row, _, end_row, _ = parent_node:range()
    -- since the end row is end-*exclusive*, we have to increase the end row by
    -- one
    end_row = end_row + 1

    local query = state.query

    -- iterate through all matched queries from the given range.
    --
    -- Note: with the native treesitter API, `match` maps each capture id to a
    -- *list* of nodes (`table<integer, TSNode[]>`), so we have to iterate over
    -- the inner list as well.
    for _, match, _ in query:iter_matches(parent_node, bufnr, start_row, end_row) do
        for id, nodes in pairs(match) do
            for _, node in ipairs(nodes) do

                -- get the "coordinations" of our current line, where we have to
                -- lookup if we should add a semicolon or not.
                local char_start_row, _, _, char_end_column = node:range()

                -- get the type of character which we should add.
                -- So for example if we have "@semicolon" in our query, than
                -- "character_type" will be "semicolon", so we know that there
                -- should be a semicolon at the end of the line
                local character_type = query.captures[id]

                -- so look first, if we reached an "exception" which have the
                -- "@skip" predicate.
                if character_type == "skip" then
                    return
                end

                -- Add the given character to the given line
                if character_type == 'semicolon' then
                    setter.set_character(bufnr, char_start_row, char_end_column, ';')
                elseif character_type == 'comma' then
                    setter.set_character(bufnr, char_start_row, char_end_column, ',')
                elseif character_type == 'double_points' then
                    setter.set_character(bufnr, char_start_row, char_end_column, ':')
                end
            end
        end
    end
end

-- The main-entry point. Here we are checking the movement of the user and look
-- if we need to look if we should add a semicolon/comma/... or not.
function TreeSetter.main(bufnr)
    local state = states[bufnr]
    if not state then
        return
    end

    local line_num = vim.api.nvim_win_get_cursor(0)[1]

    -- look if the user pressed the enter key by checking if the line number
    -- increased. If yes, look if we have to add the semicolon/comma/etc. or
    -- not.
    if state.last_line_num < line_num then
        TreeSetter.add_character(bufnr, state)
    end

    -- refresh the old cursor position
    state.last_line_num = line_num
end

function TreeSetter.attach(bufnr, lang)
    -- Don't attach twice to the same buffer.
    if states[bufnr] then
        return
    end

    local query = vim.treesitter.query.get(lang, "tsetter")
    -- Languages without a query file mustn't break the plugin.
    if not query then
        return
    end

    states[bufnr] = {
        query = query,
        last_line_num = 0,
    }

    -- Use a buffer-local autocommand so we only react to cursor movement in
    -- buffers where tree-setter is actually attached.
    local augroup = vim.api.nvim_create_augroup("TreeSetter_" .. bufnr, { clear = true })

    vim.api.nvim_create_autocmd("CursorMovedI", {
        group = augroup,
        buffer = bufnr,
        callback = function()
            require("tree-setter.main").main(bufnr)
        end,
    })

    -- Clean up our state when the buffer is unloaded/deleted so we don't leak
    -- memory and so a re-used buffer number starts fresh.
    vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete" }, {
        group = augroup,
        buffer = bufnr,
        callback = function()
            TreeSetter.detach(bufnr)
        end,
    })
end

function TreeSetter.detach(bufnr)
    states[bufnr] = nil
    pcall(vim.api.nvim_del_augroup_by_name, "TreeSetter_" .. bufnr)
end

return TreeSetter
