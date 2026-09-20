(** Versioned description of the Kong semantics Soundcheck verifies, plus a
    config-specific assessment of where conservative or unsupported behavior
    was encountered. *)

type feature = {
  code        : string;
  description : string;
}

type profile = {
  id           : string;
  connector    : string;
  version      : int;
  target       : string;
  modeled      : feature list;
  conservative : feature list;
  unsupported  : feature list;
}

type status = Within_profile | Conservative | Unsupported

type finding = {
  code    : string;
  service : string option;
  route   : string option;
  detail  : string;
}

type assessment = {
  status   : status;
  findings : finding list;
}

val profile : profile
val assess : Ast.config -> assessment
val string_of_status : status -> string

val profile_json : unit -> string
(** Stable machine-readable description of [profile]. *)
