(** Exact Allow/Deny comparison for two Kong declarative configurations. *)

type observation = {
  decision : Soundcheck_core.Ir.decision;
  route    : string option;
  service  : string option;
}

type witness = {
  request : Soundcheck_core.Solve.model;
  before  : observation;
  after   : observation;
}

type outcome = Equivalent | Different of witness | Unknown of string

type report = {
  result  : outcome;
  profile : string;
}

val run :
  ?z3:string -> ?emit_smt:string -> string -> string -> (report, string) result
(** [run before after] parses, validates, and lowers both configs. Equivalence is
    attempted only when both are within the assurance profile, every route match
    is complete, and unresolved overlapping winners cannot affect the decision. *)

val to_human : report -> string
val to_json : report -> string
