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

  let json = Assurance.profile_json () in
  if not (String.starts_with ~prefix:"{\"id\":\"kong-traditional-http-v1\"" json)
  then failwith "profile JSON omitted stable identity";

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
