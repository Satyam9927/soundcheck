open Soundcheck_core
open Soundcheck_kong

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

let ( let* ) = Result.bind
let invalid () = Error ()

let ascii_id value =
  let alnum = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true
    | _ -> false
  in
  String.length value > 0 && String.length value <= 64 && alnum value.[0]
  && String.for_all (fun c -> alnum c || c = '-' || c = '_') value

let relative_path value =
  value <> "" && Filename.is_relative value
  && String.for_all (fun c -> Char.code c >= 32 && c <> '\127' && c <> '\\') value
  && List.for_all (fun component -> component <> "" && component <> "." && component <> "..")
       (String.split_on_char '/' value)

let fields expected = function
  | `O values when List.length values = List.length expected
                   && List.for_all (fun (key, _) -> List.mem key expected) values -> Ok values
  | _ -> invalid ()

let string_field key values =
  match List.assoc_opt key values with Some (`String value) -> Ok value | _ -> invalid ()

let parse_case value =
  let* values = fields [ "id"; "config"; "contract"; "provenance" ] value in
  let* id = string_field "id" values in
  let* config = string_field "config" values in
  let* contract = string_field "contract" values in
  let* provenance = string_field "provenance" values in
  let* provenance = match provenance with
    | "synthetic" -> Ok Synthetic
    | "upstream-example" -> Ok Upstream_example
    | "authorized-deployment" -> Ok Authorized_deployment
    | _ -> invalid ()
  in
  if ascii_id id && relative_path config && relative_path contract then
    Ok { id; config; contract; provenance }
  else invalid ()

let parse_manifest source =
  (* The YAML C binding uses NUL-terminated scalar strings. Disallow escape
     syntax in this deliberately small manifest language rather than let a
     decoded NUL silently change an explicit filename before validation. *)
  if String.contains source '\\' || String.contains source '\000' then invalid ()
  else try
    let* value = Result.map_error (fun _ -> ()) (Parse.yaml_value ~where:"manifest" source) in
    let* values = fields [ "format_version"; "cases" ] value in
    let* () = match List.assoc_opt "format_version" values with
      | Some (`Float 1.) -> Ok () | _ -> invalid ()
    in
    match List.assoc_opt "cases" values with
    | Some (`A (_ :: _ as cases)) ->
      let rec collect seen acc = function
        | [] -> Ok (List.rev acc)
        | value :: tail ->
          let* case = parse_case value in
          if List.mem case.id seen then invalid ()
          else collect (case.id :: seen) (case :: acc) tail
      in
      collect [] [] cases
    | _ -> invalid ()
  with _ -> invalid ()

let read_regular ~root relative =
  if not (relative_path relative) then invalid ()
  else
    try
      let rec walk parent = function
        | [] -> invalid ()
        | name :: tail ->
          let path = Filename.concat parent name in
          let kind = (Unix.lstat path).Unix.st_kind in
          match tail, kind with
          | [], Unix.S_REG ->
            (* NONBLOCK avoids hanging if a file is replaced by a FIFO between
               lstat and open. fstat checks the actual opened object as well. *)
            let descriptor = Unix.openfile path [ Unix.O_RDONLY; Unix.O_NONBLOCK ] 0 in
            let channel = Unix.in_channel_of_descr descriptor in
            Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
              if (Unix.fstat descriptor).Unix.st_kind <> Unix.S_REG then invalid ()
              else Ok (really_input_string channel (in_channel_length channel)))
          | _ :: _, Unix.S_DIR -> walk path tail
          | _ -> invalid ()
      in
      walk root (String.split_on_char '/' relative)
    with _ -> invalid ()

let provenance_name = function
  | Synthetic -> "synthetic"
  | Upstream_example -> "upstream-example"
  | Authorized_deployment -> "authorized-deployment"

let failure_name = function
  | Contract_read_error -> "contract_read_error"
  | Contract_invalid -> "contract_invalid"
  | Config_read_error -> "config_read_error"
  | Verification_error -> "verification_error"
  | Report_mismatch -> "report_mismatch"
  | Unexpected_error -> "unexpected_error"

let result_name = function
  | Report.Proved -> "proved"
  | Report.Violated _ -> "violated"
  | Report.Vacuous -> "vacuous"
  | Report.Inconsistent _ -> "inconsistent"
  | Report.Unknown _ -> "unknown"

let assurance_name = function
  | Report.Within_profile -> "within_profile"
  | Report.Conservative -> "conservative"
  | Report.Unsupported -> "unsupported"

let known_codes =
  let profile = Assurance.profile in
  List.map (fun (feature : Assurance.feature) -> feature.code)
    (profile.modeled @ profile.conservative @ profile.unsupported)

let project_report spec report =
  let expected_identity = Contract_spec.report_identity spec in
  if report.Report.property_name <> Contract_spec.kind_name spec.Contract_spec.kind
     || (match report.frozen_spec with None -> false | Some identity -> identity <> expected_identity)
  then Error Report_mismatch
  else
  let report = Contract_spec.bind_report spec report in
  match report.Report.assurance, report.frozen_spec with
  | Some assessment, Some identity
    when assessment.profile = Assurance.profile.id
         && identity = expected_identity
         && List.for_all
              (fun (finding : Report.assurance_finding) -> List.mem finding.code known_codes)
              assessment.findings
         && (assessment.status <> Report.Unsupported
             || match report.result with Report.Unknown _ -> true | _ -> false) ->
    let findings = List.map (fun (finding : Report.assurance_finding) -> finding.code)
        assessment.findings |> List.sort_uniq String.compare in
    let uncertainty = match report.result, assessment.status with
      | Report.Unknown _, Report.Unsupported -> Some "unsupported"
      | Report.Unknown _, _ -> Some "unresolved"
      | _ -> None
    in
    Ok (result_name report.result, assurance_name assessment.status, findings, uncertainty)
  | _ -> Error Report_mismatch

