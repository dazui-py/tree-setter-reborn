;; ===================
;; Action Queries
;; ===================
;; --------------
;; Variables
;; --------------
;; A `local` declaration that has not been terminated with a semicolon.
;; Example:
;;      local x = 1
;;      local x = a + b
(variable_declaration) @semicolon

;; A bare (non-local) assignment that has not been terminated with a
;; semicolon.
;; Example:
;;      x = 2
(assignment_statement) @semicolon

;; --------------
;; Calls
;; --------------
;; A bare function call, including known (e.g. `print`) and unknown ones
;; (e.g. `my_func()`).
;; Example:
;;      print("hello")
;;      my_func()
(function_call) @semicolon

;; --------------
;; Control Flow
;; --------------
;; A `return` statement that has not been terminated with a semicolon.
;; Example:
;;      return 1
(return_statement) @semicolon

;; --------------
;; Tables  (deferred)
;; --------------
;; Multi-line `table_constructor` field detection was prototyped but caused
;; real production regressions: `field:range()` for the last field of an
;; unclosed table is environment-sensitive (different Lua grammar versions
;; extend the field past the closing `}` differently), and Lua's grammar
;; rejects the "match only the LAST field" query anchor pattern tree-sitter
;; supports.  Rather than ship a feature that breaks on common grammar
;; versions, we leave this as a future extension.  See CONTRIBUTING.md for
;; the required query-style guide when re-introducing it.
;;
;; Example pattern that did not work reliably:
;;      (table_constructor
;;          (field) @comma
;;      )


;; ==========
;; Skips
;; ==========
;; Skip incomplete block patterns that tree-sitter parses as `ERROR`.  We do
;; NOT add a semicolon to those lines -- otherwise we'd corrupt the user's
;; typing mid-header (e.g. `if x then;`).
;;
;; Examples covered by this rule:
;;      if x then
;;      while true do
;;      for i = 1, 10 do
;;      function f(
;;      repeat
;;      do
(ERROR ["if" "while" "for" "function" "repeat" "do"] @skip)

;; Skip function calls that live inside an ERROR node.  When the user types
;; `require('cord').setup {` and presses Enter before closing the table,
;; tree-sitter wraps the whole thing in ERROR.  The inner `require('cord')`
;; function_call is NOT a direct child of ERROR -- it sits inside a
;; `dot_index_expression`:
;;
;;   ERROR
;;     dot_index_expression
;;       function_call          <-- we want to skip this
;;     {                        <-- stray open brace
;;
;; Without this skip, the `(function_call) @semicolon` rule would match
;; that partial call and the setter would append `;` at the end of the
;; line (`require('cord').setup {;`).
(ERROR (dot_index_expression (function_call) @skip))


;; =============================================================================
;; Notes for future maintainers
;; =============================================================================
;; Lua semicolons are OPTIONAL.  This query file caters to users who follow a
;; strict trailing-semicolon style.  If a maintainer wants a more opinionated
;; behaviour, they may extend the captures below.
;;
;; We deliberately do NOT capture:
;;
;;   - `function_declaration` (@semicolon on a complete `function f() end`
;;     would put a `;` after `end`, which is unusual in Lua style).
;;
;;   - `table_constructor` fields / `@comma` between fields.  See the
;;     "Tables (deferred)" section above for the full rationale and an
;;     example of the proposed (but unreliable) capture pattern.
;; =============================================================================
