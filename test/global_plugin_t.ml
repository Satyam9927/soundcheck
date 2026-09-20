open Soundcheck_core
open Soundcheck_kong

let parse source =
  match Parse.parse_string source with
  | Ok config -> config
  | Error error -> failwith error

let config ?(root = "[]") ?(service = "[]") ?(route = "[]") () =
  Printf.sprintf
    {|plugins: %s
services:
  - name: api
    plugins: %s
    routes:
      - name: admin
        paths: [/admin]
        plugins: %s
|}
    root service route

let expect_result expected property source =
  match Verify.run ~property source with
  | Ok report when report.Report.result = expected -> ()
  | Ok _ -> failwith "unexpected global-plugin verification result"
  | Error error -> failwith error

let request : Ir.request =
  { principal = Anonymous;
    action = "GET";
    resource = "/admin";
    context = [];
    source = 0l;
    host = "";
    scheme = "http";
    sni = "" }

let () =
  let global_auth = config ~root:"[{name: key-auth}]" () in
  let parsed = parse global_auth in
  if List.length parsed.global_plugins <> 1 || parsed.scoped_plugins <> [] then
    failwith "relationship-free root plugin was not classified as global";
  expect_result Report.Proved (Verify.No_anonymous_access "/admin") global_auth;

  let disabled_service =
    config ~root:"[{name: key-auth}]"
      ~service:"[{name: key-auth, enabled: false}]" ()
  in
  expect_result Report.Proved (Verify.No_anonymous_access "/admin")
    disabled_service;

  let global_rate_limit = config ~root:"[{name: rate-limiting}]" () in
  expect_result Report.Proved Verify.Rate_limit_on_public global_rate_limit;

  let overridden_termination =
    config ~root:"[{name: request-termination}]"
      ~service:
        "[{name: request-termination, config: {trigger: x-maintenance}}]"
      ()
  in
  let policy = Lower.to_policy (parse overridden_termination) in
  if Ir.evaluate policy request <> Allow then
    failwith "service plugin must override the global plugin of the same name";

  let scoped_root =
    config ~root:"[{name: key-auth, service: api}]" ()
  in
  let scoped = parse scoped_root in
  if List.length scoped.scoped_plugins <> 1 || scoped.global_plugins <> [] then
    failwith "associated root plugin was incorrectly classified as global";
  (match Verify.run ~property:(Verify.No_anonymous_access "/admin") scoped_root with
   | Ok
       { result = Report.Unknown reason;
         assurance = Some { status = Report.Unsupported; _ };
         _ }
     when String.starts_with ~prefix:"unsupported fragment: root-level plugin"
            reason -> ()
   | Ok _ -> failwith "associated root plugin must produce unknown/unsupported"
   | Error error -> failwith error)
