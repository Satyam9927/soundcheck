open Soundcheck_core
open Soundcheck_kong

let parse source =
  match Parse.parse_string source with
  | Ok config -> config
  | Error error -> failwith error

let expect_result expected property source =
  match Verify.run ~property source with
  | Ok report when report.Report.result = expected -> report
  | Ok _ -> failwith "unexpected top-level route verification result"
  | Error error -> failwith error

let referenced =
  {|services:
  - name: api
    plugins: [{name: key-auth}]
routes:
  - name: admin
    service: api
    paths: [/admin]
|}

let () =
  let config = parse referenced in
  (match config.services with
   | [ { routes = [ { name = "admin"; _ } ]; _ } ] -> ()
   | _ -> failwith "top-level route was not attached to its referenced service");
  ignore
    (expect_result Report.Proved (Verify.No_anonymous_access "/admin")
       referenced);

  let service_less =
    {|routes:
  - name: maintenance
    paths: [/admin]
|}
  in
  ignore
    (expect_result Report.Proved (Verify.No_anonymous_access "/admin")
       service_less);
  (match
     Verify.run
       ~property:
         (Verify.Authenticated_access
            { path_prefix = "/admin"; method_ = None; host = None })
       service_less
   with
   | Ok
       { result = Report.Violated { route = Some "maintenance"; service = None; _ };
         clause = Some { kind = Report.Must_allow; _ };
         _ } -> ()
   | Ok _ -> failwith "service-less route functionality witness lost its route"
   | Error error -> failwith error);

  let denying_winner =
    {|services:
  - name: api
    routes:
      - name: open
        paths: [/admin]
routes:
  - name: no-service
    paths: [/admin/secure]
|}
  in
  ignore
    (expect_result Report.Proved
       (Verify.No_anonymous_access "/admin/secure") denying_winner);

  (match
     Verify.run ~property:(Verify.No_anonymous_access "/admin")
       "services: [{name: api}]\nroutes: [{name: admin, service: missing, paths: [/admin]}]"
   with
   | Error error
     when String.starts_with
            ~prefix:
              "invalid Kong config: top-level route \"admin\" references unknown service \"missing\""
            error -> ()
   | Error error -> failwith ("unexpected top-level route validation error: " ^ error)
   | Ok _ -> failwith "unknown top-level route service was accepted")
