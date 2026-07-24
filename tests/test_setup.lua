-- tests/test_setup.lua
--
-- Tests for `setup({ disabled_languages = ... })`.  We drive the
-- real FileType autocmd registered by `init()` (via `doautocmd`)
-- and assert that side effects match the user's config.
--
-- Each scenario reloads `tree-setter` so the module-level `config`
-- starts from a known default; this mirrors what `tests/test_main_*.lua`
-- already do for the same isolation reason.

vim.defer_fn(function() vim.cmd("qa!") end, 8000)
pcall(vim.treesitter.language.add, "lua")

local function reload()
    for k, _ in pairs(package.loaded) do
        if k:match("^tree%-setter") then package.loaded[k] = nil end
    end
    return require("tree-setter")
end

local pass, fail = 0, 0

local function fmt(name, ok, got, want)
    if ok then
        return string.format("  %-50s PASS", name)
    end
    return string.format("  %-50s FAIL  (got=%q want=%q)", name, tostring(got), tostring(want))
end

-- Reusable: open a fresh `lang` buffer, fire FileType, simulate an
-- Enter past the only line, then run `main()`.  Returns the first
-- line of the buffer after the run.
local function press_enter_on(lang, first_line)
    local b = vim.api.nvim_create_buf(true, false)
    vim.bo[b].filetype = lang
    vim.api.nvim_set_option_value("modifiable", true, { buf = b })
    -- Make the buffer current so `doautocmd FileType` and the
    -- text-change handlers find a window.
    vim.api.nvim_set_current_buf(b)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { first_line })
    vim.cmd("doautocmd FileType")
    vim.api.nvim_buf_set_lines(b, 1, 1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local main_mod = require("tree-setter.main")
    main_mod.main(b)

    local got = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or ""
    main_mod.detach(b)
    return got
end

print("[setup -- back-compat: empty/no opts enables all languages]")

do
    local ts = reload()
    ts.setup()   -- legacy: no opts at all

    local got = press_enter_on("lua", "local x = 1")
    local ok = got == "local x = 1;"
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(fmt("setup() no args          lua enabled, ; added", ok, got, "local x = 1;"))
end

do
    local ts = reload()
    ts.setup({})   -- empty opts table

    local got = press_enter_on("lua", "local x = 1")
    local ok = got == "local x = 1;"
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(fmt("setup({})                lua enabled, ; added", ok, got, "local x = 1;"))
end

print()
print("[setup -- disabled_languages keeps the language quiet]")

do
    local ts = reload()
    ts.setup({ disabled_languages = { "lua" } })

    local got = press_enter_on("lua", "local x = 1")
    local ok = got == "local x = 1"
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(fmt("disabled={lua}           lua NOT attached (no ;)", ok, got, "local x = 1"))
end

print()
print("[setup -- case-insensitive matching]")

do
    local ts = reload()
    ts.setup({ disabled_languages = { "LUA" } })

    local got = press_enter_on("lua", "local x = 1")
    local ok = got == "local x = 1"
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(fmt("disabled={LUA}           case-insensitive", ok, got, "local x = 1"))
end

print()
print("[setup -- one disabled, the other still works]")

-- Use a C parser independent fallback: the lua query is asked for in
-- the C test scenario indirectly via re-attachment, but here we
-- verify that disabling one language does NOT block attach for
-- other languages.  We use `lua` and `c` as the two differentiators
-- (C is the second language we test, supported in queries/c/).
pcall(vim.treesitter.language.add, "c")

do
    local ts = reload()
    ts.setup({ disabled_languages = { "lua" } })

    -- lua: should NOT get `;`
    local got_lua = press_enter_on("lua", "local x = 1")
    local ok_lua = got_lua == "local x = 1"

    -- c: should still get `;`
    local got_c = press_enter_on("c", "int x")
    local ok_c = got_c == "int x;"

    if ok_lua and ok_c then
        pass = pass + 1
        print(fmt("disabled={lua} only      lua quiet, c still adds ;", true, "lua=" .. got_lua .. " c=" .. got_c, "lua=local x=1 c=int x;"))
    else
        fail = fail + 1
        print(fmt("disabled={lua} only      lua quiet, c still adds ;", false,
            "lua=" .. got_lua .. " c=" .. got_c, "lua=local x=1 c=int x;"))
    end
end

print()
print("[setup -- late call replaces prior config]")

do
    local ts = reload()
    -- First setup() disables Lua, then re-enable it.  Verify the
    -- second call really replaces (not merges with) the first.
    ts.setup({ disabled_languages = { "lua" } })
    ts.setup({ disabled_languages = {} })

    local got = press_enter_on("lua", "local x = 1")
    local ok = got == "local x = 1;"
    if ok then pass = pass + 1 else fail = fail + 1 end
    print(fmt("setup twice              second call wins", ok, got, "local x = 1;"))
end

print()
print(string.format("RESULT pass=%d fail=%d", pass, fail))
if fail ~= 0 then vim.cmd("cq!") else vim.cmd("qa!") end
