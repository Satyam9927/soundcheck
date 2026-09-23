open Soundcheck_kong

let config ?(plugins = "[]") route =
  Printf.sprintf
    "services: [{name: api, routes: [{name: %s, paths: [/admin], plugins: %s}]}]"
    route plugins

let run before after =
  match Compare.run before after with
  | Ok report -> report
  | Error error -> failwith error

let run_mode mode before after =
  match Compare.run ~mode before after with
  | Ok report -> report
  | Error error -> failwith error

let contract source =
  match Contract_spec.parse_string source with
  | Ok contract -> contract
  | Error error -> failwith error

let run_repair contract before after =
  match Compare.run_repair ~contract before after with
  | Ok report -> report
  | Error error -> failwith error

let run_repair_mode mode contract before after =
  match Compare.run_repair ~mode ~contract before after with
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

let () =
  let before = config "admin" in
  let renamed = config "admin-v2" in
  (match (run before renamed).result with
   | Compare.Equivalent -> ()
   | _ -> failwith "route renaming must not change decision equivalence");
  (match (run_mode Compare.Route_service before renamed).result with
   | Compare.Different witness
     when witness.before.route = Some "admin"
          && witness.after.route = Some "admin-v2" -> ()
   | _ -> failwith "route/service mode must detect a selected-route rename");

  let moved =
    "services: [{name: other-api, routes: [{name: admin, paths: [/admin]}]}]"
  in
  (match (run_mode Compare.Route_service before moved).result with
   | Compare.Different witness
     when witness.before.service = Some "api"
          && witness.after.service = Some "other-api" -> ()
   | _ -> failwith "route/service mode must detect a selected-service change");

  let unnamed = "services: [{name: api, routes: [{paths: [/admin]}]}]" in
  (match (run_mode Compare.Route_service unnamed before).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config contains a route without" reason -> ()
   | _ -> failwith "unnamed routes must prevent exact routing identity");

  let unnamed_service = "services: [{routes: [{name: admin, paths: [/admin]}]}]" in
  (match (run_mode Compare.Route_service unnamed_service before).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config contains a routed service without" reason -> ()
   | _ -> failwith "unnamed services must prevent exact routing identity");

  let harmless_decision_tie =
    {|services:
  - name: api
    routes:
    - name: first
      paths: [/admin]
    - name: second
      paths: [/admin]
|}
  in
  (match (run harmless_decision_tie harmless_decision_tie).result with
   | Compare.Equivalent -> ()
   | _ -> failwith "identical-effect ties may prove decision equivalence");
  (match
     (run_mode Compare.Route_service harmless_decision_tie harmless_decision_tie).result
   with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config has overlapping routes" reason -> ()
   | _ -> failwith "distinct tied routes must prevent routing equivalence")

let () =
  let service target =
    Printf.sprintf
      "services: [{name: api, %s, routes: [{name: admin, paths: [/admin]}]}]"
      target
  in
  let shorthand = service "url: HTTPS://Backend.Example/v1" in
  let explicit =
    service
      "protocol: https, host: backend.example, port: 443, path: /v1"
  in
  (match (run_mode Compare.Service_target shorthand explicit).result with
   | Compare.Equivalent -> ()
   | _ ->
     failwith
       "URL shorthand and normalized explicit target fields must be equivalent");

  let redirected = service "url: https://other.example/v1" in
  (match (run_mode Compare.Service_target shorthand redirected).result with
   | Compare.Different witness
     when Option.map (fun target -> target.Compare.host) witness.before.service_target
            = Some "backend.example"
          && Option.map (fun target -> target.Compare.host)
               witness.after.service_target
             = Some "other.example" -> ()
   | _ -> failwith "service-target mode must detect an upstream redirect");

  let new_base_path = service "url: https://backend.example/v2" in
  (match (run_mode Compare.Service_target shorthand new_base_path).result with
   | Compare.Different witness
     when Option.bind witness.before.service_target (fun target -> target.path)
            = Some "/v1"
          && Option.bind witness.after.service_target (fun target -> target.path)
             = Some "/v2" -> ()
   | _ -> failwith "service-target mode must detect a service base-path change");

  let missing = service "retries: 5" in
  (match (run_mode Compare.Service_target missing explicit).result with
   | Compare.Unknown reason
     when String.starts_with ~prefix:"before config service \"api\" has no upstream host"
            reason -> ()
   | _ -> failwith "a missing upstream host must prevent target equivalence");

  let mixed =
    service "url: https://backend.example/v1, host: backend.example"
  in
  (match (run_mode Compare.Service_target mixed explicit).result with
   | Compare.Unknown reason
     when String.starts_with
            ~prefix:
              "before config service \"api\" combines url shorthand with explicit"
            reason -> ()
   | _ -> failwith "mixed shorthand and explicit targets must fail closed")

