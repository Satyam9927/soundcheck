open Soundcheck_kong

let config ?(plugins = "[]") route =
  Printf.sprintf
    "services: [{name: api, routes: [{name: %s, paths: [/admin], plugins: %s}]}]"
    route plugins

let run before after =
  match Compare.run before after with
  | Ok report -> report
  | Error error -> failwith error

let () =
  let open_config = config "admin" in
  let guarded = config ~plugins:"[{name: key-auth}]" "admin" in
  (match (run open_config open_config).result with
   | Compare.Equivalent -> ()
   | _ -> failwith "identical configs must be decision-equivalent");

  (match (run open_config guarded).result with
   | Compare.Different witness
     when witness.request.is_anon
          && witness.request.path = "/admin"
          && witness.before.decision = Soundcheck_core.Ir.Allow
          && witness.after.decision = Soundcheck_core.Ir.Deny -> ()
   | _ -> failwith "open and authenticated routes need a concrete difference");

  let unknown_plugin = config ~plugins:"[{name: custom-auth}]" "admin" in
  (match (run unknown_plugin guarded).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config is conservative: unrecognized-plugin" reason -> ()
   | _ -> failwith "conservative plugin semantics must prevent equivalence");

  let unsupported_regex =
    {|services: [{name: api, routes: [{name: admin, paths: ['~/admin/(a+)\1']}]}]|}
  in
  (match (run unsupported_regex guarded).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config is unsupported: unsupported-path-regex" reason -> ()
   | _ -> failwith "unsupported fragments must be a comparison outcome, not an error");

  let ambiguous =
    {|services:
  - name: api
    routes:
    - name: open
      paths: [/admin]
    - name: guarded
      paths: [/admin]
      plugins: [{name: key-auth}]
|}
  in
  (match (run ambiguous guarded).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config has overlapping routes" reason -> ()
   | _ -> failwith "an unresolved security-relevant route tie must be unknown");

  let json = Compare.to_json (run open_config open_config) in
  let expected =
    {|{"result":"equivalent","schema_version":1,"comparison":"security_decision","assurance_profile":"kong-traditional-http-v10","witness":null}|}
  in
  if json <> expected then failwith ("unexpected equivalence JSON: " ^ json)
