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
--          lang  = <string: the treesitter language name>,
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

    -- Use the parse-tree ROOT for iter_matches, NOT the cursor's
    -- smallest-leaf's parent.  If we use the latter, iter_matches
    -- searches only inside that tiny subtree -- e.g. when the cursor
    -- sits inside `int d`, the parent is the `int d` declarator and
    -- captures on `int a/b/c` twenty rows above are simply invisible.
    -- The actual row scoping happens in `apply()` (post-filter on
    -- node:range() row values), so we WANT iter_matches to see the
    -- whole file and let the post-filter decide.
    --
    -- Calling `iter_matches(root_node, bufnr)` with the 2-arg form
    -- defaults to `root_node:range()` for start/stop, which is the
    -- cleanest "search the whole buffer" ask.
    local tree = parser:parse()[1]
    if not tree then
        return
    end
    local root_node = tree:root()
    if not root_node then
        return
    end

    -- Capture the user's pre-Edit row ONCE here: the line directly
    -- above the post-Enter cursor.  This works whether the user
    -- pressed Enter at the bottom of the buffer, in the middle,
    -- or near the top (e.g. top-down editing after a bottom-up
    -- session).  state.last_line_count only coincides with this
    -- when the user is at the bottom of the buffer, so it's NOT
    -- a reliable anchor -- the cursor is.
    --
    -- We resolve the window by `bufnr` rather than hard-coded 0 so
    -- the cursor we capture is the cursor IN THE BUFFER WE'RE
    -- ATTACHED TO, not whatever window happens to be current.
    -- If the buffer isn't visible in any window (rare but observable
    -- when a tab has only this buffer's augroup alive), bail.
    local win_id = vim.fn.bufwinid(bufnr)
    if win_id == -1 then
        return
    end
    local user_row = vim.api.nvim_win_get_cursor(win_id)[1] - 2

    local query = state.query

    -- iterate through all matched queries, then dispatch the most-derived
    -- match per character_type.
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

    -- `match[id]` can be a single TSNode (newer nvim) OR a list of TSNodes
    -- (older nvim).  We dispatch both shapes to a uniform `process(node)`
    -- closure so we don't crash on either build.
    for _, match, _ in query:iter_matches(root_node, bufnr) do
        for id, captured in pairs(match) do
            local function process(node)
                local start_row, _, end_row, end_col = node:range()
                local capture_name = query.captures[id]

                -- PRIMARY ROW FILTER (must be BEFORE the @skip check).
                --
                -- Only consider captures whose range overlaps the user's
                -- pre-Enter row ± 1 window.  Putting this filter first
                -- is critical: an `if (x) {` on row 5 must NOT short-
                -- circuit the plugin when the user is editing something
                -- 10 rows below.  Earlier versions of this code put
                -- `@skip` first, which made any skip anywhere in the
                -- buffer abort annotation globally -- the user's bug 2
                -- "cursor far below an if with unterminated printf"
                -- exposed this.
                --
                -- Also keeps bottommost-wins competition ENTER-WINDOW
                -- ONLY: an out-of-window `int e` cannot out-rank an in-
                -- window `int c` for the @semicolon slot in
                -- `best_for_type`.
                --
                -- `user_row` is captured ONCE at the top of
                -- `add_character` from the file-local cursor and stays
                -- constant across all captures within this dispatch.
                if end_row < user_row - 1 or start_row > user_row then
                    return  -- out of window; silent nil (NOT "skip")
                end

                -- `@skip` beats every other match -- but only for
                -- in-window captures, thanks to the filter above.
                if capture_name == "skip" then
                    return "skip"  -- sentinel that short-circuits the outer loops
                end

                -- Among same-name captures, keep the one furthest down (or
                -- rightmost on the same row).  Tuple comparison so nodes on
                -- different rows are ranked by row first, col second.
                local cur = best_for_type[capture_name]
                if not cur then
                    best_for_type[capture_name] = { node = node, end_row = end_row, end_col = end_col }
                elseif end_row > cur.end_row or (end_row == cur.end_row and end_col > cur.end_col) then
                    best_for_type[capture_name] = { node = node, end_row = end_row, end_col = end_col }
                end
            end

            if type(captured) == "userdata" then
                -- Modern nvim: match[id] is a single TSNode.
                if process(captured) == "skip" then return end
            elseif type(captured) == "table" then
                -- Older nvim: match[id] is a list of TSNodes.
                for _, node in ipairs(captured) do
                    if process(node) == "skip" then return end
                end
            end
            -- Anything else (number, string): silently skip; no capture to process.
        end
    end

    -- Dispatch the chosen matches.
    --
    -- ABOUT ROW SCOPING (single source of truth): the row-window filter
    -- is enforced inside `process()` above.  Don't redefine it here --
    -- doing so would create two competing sources of truth that future
    -- contributors will struggle to keep in sync.  If you need to widen
    -- or narrow the window, edit the filter in `process()` only.
    local function apply(capture_name, char)
        local entry = best_for_type[capture_name]
        if not entry then return end
        -- Single unpack of node:range() (4 ints: start_row, start_col,
        -- end_row, end_col). Subscripting the result of a function call
        -- (`entry.node:range()[1]`) is invalid in Lua: only the first
        -- multi-return value is taken and indexed, which crashes with
        -- `attempt to index a number value`. Always destructure.
        --
        -- end_row is intentionally bound (not dropped) to make it OBVIOUS
        -- that no row-scoped check is being suppressed here -- the row
        -- check is in `process()`.
        local node_start_row, _, node_end_row, char_end_col = entry.node:range()
        _ = node_end_row  -- see comment above
        setter.set_character(bufnr, node_start_row, char_end_col, char)
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
-- cursor movement. This way pure navigation (arrow keys, PageUp/Down,
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
    local state = states[bufnr]
    if state then
        -- Already attached to this buffer.  If the language changed (e.g.
        -- the user did `:e` from a C file to a Lua file in the same buffer
        -- slot), detach first so we re-attach with the correct query.
        -- Do NOT skip just because the buffer number is reused.
        if state.lang == lang then
            return
        end
        TreeSetter.detach(bufnr)
    end

    local query = vim.treesitter.query.get(lang, "tsetter")
    -- Languages without a query file mustn't break the plugin.
    if not query then
        return
    end

    states[bufnr] = {
        query = query,
        lang = lang,
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
