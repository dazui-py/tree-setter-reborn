-- The main module of tree-setter.
--
-- Instead of relying on the (now removed) `nvim-treesitter.define_modules`
-- framework, we hook directly into Neovim's native treesitter API. We set up a
-- `FileType` autocommand which, for each buffer, checks if there's an
-- appropriate query file for the current language (for example
-- `queries/c/tsetter.scm` for a C file). If a query exists, we attach
-- tree-setter to that buffer.

local main = require("tree-setter.main")

local M = {}

-- ------------------------------------------------------------------
-- User config
-- ------------------------------------------------------------------
-- `config` holds the user-configurable knobs set by `setup(opts)`.
-- `init()` reads them when registering the FileType autocommand.
--
-- Defaults are conservative: `disabled_languages = {}` keeps the
-- plugin attached to every supported language, which is the same
-- behaviour as before this option existed (so users who do NOT call
-- `setup(...)` keep the legacy behaviour).
--
-- Fields:
--
--   disabled_languages : table<integer, string>
--     A list of tree-sitter language names (case-insensitive) that
--     tree-setter must NOT attach to.  Compared against the value
--     returned by `vim.treesitter.language.get_lang(...)` -- the
--     RESOLVED language name, not the raw `&filetype`.
--
--     Common values: `"c"`, `"cpp"`, `"lua"`, `"python"`, `"rust"`.
--
--     Example:
--
--         require("tree-setter").setup({
--             disabled_languages = { "lua", "rust" },
--         })
--
--     Notes:
--       * Calling `setup({})` or `setup()` is equivalent to an empty
--         `disabled_languages` list (legacy behaviour: attach to
--         every supported language).
--       * Subsequent calls to `setup()` REPLACE the previous config
--         entirely (so toggling a language off and back on later is
--         a single-line change in user init.lua).
--       * Keys are stored lower-cased so user typos in case don't
--         silently do nothing.
local config = {
    disabled_languages = {},
}

-- True iff `lang` has a `queries/<lang>/tsetter.scm` file AND is not
-- in `config.disabled_languages`.  Anything in the disabled list
-- short-circuits even if a query exists -- useful for users who
-- keep the query file in-tree but want the plugin to leave that
-- buffer alone on their machine.
local function is_enabled(lang)
    if lang == nil then
        return false
    end
    if config.disabled_languages[lang:lower()] then
        return false
    end
    return vim.treesitter.query.get(lang, "tsetter") ~= nil
end

-- Coerce a user-provided `disabled_languages` value into the
-- internal set shape `{[lowercase_name] = true}`.  Returns `{}` and
-- emits a single warning when the input is structurally wrong,
-- because a typo at startup should not silently disable EVERYTHING
-- (we'd rather fall back to the legacy "attach everywhere" mode).
local function to_disabled_set(list)
    if list == nil then
        return {}
    end
    if type(list) ~= "table" then
        vim.api.nvim_echo({
            { "tree-setter: disabled_languages must be a list of strings; got " .. type(list), "WarningMsg" },
        }, true, {})
        return {}
    end
    local set = {}
    for i, name in ipairs(list) do
        if type(name) == "string" then
            set[name:lower()] = true
        else
            vim.api.nvim_echo({
                {
                    string.format(
                        "tree-setter: disabled_languages[%d] must be a string; got %s",
                        i, type(name)
                    ),
                    "WarningMsg",
                },
            }, true, {})
        end
    end
    return set
end

function M.init()
    local augroup = vim.api.nvim_create_augroup("TreeSetter", { clear = true })

    vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        callback = function(args)
            local bufnr = args.buf

            -- Get the treesitter language for the current filetype. This might
            -- differ from the filetype itself (e.g. filetype `svg` -> lang
            -- `xml`).
            local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)

            -- Skip both:
            --   (a) languages without a query file (don't break the plugin),
            --   (b) languages the user disabled via setup().
            if not is_enabled(lang) then
                return
            end

            main.attach(bufnr, lang)
        end,
    })
end

-- User-facing configuration entry point.
--
-- `setup(opts)` applies the user's config and then registers the
-- FileType autocmd via `init()`.  Calling `setup()` (no arguments)
-- preserves the legacy behaviour (every supported language attached).
--
-- Currently supported keys:
--
--   * `disabled_languages`: list of language names to NEVER attach.
--
-- Calling `setup(opts)` a second time FULLY REPLACES the previous
-- config (so toggling a language on or off later is just a one-line
-- change in user init.lua).  It also re-creates the TreeSetter
-- augroup, so the new `disabled_languages` takes effect for any
-- buffer that opens from that point onward.
function M.setup(opts)
    opts = opts or {}
    config.disabled_languages = to_disabled_set(opts.disabled_languages)
    M.init()
end

return M
