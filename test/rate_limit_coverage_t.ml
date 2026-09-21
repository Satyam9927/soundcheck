open Soundcheck_core
open Soundcheck_kong

let config ?(service_plugins = "[]") route_plugins =
  Printf.sprintf
    {|services:
  - name: public-api
    url: http://upstream:8000
    plugins: %s
    routes:
      - name: public
        paths: [/public]
        plugins: %s
|}
    service_plugins route_plugins

let verify yaml =
  match Verify.run ~property:Verify.Rate_limit_on_public yaml with
  | Ok report -> report
  | Error error -> failwith error

let expect_specialized code plugin =
  match verify (config (Printf.sprintf "[{name: %s}]" plugin)) with
  | { Report.result = Report.Violated _;
      assurance =
        Some
          { status = Report.Conservative;
            findings = [ { code = actual; _ } ];
            _ };
      _ }
    when actual = code -> ()
  | _ -> failwith (plugin ^ " must not establish general request-rate coverage")

let expect_proved yaml message =
  match (verify yaml).result with Report.Proved -> () | _ -> failwith message

let () =
  expect_specialized "response-rate-limit-dependency" "response-ratelimiting";
  expect_specialized "graphql-rate-limit-scope"
    "graphql-rate-limiting-advanced";

  expect_proved (config "[{name: rate-limiting}]")
    "rate-limiting must establish general request-rate coverage";
  expect_proved (config "[{name: rate-limiting-advanced}]")
    "rate-limiting-advanced must establish general request-rate coverage";

  expect_proved
    (config
       ~service_plugins:"[{name: rate-limiting}]"
       "[{name: response-ratelimiting}]")
    "a specialized route plugin must not hide a differently named general service plugin";

  expect_proved
    (config
       ~service_plugins:"[{name: rate-limiting}]"
       "[{name: rate-limiting, enabled: false}]")
    "a disabled route plugin must not hide the enabled service configuration"