let run ?read ?(verify = fun property source -> Verify.run ~property source)
    ?(now = Unix.gettimeofday) ~root manifest =
  let read = Option.value ~default:(read_regular ~root) read in
  (* All declared contracts are loaded before the first config is checked.
     Multiple cases using one path share the same immutable parsed snapshot. *)
  let contracts = Hashtbl.create (List.length manifest) in
  List.iter (fun (case : case) ->
    if not (Hashtbl.mem contracts case.contract) then begin
      let frozen = try
        match read case.contract with
        | Error () -> Error Contract_read_error
        | Ok source ->
          (match Contract_spec.parse_string source with
           | Error _ -> Error Contract_invalid
           | Ok spec -> Ok (spec, Sha256.string (Contract_spec.canonical_json spec)))
        with _ -> Error Unexpected_error
      in
      Hashtbl.add contracts case.contract frozen
    end) manifest;
  List.map (fun (case : case) ->
    let started = now () in
    let empty = { id = case.id; provenance = case.provenance;
      config_sha256 = None; contract_sha256 = None; result = None;
      assurance = None; finding_codes = []; uncertainty = None; failure = None;
      elapsed_seconds = 0. } in
    let row = try
      match Hashtbl.find contracts case.contract with
      | Error failure -> { empty with failure = Some failure }
      | Ok (spec, contract_sha256) ->
        let row = { empty with contract_sha256 = Some contract_sha256 } in
        (match read case.config with
         | Error () -> { row with failure = Some Config_read_error }
         | Ok source ->
           let row = { row with config_sha256 = Some (Sha256.string source) } in
           try match verify (Contract_spec.to_property spec) source with
           | Error _ -> { row with failure = Some Verification_error }
           | Ok report ->
             match project_report spec report with
             | Error failure -> { row with failure = Some failure }
             | Ok (result, assurance, finding_codes, uncertainty) ->
               { row with result = Some result; assurance = Some assurance;
                 finding_codes; uncertainty }
           with _ -> { row with failure = Some Unexpected_error })
      with _ -> { empty with failure = Some Unexpected_error }
    in
    let elapsed_seconds = now () -. started in
    let elapsed_seconds =
      if Float.is_finite elapsed_seconds then max 0. elapsed_seconds else 0.
    in
    { row with elapsed_seconds }) manifest

let exit_code rows =
  if rows = [] || List.exists (fun row -> Option.is_some row.failure || row.result = None) rows
  then 1
  else if List.for_all (fun row -> row.result = Some "proved") rows then 0
  else 3

(* Keep this privacy projection independent of the public report serializer.
   New Report.t fields cannot silently start appearing in pilot output. *)
let quote value =
  let buffer = Buffer.create (String.length value + 2) in
  Buffer.add_char buffer '"';
  String.iter (function
    | '"' -> Buffer.add_string buffer "\\\""
    | '\\' -> Buffer.add_string buffer "\\\\"
    | c when Char.code c < 32 -> Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char buffer c) value;
  Buffer.add_char buffer '"'; Buffer.contents buffer

let optional = function None -> "null" | Some value -> quote value
let array values = "[" ^ String.concat "," values ^ "]"
let object_ values =
  "{" ^ String.concat "," (List.map (fun (key, value) -> quote key ^ ":" ^ value) values) ^ "}"

let row_json row = object_
  [ "id", quote row.id;
    "provenance", quote (provenance_name row.provenance);
    "config_sha256", optional row.config_sha256;
    "contract_sha256", optional row.contract_sha256;
    "result", optional row.result;
    "assurance", optional row.assurance;
    "finding_codes", array (List.map quote row.finding_codes);
    "uncertainty", optional row.uncertainty;
    "failure", optional (Option.map failure_name row.failure);
    "elapsed_seconds", Printf.sprintf "%.6f" row.elapsed_seconds ]

let header =
  [ "experimental_format_version", "1";
    "kind", quote "local_advisory_evaluation";
    "profile", quote Assurance.profile.id ]

let to_json rows =
  let count name =
    List.fold_left (fun total row -> if row.result = Some name then total + 1 else total) 0 rows
  in
  let counts = List.map (fun name -> name, string_of_int (count name))
      [ "proved"; "violated"; "vacuous"; "inconsistent"; "unknown" ] in
  let errors = List.fold_left
      (fun total row -> if Option.is_some row.failure || row.result = None then total + 1 else total) 0 rows in
  object_ (header @
    [ "scheduled", string_of_int (List.length rows);
      "processed", string_of_int (List.length rows);
      "counts", object_ (counts @ [ "errors", string_of_int errors ]);
      "cases", array (List.map row_json rows) ])

let fatal_json failure =
  object_ (header @ [ "failure", quote failure; "scheduled", "null"; "cases", "[]" ])
