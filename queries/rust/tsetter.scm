;; ==============
;; Variables
;; ==============
;; A normal let declaration like
;;      
;;      let variable = 10
(let_declaration
    pattern: (identifier)
    value: (_) @semicolon
)

;; ==============
;; Struct fields
;; ==============
;; Struct field declarations (members) use `,` as separator, not `;`.
;; Both direct and ERROR-wrapped forms are needed because tree-sitter's
;; error recovery may produce either variant for incomplete fields.
;; Example:
;;      struct Point { x: i32 }
;;      struct Data { name: String }
;;
;; IMPORTANT: the ERROR form captures the inner field_declaration, NOT the
;; ERROR node.  Error recovery can merge the incomplete field with the rows
;; below it into one multi-row ERROR (e.g. a field missing `,` followed by
;; more fields); capturing the ERROR would place `,` on its LAST row -- a
;; line the user is not editing.  The inner node ends on the field's own row.
(field_declaration
    name: (_)
    type: (_) @comma
)

((ERROR
    (field_declaration
        name: (_)
        type: (_)
    ) @comma)
)

;; ==============
;; Functions
;; ==============
;; A normal function call like
;;
;;      test()
(call_expression
    function: (identifier)
    arguments: (arguments) @semicolon
)
