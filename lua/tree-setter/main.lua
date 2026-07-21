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
--          -- the number of lines the buffer had after we last processed a
--          -- change. It's used to detect whether the *user* inserted a new
--          -- line (i.e. pressed enter / opened a line) since the last text
--          -- change (see `TreeSetter.main`).
--          last_line_count = <number>,
--          -- reentrancy guard: while we are applying our own edit we mustn't
--          -- react to the `TextChangedI` event it triggers, otherwise we'd
--          -- risk an insertion loop.
--          applying = <boolean>,
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

    -- iterate through all matched queries from the given range, then dispatch
    -- the *most-derived* match per character_type.
    --
    -- Note: with the native treesitter API, `match` maps each capture id to a
    -- *list* of nodes (`table<integer, TSNode[]>`), so we have to iterate over
    -- the inner list as well.
    --
    -- Why "most-derived" instead of "first hit": `pairs(match)` is unordered
    -- -- if we returned after the first match we'd insert a `,` on a random
    -- field of a multi-field table constructor, not on the last one above
    -- the cursor.  The same hazard exists for any future capture that fires
    -- on more than one node per range.  We therefore collect ALL matches,
    -- then pick the bottommost (largest (end_row, end_col)) per capture-
    -- type, so a single Enter always produces exactly one edit on the line
    -- right above the cursor.
    --
    -- `@skip` keeps its early-return semantics so a skip inside the
    -- range always wins.
    local best_for_type = {}  -- capture_name -> {node, end_row, end_col}

    for _, match, _ in query:iter_matches(parent_node, bufnr, start_row, end_row) do
        for id, nodes in pairs(match) do
            for _, node in ipairs(nodes) do
                local _, _, end_row, end_col = node:range()
                local capture_name = query.captures[id]

                -- `@skip` beats every other match inside the range.
                if capture_name == "skip" then
                    return
                end

                -- Among same-name captures, keep the one furthest down (or
                -- rightmost on the same row).  Use a tuple comparison so that
                -- nodes on different rows are ranked by row first, col second
                -- -- column alone is a no-op tiebreaker when two fields sit
                -- at the same indent on different lines.
                local cur = best_for_type[capture_name]
                if not cur then
                    best_for_type[capture_name] = { node = node, end_row = end_row, end_col = end_col }
                elseif end_row > cur.end_row or (end_row == cur.end_row and end_col > cur.end_col) then
                    best_for_type[capture_name] = { node = node, end_row = end_row, end_col = end_col }
                end
            end
        end
    end

    -- Dispatch the chosen matches.  Priority between different capture
    -- names: `@comma` first (multi-field tables are the most likely to
    -- accidentally match more than one node), then `@semicolon`, then
    -- `@double_points`.  We unpack each entry once into local variables
    -- so the dispatch is one straight line of `if`-statements.
    local function apply(capture_name, char)
        local entry = best_for_type[capture_name]
        if not entry then return end
        local char_start_row, _, _, char_end_column = entry.node:range()
        setter.set_character(bufnr, char_start_row, char_end_column, char)
    end

    if best_for_type.comma then
        apply('comma', ',')
    elseif best_for_type.semicolon then
        apply('semicolon', ';')
    elseif best_for_type.double_points then
        apply('double_points', ':')
    end
end

-- The main-entry point. It's called on every insert-mode text change and
-- decides whether the user just inserted a new line (e.g. by pressing enter)
-- and, if so, whether we should add a semicolon/comma/... to the line above.
--
-- We deliberately react to `TextChangedI` (an actual text mutation) instead of
-- cursor movement. This way pure navigation (arrow keys, PageUp/PageDown,
-- switching buffers/windows) never triggers us, because none of those change
-- the buffer text.
function TreeSetter.main(bufnr)
    local state = states[bufnr]
    if not state then
        return
    end

    -- Ignore the text change caused by our own edit, otherwise we could end up
    -- in an insertion loop.
    if state.applying then
        return
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)

    -- A new line was inserted (enter, `o`, `O`, ...) only if the total number
    -- of lines grew. Plain typing keeps the line count the same, so we don't
    -- react to it.
    if line_count > state.last_line_count then
        -- Guard against reacting to the `TextChangedI` event that our own edit
        -- will emit.
        state.applying = true
        local ok, err = pcall(TreeSetter.add_character, bufnr, state)
        -- Reset the guard *after* the resulting `TextChangedI` has been
        -- processed. Scheduling defers it to the next event-loop tick, where
        -- we also re-sync `last_line_count` against the post-edit buffer.
        -- We intentionally do NOT update `last_line_count` synchronously
        -- here: the value we just read is the *pre-edit* count and would
        -- be stale until the buffer settles.
        vim.schedule(function()
            local s = states[bufnr]
            if s then
                s.applying = false
                if vim.api.nvim_buf_is_valid(bufnr) then
                    s.last_line_count = vim.api.nvim_buf_line_count(bufnr)
                end
            end
        end)
        if not ok then
            require("tree-setter.logger").error("failed to add character: " .. tostring(err))
        end
    else
        -- No new line: just refresh the tracked count so plain typing and
        -- deletions keep the diff baseline current.
        state.last_line_count = line_count
    end
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
        last_line_count = vim.api.nvim_buf_line_count(bufnr),
        applying = false,
    }

    -- Use a buffer-local autocommand so we only react to text changes in
    -- buffers where tree-setter is actually attached.
    local augroup = vim.api.nvim_create_augroup("TreeSetter_" .. bufnr, { clear = true })

    -- `TextChangedI` fires whenever the text is changed in insert mode. That's
    -- exactly what we want: navigation-only events (arrow keys, PageUp/Down,
    -- buffer/window switches) don't mutate text and therefore don't fire it.
    vim.api.nvim_create_autocmd("TextChangedI", {
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
