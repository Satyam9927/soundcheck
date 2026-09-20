open Soundcheck_kong

let parse source =
  match Parse.parse_string source with
  | Ok config -> config
  | Error error -> failwith error

let codes assessment = List.map (fun (finding : Assurance.finding) -> finding.code) assessment.Assurance.findings

let expect_status expected assessment =
  if assessment.Assurance.status <> expected then
    failwith
      (Printf.sprintf "expected assurance status %s, got %s"
         (Assurance.string_of_status expected)
         (Assurance.string_of_status assessment.Assurance.status))

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || search (offset + 1))
  in
  needle_length = 0 || search 0

let () =
  if Assurance.profile.id <> "kong-traditional-http-v1"
     || Assurance.profile.version <> 1
  then failwith "assurance profile identity changed";

  let within =
    parse
      "services: [{name: api, routes: [{name: exact, paths: [/admin], methods: [GET], hosts: [admin.example], plugins: [{name: key-auth}]}]}]"
    |> Assurance.assess
  in
  expect_status Assurance.Within_profile within;

  let conservative =
    parse
      "services: [{name: api, plugins: [{name: custom-auth}], routes: [{name: headers, paths: [/admin], headers: {x-role: [admin]}, hosts: [Admin.Example], plugins: [{name: ip-restriction, config: {allow: ['2001:db8::/32']}}]}]}]"
    |> Assurance.assess
  in
  expect_status Assurance.Conservative conservative;
  let conservative_codes = codes conservative in
  List.iter
    (fun code ->
      if not (List.mem code conservative_codes) then
        failwith ("missing conservative finding: " ^ code))
    [ "unrecognized-plugin"; "route-headers"; "uppercase-host"; "invalid-ip-cidr" ];

  let unsupported =
    parse
      "services: [{name: api, routes: [{name: backref, paths: ['~/(a+)\\1']}]}]"
    |> Assurance.assess
  in
  expect_status Assurance.Unsupported unsupported;
  if not (List.mem "unsupported-path-regex" (codes unsupported)) then
    failwith "unsupported regex finding missing";

  let expected_json =
    {|{"schema_version":1,"id":"kong-traditional-http-v1","connector":"kong","version":1,"target":"Kong Gateway traditional/traditional_compatible HTTP routing","modeled":[{"code":"literal-path-prefix","description":"literal HTTP path-prefix matching"},{"code":"regular-path-regex","description":"the documented regular subset of Kong path regexes"},{"code":"http-method","description":"HTTP method matching"},{"code":"lowercase-host","description":"lowercase exact and wildcard Host matching"},{"code":"traditional-route-priority","description":"two-layer traditional-router priority without created_at"},{"code":"known-auth-plugins","description":"authentication requirement from Soundcheck's known plugin list"},{"code":"known-rate-limit-plugins","description":"rate-limit coverage from Soundcheck's known plugin list"},{"code":"ipv4-ip-restriction","description":"IPv4 ip-restriction allow and deny guards over Kong's derived client IP"},{"code":"default-admin-ports","description":"Admin API recognition on default ports 8001 and 8444"},{"code":"default-deny","description":"denying fallthrough when no route guard allows a request"}],"conservative":[{"code":"request-path-normalization","description":"symbolic paths are not restricted to Kong-normalized request paths"},{"code":"route-created-at-tie","description":"created_at is absent from decK and unresolved route order remains tied"},{"code":"route-headers","description":"header criteria are over-approximated and the route is left incomparable"},{"code":"route-sni","description":"SNI criteria are over-approximated and the route is left incomparable"},{"code":"route-stream-match","description":"source/destination criteria are over-approximated and the route is left incomparable"},{"code":"uppercase-host","description":"uppercase route hosts are left incomparable because request hosts are lowercased"},{"code":"unrecognized-plugin","description":"unrecognized plugins provide no modeled auth or rate-limit behavior"},{"code":"invalid-ip-cidr","description":"IPv6 or malformed ip-restriction entries are dropped, weakening the guard"}],"unsupported":[{"code":"unsupported-path-regex","description":"non-regular or untranslated regex constructs make the whole result unknown"}]}|}
  in
  let json = Assurance.profile_json () in
  if json <> expected_json then failwith "Kong assurance profile JSON changed";
  let expected_human =
    {|KONG ASSURANCE PROFILE  kong-traditional-http-v1
Connector: kong
Profile version: 1
Target: Kong Gateway traditional/traditional_compatible HTTP routing

Modeled:
  - literal-path-prefix: literal HTTP path-prefix matching
  - regular-path-regex: the documented regular subset of Kong path regexes
  - http-method: HTTP method matching
  - lowercase-host: lowercase exact and wildcard Host matching
  - traditional-route-priority: two-layer traditional-router priority without created_at
  - known-auth-plugins: authentication requirement from Soundcheck's known plugin list
  - known-rate-limit-plugins: rate-limit coverage from Soundcheck's known plugin list
  - ipv4-ip-restriction: IPv4 ip-restriction allow and deny guards over Kong's derived client IP
  - default-admin-ports: Admin API recognition on default ports 8001 and 8444
  - default-deny: denying fallthrough when no route guard allows a request

Conservative:
  - request-path-normalization: symbolic paths are not restricted to Kong-normalized request paths
  - route-created-at-tie: created_at is absent from decK and unresolved route order remains tied
  - route-headers: header criteria are over-approximated and the route is left incomparable
  - route-sni: SNI criteria are over-approximated and the route is left incomparable
  - route-stream-match: source/destination criteria are over-approximated and the route is left incomparable
  - uppercase-host: uppercase route hosts are left incomparable because request hosts are lowercased
  - unrecognized-plugin: unrecognized plugins provide no modeled auth or rate-limit behavior
  - invalid-ip-cidr: IPv6 or malformed ip-restriction entries are dropped, weakening the guard

Unsupported:
  - unsupported-path-regex: non-regular or untranslated regex constructs make the whole result unknown|}
  in
  let human = Assurance.profile_human () in
  if human <> expected_human then failwith "Kong assurance profile human output changed";

  let report =
    match
      Verify.run ~property:(Verify.No_anonymous_access "/admin")
        "services: [{name: api, routes: [{name: headers, paths: [/admin], headers: {x-role: [admin]}}]}]"
    with
    | Ok report -> report
    | Error error -> failwith error
  in
  (match report.Soundcheck_core.Report.assurance with
   | Some assurance
     when assurance.profile = "kong-traditional-http-v1"
          && assurance.status = Soundcheck_core.Report.Conservative -> ()
   | _ -> failwith "verification report omitted assurance assessment");
  let report_json = Soundcheck_core.Report.to_json report in
  if not (contains report_json "\"schema_version\":7")
     || not (contains report_json "\"code\":\"route-headers\"")
  then failwith "report JSON omitted assurance identity or finding";
  let human = Soundcheck_core.Report.to_human report in
  if not (contains human "Assurance: kong-traditional-http-v1 (conservative)")
     || not (contains human "route-headers")
  then failwith "human report omitted assurance assessment"
