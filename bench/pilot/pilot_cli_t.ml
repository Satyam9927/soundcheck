open Soundcheck_core
open Soundcheck_kong

let checks = ref 0
let check name condition =
  incr checks;
  if not condition then failwith ("pilot CLI check failed: " ^ name)
let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))
let read_all channel =
  let buffer = Buffer.create 1024 in
  (try while true do Buffer.add_string buffer (input_line channel); Buffer.add_char buffer '\n' done
   with End_of_file -> ());
  Buffer.contents buffer
let run executable arguments =
  let channels = Unix.open_process_args_full executable
      (Array.of_list (executable :: arguments)) (Unix.environment ()) in
  let stdout, _, stderr = channels in
  let output = read_all stdout and errors = read_all stderr in
  let code = match Unix.close_process_full channels with Unix.WEXITED code -> code | _ -> -1 in
  code, output, errors
let parse source = match Yaml.of_string source with Ok value -> value | Error _ -> failwith "invalid JSON"
let field name = function
  | `O fields -> (match List.assoc_opt name fields with Some value -> value | None -> failwith name)
  | _ -> failwith "expected object"
let string = function `String value -> value | _ -> failwith "expected string"
let list = function `A values -> values | _ -> failwith "expected array"
let contains text fragment =
  let rec search index =
    index + String.length fragment <= String.length text
    && (String.sub text index (String.length fragment) = fragment || search (index + 1))
  in search 0

let () =
  if Array.length Sys.argv <> 6 then failwith "expected pilot, soundcheck, examples, retired survey and reviewed contract";
  let pilot, soundcheck, examples = Sys.argv.(1), Sys.argv.(2), Sys.argv.(3) in
  let canonical path = match Contract_spec.parse_string (read_file path) with
    | Ok spec -> Contract_spec.canonical_json spec
    | Error _ -> failwith "invalid reviewed fixture contract"
  in
  check "example contract preserves reviewed identity"
    (canonical (Filename.concat examples "admin-get.yaml") = canonical Sys.argv.(5));
  let code, output, errors = run pilot [ Filename.concat examples "manifest.yaml" ] in
  check "example aggregate nonproof code" (code = 3);
  check "example stderr empty" (errors = "");
  let summary = parse output in
  check "all four examples counted" (field "scheduled" summary = `Float 4.);
  let rows = list (field "cases" summary) in
  check "example row count" (List.length rows = 4);
  List.iter2 (fun (file, expected, expected_exit) row ->
    let config = Filename.concat examples file in
    let contract = Filename.concat examples "admin-get.yaml" in
    let code, output, errors = run soundcheck [ "verify"; config; "--contract"; contract; "--format"; "json" ] in
    check (file ^ " public CLI exit") (code = expected_exit && errors = "");
    let report = parse output in
    check (file ^ " fixed reviewed verdict") (field "result" report = `String expected);
    check (file ^ " unchanged CLI verdict") (field "result" row = field "result" report);
    check (file ^ " unchanged profile") (field "profile" summary = field "profile" (field "assurance" report));
    check (file ^ " unchanged assurance") (field "assurance" row = field "status" (field "assurance" report));
    let codes = list (field "findings" (field "assurance" report))
      |> List.map (fun finding -> string (field "code" finding)) |> List.sort_uniq String.compare in
    check (file ^ " unchanged finding codes") (list (field "finding_codes" row) = List.map (fun code -> `String code) codes);
    check (file ^ " exact source digest") (field "config_sha256" row = `String (Sha256.string (read_file config)));
    let canonical = string (field "canonical" (field "frozen_spec" report)) in
    check (file ^ " same canonical identity") (field "contract_sha256" row = `String (Sha256.string canonical));
    check (file ^ " no synthetic input error") (field "failure" row = `Null);
    check (file ^ " measured runtime") (match field "elapsed_seconds" row with `Float value -> value >= 0. | _ -> false))
    [ "unsafe.yaml", "violated", 3; "repaired.yaml", "proved", 0;
      "deny-all.yaml", "violated", 3; "unsupported.yaml", "unknown", 4 ] rows;
  let root = Filename.temp_file "soundcheck-pilot-cli-" "" in
  Unix.unlink root; Unix.mkdir root 0o700;
  let write name bytes =
    let channel = open_out_bin (Filename.concat root name) in
    Fun.protect ~finally:(fun () -> close_out_noerr channel) (fun () -> output_string channel bytes)
  in
  let rec remove path =
    if (Unix.lstat path).Unix.st_kind = Unix.S_DIR then begin
      Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path
    end else Unix.unlink path
  in
  Fun.protect ~finally:(fun () -> remove root) (fun () ->
    let secret = "private-sentinel-71adb2" in
    let config_name = secret ^ "-config.yaml" and contract_name = secret ^ "-contract.yaml" in
    let config =
      "consumers:\n  - username: " ^ secret ^ "\n    keyauth_credentials:\n      - key: " ^ secret
      ^ "\nservices:\n  - name: " ^ secret ^ "\n    routes:\n      - name: " ^ secret
      ^ "\n        paths: [/" ^ secret ^ "]\n        hosts: [" ^ secret ^ ".example]\n"
    in
    write config_name config;
    write contract_name ("schema_version: 1\nkind: authenticated-access\nscope:\n  path_prefix: /"
      ^ secret ^ "\n  method: GET\n  host: " ^ secret ^ ".example\n");
    write (secret ^ "-invalid.yaml") ("services:\n  - name: " ^ secret ^ "\n    routes: 17\n");
    write (secret ^ "-invalid-contract.yaml") ("schema_version: 1\nkind: " ^ secret ^ "\n");
    let entry id config contract = Printf.sprintf
      "  - id: %s\n    provenance: synthetic\n    config: %s\n    contract: %s\n" id config contract in
    write "manifest.yaml" ("format_version: 1\ncases:\n"
      ^ entry "private-unsafe" config_name contract_name
      ^ entry "private-invalid" (secret ^ "-invalid.yaml") contract_name
      ^ entry "private-missing" (secret ^ "-missing.yaml") contract_name
      ^ entry "private-invalid-contract" config_name (secret ^ "-invalid-contract.yaml"));
    let before = Sys.readdir root |> Array.to_list |> List.sort String.compare in
    let code, output, errors = run pilot [ Filename.concat root "manifest.yaml" ] in
    check "mixed input failures nonzero" (code = 1);
    check "secret paths/config/diagnostics not emitted" (not (contains (output ^ errors) secret));
    check "private stderr empty" (errors = "");
    let summary = parse output in
    check "input failures retain denominator" (field "scheduled" summary = `Float 4.);
    check "input failures explicit" (field "errors" (field "counts" summary) = `Float 3.);
    check "real violation retained alongside failures" (field "violated" (field "counts" summary) = `Float 1.);
    check "no automatic artifacts" (before = (Sys.readdir root |> Array.to_list |> List.sort String.compare));
    check "input config unchanged" (read_file (Filename.concat root config_name) = config);
    write "repaired.yaml" (read_file (Filename.concat examples "repaired.yaml"));
    write "approved.yaml" (read_file (Filename.concat examples "admin-get.yaml"));
    write "proved.yaml" ("format_version: 1\ncases:\n" ^ entry "only-proof" "repaired.yaml" "approved.yaml");
    let code, output, errors = run pilot [ Filename.concat root "proved.yaml" ] in
    check "all proved exit zero" (code = 0 && errors = "" && field "proved" (field "counts" (parse output)) = `Float 1.);
    write "bad-manifest.yaml" ("format_version: 1\n" ^ secret ^ ": invalid\n");
    let code, output, errors = run pilot [ Filename.concat root "bad-manifest.yaml" ] in
    check "invalid manifest sanitized" (code = 1 && errors = "" && not (contains output secret)
      && field "failure" (parse output) = `String "manifest_invalid"
      && field "scheduled" (parse output) = `Null);
    let code, output, errors = run pilot [ Filename.concat root (secret ^ "-absent.yaml") ] in
    check "missing manifest sanitized" (code = 1 && errors = "" && not (contains output secret));
    Unix.symlink "proved.yaml" (Filename.concat root "linked.yaml");
    let code, output, errors = run pilot [ Filename.concat root "linked.yaml" ] in
    check "manifest symlink rejected" (code = 1 && errors = ""
      && field "failure" (parse output) = `String "manifest_read_error");
    let code, output, errors = run pilot [ "--unsupported"; secret ] in
    check "usage does not echo private arguments" (code = 2 && output = "" && not (contains errors secret)));
  let code, output, errors = run Sys.argv.(4) [ "private-retired-survey-input" ] in
  check "old survey explicitly retired" (code = 2 && output = "" && contains errors "retired");
  check "retirement does not disclose inputs" (not (contains errors "private-retired-survey-input"));
  Printf.printf "All %d experimental pilot CLI checks passed.\n" !checks
