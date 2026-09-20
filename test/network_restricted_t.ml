open Soundcheck_core
open Soundcheck_kong

let trusted =
  match Cidr.parse "10.0.0.0/8" with Ok cidr -> cidr | Error error -> failwith error

let contract ?(trusted_cidr = trusted) () =
  Verify.Network_restricted_access
    { path_prefix = "/internal";
      method_ = Some "GET";
      host = Some "internal.example";
      trusted_cidr }

let verify ?trusted_cidr config =
  match Verify.run ~property:(contract ?trusted_cidr ()) config with
  | Ok report -> report
  | Error error -> failwith error

let expect_clause report kind name =
  match report.Report.clause with
  | Some clause when clause.kind = kind && clause.name = name -> ()
  | _ -> failwith ("unexpected or missing clause metadata for " ^ name)

let secure =
  {|services:
  - name: internal-api
    routes:
    - name: internal-get
      paths: [/internal]
      methods: [GET]
      hosts: [internal.example]
      plugins:
      - name: key-auth
      - name: ip-restriction
        config: {allow: [10.0.0.0/8]}
|}

let auth_only =
  {|services:
  - name: internal-api
    routes:
    - name: internal-get
      paths: [/internal]
      methods: [GET]
      hosts: [internal.example]
      plugins: [{name: key-auth}]
|}

let () =
  (match (verify secure).Report.result with
   | Proved -> ()
   | _ -> failwith "network-restricted contract must prove for guarded access");

  let exposed = verify auth_only in
  (match exposed.result with
   | Violated counterexample ->
     expect_clause exposed Must_deny "untrusted-network-access-denied";
     if Cidr.contains trusted counterexample.source_ip then
       failwith "untrusted-network witness came from inside the trusted block"
   | _ -> failwith "auth-only route must expose authenticated external access");

  let deny_all = verify "services: []\n" in
  (match deny_all.result with
   | Violated counterexample ->
     expect_clause deny_all Must_allow "trusted-authenticated-access-allowed";
     if not (Cidr.contains trusted counterexample.source_ip) then
       failwith "functionality witness came from outside the trusted block"
   | _ -> failwith "deny-all must violate trusted-network functionality");

  let all =
    match Cidr.parse "0.0.0.0/0" with Ok cidr -> cidr | Error error -> failwith error
  in
  let vacuous = verify ~trusted_cidr:all secure in
  (match vacuous.result with
   | Vacuous -> expect_clause vacuous Must_deny "untrusted-network-access-denied"
   | _ -> failwith "a universal trusted block must make the outside class vacuous")
