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

-- Look if tree-setter supports the current language by checking if there's an
-- appropriate query file for it. For example if we're currently editing a C
-- file, then this function looks if there's a `queries/c/tsetter.scm` file.
local function is_supported(lang)
    return lang ~= nil and vim.treesitter.query.get(lang, "tsetter") ~= nil
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

            -- Languages without a query file mustn't break the plugin: just
            -- don't attach in that case.
            if not is_supported(lang) then
                return
            end

            main.attach(bufnr, lang)
        end,
    })
end

-- `setup` is a common convention nowadays, so we expose it as an alias for
-- `init` in case users prefer to call it that way.
function M.setup()
    M.init()
end

return M
