;; ===================
;; Action Queries
;; ===================
;; --------------
;; Variables
;; --------------
;; For known declarations and initialisations
;; Example:
;;      char var_name
;;      int var_name = 10

;; Somehow `long` can't be seen as a declaration first, only if the semicolon is
;; added, so we have to use the query below for these cases.
(declaration
    type: (_)
    declarator: (_) @semicolon
)

;; Query for "special" variable declaration like the `long` type as descriped
;; above.
;; Example:
;;      long var_name
((sized_type_specifier
    type: (_)
) @semicolon)

;; Query for assignments.
;; Example:
;;      var = 10
((assignment_expression
    left: (identifier)
    right: (_)
) @semicolon)

;; --------------
;; Struct/Union members
;; --------------
;; Query for struct/union field declarations (members).
;; Tree-sitter C represents struct members as `field_declaration` nodes,
;; NOT `declaration` nodes, so the declaration query above does not capture
;; them.
;; Example:
;;      struct Point { int x }
;;      struct Data { char name }
;;
;; Tree-sitter's error recovery may produce either a proper field_declaration
;; with a MISSING `;` or wrap it in an ERROR node, so we need both forms
;; (same dual-query pattern as call_expression below).
(field_declaration
    type: (_)
    declarator: (_) @semicolon
)

((ERROR
    (field_declaration
        type: (_)
        declarator: (_)
    )
) @semicolon)

;; --------------
;; Functions
;; --------------
;; This query is mainly used for custom function-calls
;; Example:
;;      my_func()
;; This query might look weird for a function call but the query looks like
;; this if we just write 'function_call()'. Don't believe me? Try it out by
;; adding this for example in a C file:
;;      
;;      int main() {
;;          function_call()
;;      }
;;
;; and open the TreeSitterPlayground afterwards ;)
((ERROR
    (call_expression
        function: (identifier)
        arguments: (argument_list)
    )
) @semicolon)

;; This is used for known functions like
;;      printf("welp")
;; Somehow the query above doesn't hit for `printf` for example, that's why we
;; need this query as well.
((expression_statement
    (call_expression
        function: (identifier)
        arguments: (argument_list)
    )
) @semicolon)

;; ----------------
;; Switch-Case
;; ----------------
;; Query for case statements like
;;      case 1
;;
;; Tree-sitter may wrap an incomplete case inside an ERROR node when the
;; enclosing switch block is unclosed, so we need both forms.
((case_statement
    value: (_)
) @double_points)

((ERROR
    (case_statement
        value: (_)
    )
) @double_points)

;; -----------
;; Macros
;; -----------
;; NOTE: `macro_type_specifier` (macros used as types, e.g. `free(ptr)` or
;; `MY_TYPE x`) is NOT queried here.  That node only exists in
;; tree-sitter-c >= 0.21; on older grammars (Termux, older distros) a query
;; referencing it fails to PARSE, which crashed every C/header buffer with
;; E5108 (`Invalid node type "macro_type_specifier"`).  The pattern lives in
;; queries/c/tsetter_extra.scm instead, which the plugin loads separately and
;; only when the installed grammar can parse it (see lua/tree-setter/main.lua).
;; On old grammars `free(ptr)` parses as a plain call_expression and is
;; caught by the call_expression queries above.

;; ----------------------
;; Other expressions
;; ----------------------
;; Small updates, for example like
;;      integer--
;;  or  integer++
((update_expression
    argument: (_)
) @semicolon)

;; Query for break statements
;; Treesitter sees a line with "break", only if there's already a semicolon!
;; Otherwise it'll display it as "ERROR" so we need to compare it on our own if
;; it's a break statement.
(ERROR "break" @semicolon)

;; Well... just return statements... like
;;      return 0
((return_statement
    (_)
) @semicolon)

;; Tree-sitter C wraps function declarations with empty parameter lists
;; (e.g. `void test()`, `int main()`, `bool isPrime()`) inside an ERROR
;; node because `()` is ambiguous with a function call.  Inside the ERROR,
;; the children are (type_node) + (function_declarator).  The existing
;; (declaration ...) query cannot reach inside the ERROR because the
;; `declaration` parent doesn't exist there.
;;
;; We capture the function_declarator CHILD, not the ERROR itself.  When a
;; prototype is typed ABOVE an already-existing function definition,
;; tree-sitter merges both into one multi-row ERROR
;; (`int test()<blank>int main() {` -> ERROR rows 0..2); capturing the ERROR
;; would place `;` on its LAST row (the `{` line).  Capturing the inner
;; declarator pins `;` to the prototype's own row, and the plugin's row
;; filter drops the `main()` declarator below the cursor window.
(ERROR
    (function_declarator
        declarator: (_)
        parameters: (_)
    ) @semicolon
)

;; Pointer-wrapped variant: `int **test()` (and deeper) parse with the
;; function_declarator nested under pointer_declarator node(s).  Tree-sitter's
;; error recovery collapses ANY pointer depth into a single wrapper here, so
;; one extra `_` level covers them all in this shape.
(ERROR
    (_
        (function_declarator
            declarator: (_)
            parameters: (_)
        ) @semicolon
    )
)

;; Function definitions: capture the DECLARATOR'S PARAMETER LIST so a
;; prototype typed ABOVE an already-existing definition still gets `;`.
;; Tree-sitter merges
;;
;;      bool isPrime(int n)
;;      int main() { ... }
;;
;; into ONE function_definition whose declarator swallows rows 0..2.  The
;; only node that reliably ENDS on the prototype's own row is its
;; parameter_list, so we anchor the capture there (the setter places `;` at
;; the end of the capture's last row).
;;
;; The `bool isPrime(int n) {` regression test in tests/test_main_c.lua stays
;; green because the setter refuses to terminate a line that already ends
;; with `{` (see the `{` guard in lua/tree-setter/setter.lua): an opening
;; brace never wants `;`.
;;
;; The declarator can be a bare function_declarator (`bool f(int n)`), a
;; pointer_declarator wrapping one (`int *f(int n)`), or two nested
;; pointer_declarators (`int **f(int n)`).  Queries have no "any descendant"
;; operator, so each nesting depth needs its own branch.  Three or more
;; levels of pointer indirection in a prototype are rare enough that they
;; stay unsupported (documented in README.md).
(function_definition
    declarator: (function_declarator
        parameters: (_) @semicolon
    )
)

(function_definition
    declarator: (_
        (function_declarator
            parameters: (_) @semicolon
        )
    )
)

(function_definition
    declarator: (_
        (_
            (function_declarator
                parameters: (_) @semicolon
            )
        )
    )
)

;; ==========
;; Skips
;; ==========
;; If we are in a condition, than musn't add a semicolon in it! For example
;;      if (test()
;; So here are all "exception" cases. We have the query `ERROR` here, because if
;; we have a condition like
;;      if (...
;; Then we're having `ERROR` instead of `if_statement` since treesitter can't
;; detect it as an if-statement.
(ERROR ["if" "while" "for"] "(" @skip)