let () =
  let frozen =
    contract
      {|schema_version: 1
kind: authenticated-access
scope:
  path_prefix: /admin
  method: GET
|}
  in
  let before =
    {|services:
  - name: api
    routes:
    - name: admin
      paths: [/admin]
    - name: public
      paths: [/public]
|}
  in
  let repaired =
    {|services:
  - name: api
    routes:
    - name: admin
      paths: [/admin]
      methods: [GET]
      plugins: [{name: key-auth}]
    - name: admin-other
      paths: [/admin]
    - name: public
      paths: [/public]
|}
  in
  (match (run_repair frozen before repaired).result with
   | Compare.Valid_repair -> ()
   | _ -> failwith "a contract-compliant scoped change must be a valid repair");
  let valid_json = Compare.repair_to_json (run_repair frozen before repaired) in
  if
    not
      (String.starts_with
         ~prefix:
           {|{"result":"valid_repair","schema_version":1,"comparison":"frozen_scope_preservation"|}
         valid_json)
  then failwith ("unexpected scoped-repair JSON: " ^ valid_json);

  let routing_repaired =
    {|services:
  - name: api
    routes:
    - name: admin-get
      paths: [/admin]
      methods: [GET]
      plugins: [{name: key-auth}]
    - name: admin
      paths: [/admin]
    - name: public
      paths: [/public]
|}
  in
  (match
     (run_repair_mode Compare.Route_service frozen before routing_repaired).result
   with
   | Compare.Valid_repair -> ()
   | _ ->
     failwith
       "route/service preservation must ignore routing changes inside frozen scope");

  let routing_regressed =
    {|services:
  - name: api
    routes:
    - name: admin-get
      paths: [/admin]
      methods: [GET]
      plugins: [{name: key-auth}]
    - name: admin
      paths: [/admin]
    - name: public-v2
      paths: [/public]
|}
  in
  (match
     (run_repair_mode Compare.Route_service frozen before routing_regressed).result
   with
   | Compare.Out_of_scope_regression witness
     when String.starts_with ~prefix:"/public" witness.request.path -> ()
   | _ -> failwith "out-of-scope route renaming must be a routing regression");

  let regressed =
    {|services:
  - name: api
    routes:
    - name: admin
      paths: [/admin]
      methods: [GET]
      plugins: [{name: key-auth}]
    - name: admin-other
      paths: [/admin]
    - name: public
      paths: [/public]
      plugins: [{name: key-auth}]
|}
  in
  let regression_report = run_repair frozen before regressed in
  (match regression_report.result with
   | Compare.Out_of_scope_regression witness
     when String.starts_with ~prefix:"/public" witness.request.path -> ()
   | _ ->
     failwith
       ("a public-route change must be an out-of-scope regression: "
        ^ Compare.repair_to_human regression_report));

  let deny_all = "services: []" in
  (match (run_repair frozen before deny_all).result with
   | Compare.Contract_failed -> ()
   | _ -> failwith "deny-all must fail the frozen functionality clause");

  let post_changed =
    {|services:
  - name: api
    routes:
    - name: admin-get
      paths: [/admin]
      methods: [GET]
      plugins: [{name: key-auth}]
    - name: admin-post
      paths: [/admin]
      methods: [POST]
      plugins: [{name: key-auth}]
    - name: public
      paths: [/public]
|}
  in
  let method_report = run_repair frozen before post_changed in
  (match method_report.result with
   | Compare.Out_of_scope_regression witness
     when String.starts_with ~prefix:"/admin" witness.request.path
          && witness.request.method_ <> "GET" -> ()
   | _ ->
     failwith
       ("method-excluded endpoint behavior must remain preserved: "
        ^ Compare.repair_to_human method_report))

let () =
  let network =
    contract
      {|schema_version: 1
kind: network-restricted-access
scope:
  path_prefix: /internal
  method: GET
  host: internal.example
  trusted_cidr: 10.0.0.0/8
assumptions:
  source_ip_integrity: externally-enforced
|}
  in
  let request principal source : Soundcheck_core.Ir.request =
    { principal;
      action = "GET";
      resource = "/internal/status";
      context = [];
      source;
      host = "internal.example";
      scheme = "https";
      sni = "" }
  in
  let scope = Contract_spec.scope_condition network in
  if
    not
      (Soundcheck_core.Ir.matches scope
         (request Soundcheck_core.Ir.Anonymous 0l))
    || not
         (Soundcheck_core.Ir.matches scope
            (request (Soundcheck_core.Ir.Authenticated "user") 0x0a000001l))
  then
    failwith
      "principal and trusted CIDR must govern clauses, not narrow repair scope"
