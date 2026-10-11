(** Experimental local advisory evaluation. This is not a public verifier API. *)

type provenance = Synthetic | Upstream_example | Authorized_deployment
type case = {
  id : string;
  config : string;
  contract : string;
  provenance : provenance;
}
type manifest = case list

type failure =
  | Contract_read_error
  | Contract_invalid
  | Config_read_error
  | Verification_error
  | Report_mismatch
  | Unexpected_error

type row = {
  id : string;
  provenance : provenance;
  config_sha256 : string option;
  contract_sha256 : string option;
  result : string option;
  assurance : string option;
  finding_codes : string list;
  uncertainty : string option;
  failure : failure option;
  elapsed_seconds : float;
}

val parse_manifest : string -> (manifest, unit) result
(** Strict single-document YAML/JSON subset without backslash escape syntax or
    literal NUL. IDs are unique; explicit relative paths cannot contain dot
    components, ASCII controls, or backslashes. No input is read. *)

val read_regular : root:string -> string -> (string, unit) result
(** Read one explicit regular file beneath [root], rejecting symlink components.
    No discovery or network access. Inputs must remain stable during a run;
    this local helper is not a race-resistant filesystem security boundary. *)

val run :
  ?read:(string -> (string, unit) result) ->
  ?verify:(Soundcheck_kong.Verify.property -> string ->
           (Soundcheck_core.Report.t, string) result) ->
  ?now:(unit -> float) -> root:string -> manifest -> row list
(** Freeze each distinct contract once before any verification; read each config
    once per case, hash those bytes, and verify sequentially. Per-case failures do not
    remove other scheduled cases. Test injection does not affect production CLI. *)

val exit_code : row list -> int
(** 0 only for a nonempty all-proved run; 1 for any input/tool failure (or empty
    run); 3 for a completed run with any non-proof. These are aggregate codes,
    not an extension of the public verifier's exit-code contract. *)

val to_json : row list -> string
(** Privacy-minimized summary only; deliberately does not serialize Report.t. *)

val fatal_json : string -> string
(** [string] must be an internal constant, never an exception/input diagnostic. *)
