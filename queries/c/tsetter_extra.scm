;; ===================
;; Extra Queries (optional)
;; ===================
;; This file is loaded SEPARATELY from tsetter.scm (see
;; lua/tree-setter/main.lua) and is kept in its own file so that a grammar
;; version mismatch here can NEVER break the base query.
;;
;; `macro_type_specifier` only exists in tree-sitter-c >= 0.21: on those
;; grammars a line like
;;
;;      free(ptr)
;;
;; parses as a macro used as a type specifier, so the base query's
;; call_expression patterns don't match it and we need this pattern to add
;; the `;`.  On older grammars the node type doesn't exist, the whole file
;; fails to parse, and the plugin simply skips it -- there `free(ptr)` is a
;; plain call_expression already covered by queries/c/tsetter.scm.
((macro_type_specifier
    name: (_)
    type: (_)
) @semicolon)
