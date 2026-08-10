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
;;
;; IMPORTANT: in the ERROR form we capture the inner field_declaration, NOT
;; the ERROR node itself.  Error recovery can merge the incomplete field with
;; the lines below it into ONE multi-row ERROR (e.g. a struct member missing
;; `;` followed by more members); capturing the ERROR would place `;` on its
;; LAST row -- a line the user is not editing.  The inner node ends on the
;; field's own row, which is what the plugin's row filter expects.
(field_declaration
    type: (_)
    declarator: (_) @semicolon
)

((ERROR
    (field_declaration
        type: (_)
        declarator: (_)
    ) @semicolon)
)

;; --------------
;; Initializer lists (arrays, structs, unions)
;; --------------
;; When the user is typing a multi-line initializer list top-down (the
;; closing `};` doesn't exist yet), tree-sitter wraps the whole thing in an
;; ERROR node.  The elements end up as direct children of that ERROR:
;;
;;      int m[2][2] = {     <- ERROR
;;          { 1, 2 },
;;          { 3, 4 }        <- cursor; user pressed <CR> here
;;
;; We add `,` to the LAST element (bottommost-wins in the plugin picks the
;; lowest in-window capture) so the user can keep typing rows, matching what
;; the Python query does for lists/dicts and the Rust query for struct
;; fields.
;;
;; The captures are the inner initializer_list (nested `{ ... }` elements
;; like the `{ 1, 2 }` rows above) and initializer_pair (designated
;; initializers like `.x = 1`).  Both node types only exist inside an
;; initializer context, so these patterns can NEVER fire on unrelated ERROR
;; nodes (e.g. `int x = 5 +` or an unterminated `foo(`).  A single-line
;; closed initializer (`int x = { 1, 2, 3 }` + <CR>) parses as a proper
;; declaration -- no ERROR -- so it keeps getting `;` from the declaration
;; query above.
((ERROR
    (initializer_list) @comma
)
)

((ERROR
    (initializer_pair) @comma
)
)

;; Closed-list variant: when the `};` is ALREADY typed (retrospective edit,
;; e.g. the user goes back up to insert another row), the list parses as a
;; proper initializer_list (no ERROR).  Capture the inner initializer_list /
;; initializer_pair elements the same way.  A single-line closed initializer
;; (`int x = { 1, 2, 3 }`) has bare number_literal children -- they match
;; NEITHER pattern, so it keeps getting `;` from the declaration query.
(initializer_list
    (initializer_list) @comma
)

(initializer_list
    (initializer_pair) @comma
)

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
;;
;; We capture the inner call_expression, NOT the ERROR node.  When an `else`
;; (or any token that cannot continue the statement) follows an unterminated
;; call, error recovery merges `call<blank>else` into ONE multi-row ERROR
;; whose last row is the `else` line.  Capturing the ERROR would place `;`
;; on the `else` line; the inner call_expression ends on the user's own row.
((ERROR
    (call_expression
        function: (identifier)
        arguments: (argument_list)
    ) @semicolon)
)

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
;;
;; As with the call_expression / field_declaration patterns above, the ERROR
;; form captures the inner case_statement (not the whole ERROR): a merged
;; multi-row ERROR would pin `:` to a row below the user's edit.
((case_statement
    value: (_)
) @double_points)

((ERROR
    (case_statement
        value: (_)
    ) @double_points)
)

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

;; Function definitions: capture the DECLARATOR so a prototype typed ABOVE
;; an already-existing definition still gets `;`.  Tree-sitter merges
;;
;;      bool isPrime(int n)
;;      int main() { ... }
;;
;; into ONE function_definition whose declarator swallows rows 0..2, and the
;; declarator can be a function_declarator or a pointer_declarator chain of
;; ANY depth (`int *f()`, `int **f()`, `int ***f()`, ...).  Queries have no
;; "any descendant" operator, so instead of enumerating pointer depths we
;; capture the declarator with a dedicated @func_decl name and let the plugin
;; resolve the innermost parameter_list in Lua (resolve_func_decl() in
;; lua/tree-setter/main.lua).  That parameter_list is the node that reliably
;; ENDS on the prototype's own row, so the setter places `;` there.
;;
;; The `bool isPrime(int n) {` regression test in tests/test_main_c.lua stays
;; green because the setter refuses to terminate a line that already ends
;; with `{` (see the `{` guard in lua/tree-setter/setter.lua): an opening
;; brace never wants `;`.
(function_definition
    declarator: (_) @func_decl
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
