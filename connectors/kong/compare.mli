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

type repair_outcome =
  | Valid_repair
  | Contract_failed
  | Out_of_scope_regression of witness
  | Repair_unknown of string

type repair_report = {
  result          : repair_outcome;
  profile         : string;
  contract_report : Soundcheck_core.Report.t;
  frozen_spec     : Contract_spec.t;
}

val run_repair :
  ?z3:string ->
  ?emit_smt:string ->
  contract:Contract_spec.t ->
  string ->
  string ->
  (repair_report, string) result
(** Verify the replacement against [contract], then prove that the before/after
    decisions agree outside the contract's immutable endpoint scope. *)

val repair_to_human : repair_report -> string
val repair_to_json : repair_report -> string
