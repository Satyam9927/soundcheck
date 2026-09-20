open Soundcheck_core
open Soundcheck_kong

let config plugins =
  Printf.sprintf
    {|services:
  - name: secure-api
    routes:
    - name: secure-sni
      protocols: [https]
      paths: [/admin]
      snis: [api.example.]
      plugins: %s
|}
    plugins

let parse source =
  match Parse.parse_string source with
  | Ok parsed -> parsed
  | Error error -> failwith error

let request ~scheme ~sni : Ir.request =
  { principal = Anonymous;
    action = "GET";
    resource = "/admin";
    context = [];
    source = 0l;
    host = "";
    scheme;
    sni }

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search offset =
    if offset + needle_length > haystack_length then false
    else if String.sub haystack offset needle_length = needle then true
    else search (offset + 1)
  in
  search 0

let () =
  let policy = Lower.to_policy (parse (config "[]")) in
  if List.length policy.rules <> 2 then
    failwith "SNI route must lower to HTTP-bypass and HTTPS variants";
  if Ir.evaluate policy (request ~scheme:"http" ~sni:"") <> Deny then
    failwith "HTTPS-only route must reject an HTTP request after selection";
  if Ir.evaluate policy (request ~scheme:"https" ~sni:"api.example") <> Allow then
    failwith "normalized exact SNI must match HTTPS";
  if Ir.evaluate policy (request ~scheme:"https" ~sni:"other.example") <> Deny then
    failwith "wrong HTTPS SNI must not match";

  (match
     Verify.run ~property:(Verify.No_anonymous_access "/admin") (config "[]")
   with
   | Ok { result = Report.Violated counterexample; _ }
     when counterexample.scheme = "https"
          && counterexample.sni = "api.example"
          && contains counterexample.note "over https with SNI api.example" -> ()
   | Ok _ -> failwith "SNI violation omitted its HTTPS/SNI witness"
   | Error error -> failwith error);

  (match
     Verify.run
       ~property:
         (Verify.Authenticated_access
            { path_prefix = "/admin"; method_ = None; host = None })
       (config "[{name: key-auth}]")
   with
   | Ok { result = Report.Violated counterexample; _ }
     when counterexample.scheme = "http" -> ()
   | Ok _ ->
     failwith
       "HTTPS-only route must not prove all-scheme authenticated functionality"
   | Error error -> failwith error);

  let wildcard =
    parse
      {|services:
  - name: api
    routes:
    - name: wildcard-sni
      protocols: [https]
      snis: ['*.example']
|}
  in
  let wildcard_policy = Lower.to_policy wildcard in
  if List.for_all (fun (rule : Ir.rule) -> rule.match_complete) wildcard_policy.rules
  then failwith "wildcard SNI must remain conservatively incomplete";
  (match (Assurance.assess wildcard).findings with
   | [ { code = "wildcard-sni"; _ } ] -> ()
   | _ -> failwith "wildcard SNI must carry an assurance finding");

  let expect_invalid source fragment =
    match Verify.run ~property:(Verify.No_anonymous_access "/admin") source with
    | Error error when String.starts_with ~prefix:fragment error -> ()
    | Error error -> failwith ("unexpected protocol validation error: " ^ error)
    | Ok _ -> failwith "invalid Kong protocol configuration was accepted"
  in
  expect_invalid
    "services: [{name: api, routes: [{name: mixed, protocols: [http, tcp], paths: [/admin]}]}]"
    "invalid Kong config: route \"mixed\" (service \"api\") has unknown or incompatible protocols";
  expect_invalid
    "services: [{name: api, routes: [{name: insecure-sni, protocols: [http], snis: [api.example], paths: [/admin]}]}]"
    "invalid Kong config: route \"insecure-sni\" (service \"api\") snis require secure protocols"
