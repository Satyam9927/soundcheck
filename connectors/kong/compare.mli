(** Exact decision and optional route/service comparison for two Kong
    declarative configurations. *)

type mode = Security_decision | Route_service | Service_target | Upstream_uri

type service_target = {
  protocol : string;
  host     : string;
  port     : int;
  path     : string option;
}

type observation = {
  decision : Soundcheck_core.Ir.decision;
  route    : string option;
  service  : string option;
  service_target : service_target option;
  upstream_uri : string option;
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
  mode    : mode;
}

val run :
  ?z3:string ->
  ?emit_smt:string ->
  ?mode:mode ->
  string ->
  string ->
  (report, string) result
(** [run before after] parses, validates, and lowers both configs. Equivalence is
    attempted only when both are within the assurance profile, every route match
    is complete, and unresolved overlapping winners cannot affect the selected
    comparison mode. Route/service mode additionally requires stable explicit
    route and service identity. Service-target mode also compares each selected
    service's normalized protocol, host, port, and base path. Upstream-URI mode
    additionally compares the request-dependent transformed upstream path for
    literal route paths. *)

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
  mode            : mode;
}

val run_repair :
  ?z3:string ->
  ?emit_smt:string ->
  ?mode:mode ->
  contract:Contract_spec.t ->
  string ->
  string ->
  (repair_report, string) result
(** Verify the replacement against [contract], then prove that the before/after
    decisions agree outside the contract's immutable endpoint scope. *)

val repair_to_human : repair_report -> string
val repair_to_json : repair_report -> string
