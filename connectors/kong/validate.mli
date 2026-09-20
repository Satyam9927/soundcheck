(** Semantic validation performed by Kong before routes reach the router. *)

val check : Ast.config -> (unit, string) result
(** Reject malformed percent escapes and non-normalized literal route paths.
    Regex route patterns remain authored patterns and are checked separately by
    {!Fragment.check}. *)
