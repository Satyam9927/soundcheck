open Soundcheck_core
open Soundcheck_kong

let verify yaml =
  match Verify.run ~property:(Verify.No_anonymous_access "/admin") yaml with
  | Ok report -> report
  | Error error -> failwith error

let config ?(service_plugin = "") route_plugin =
  Printf.sprintf
    {|services:
  - name: api
    url: http://upstream:8000
    plugins: %s
    routes:
      - name: admin
        paths: [/admin]
        plugins: %s
|}
    service_plugin route_plugin

let expect_result expected report message =
  if report.Report.result <> expected then failwith message

let () =
  let anonymous =
    verify
      (config
         "[{name: key-auth, config: {anonymous: anonymous-consumer}}]")
  in
  (match anonymous with
   | { Report.result = Report.Violated _;
       assurance =
         Some
           { status = Report.Conservative;
             findings = { code = "auth-anonymous-fallback"; _ } :: _;
             _ };
       _ } -> ()
   | _ -> failwith "anonymous fallback must leave the route anonymously reachable");

  let preflight =
    verify
      (config
         "[{name: jwt, config: {run_on_preflight: false}}]")
  in
  (match preflight.result with
   | Report.Violated { action = "OPTIONS"; _ } -> ()
   | _ -> failwith "JWT preflight bypass must expose anonymous OPTIONS");

  let get_only =
    {|services:
  - name: api
    url: http://upstream:8000
    routes:
      - name: admin
        paths: [/admin]
        methods: [GET]
        plugins:
          - name: key-auth
            config: {run_on_preflight: false}
|}
  in
  expect_result Report.Proved (verify get_only)
    "OPTIONS bypass must not affect a GET-only route";

  let strict_route_overrides_anonymous_service =
    config
      ~service_plugin:
        "[{name: key-auth, config: {anonymous: anonymous-consumer}}]"
      "[{name: key-auth}]"
  in
  expect_result Report.Proved (verify strict_route_overrides_anonymous_service)
    "strict route plugin must override anonymous service plugin";

  let anonymous_route_overrides_strict_service =
    config ~service_plugin:"[{name: key-auth}]"
      "[{name: key-auth, config: {anonymous: anonymous-consumer}}]"
  in
  (match (verify anonymous_route_overrides_strict_service).result with
   | Report.Violated _ -> ()
   | _ -> failwith "anonymous route plugin must override strict service plugin")
