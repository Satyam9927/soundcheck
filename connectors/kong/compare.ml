open Soundcheck_core

type mode = Security_decision | Route_service

type observation = {
  decision : Ir.decision;
  route    : string option;
  service  : string option;
}

type witness = {
  request : Solve.model;
  before  : observation;
  after   : observation;
}

type outcome = Equivalent | Different of witness | Unknown of string

type report = {
  result  : outcome;
  profile : string;
  mode    : mode;
}

let parse label source =
  match Parse.parse_string source with
  | Error error -> Error (Printf.sprintf "%s config: %s" label error)
  | Ok config ->
    (match Validate.check config with
     | Error error -> Error (Printf.sprintf "%s config: %s" label error)
     | Ok () -> Ok config)

let assessment_reason label (assessment : Assurance.assessment) =
  match assessment.findings with
  | [] -> Printf.sprintf "%s config is not within the assurance profile" label
  | finding :: _ ->
    Printf.sprintf "%s config is %s: %s — %s" label
      (Assurance.string_of_status assessment.status) finding.code finding.detail

let unresolved_pairs ~label mode (policy : Ir.policy) =
  let rec pairs = function
    | [] -> []
    | rule :: rest -> List.map (fun other -> (rule, other)) rest @ pairs rest
  in
  pairs policy.rules
  |> List.filter (fun ((left : Ir.rule), (right : Ir.rule)) ->
         not (Ir.outranks left.priority right.priority)
         && not (Ir.outranks right.priority left.priority)
         && (left.decision <> right.decision || left.guard <> right.guard
            || (mode = Route_service && label left <> label right)))

let exact_policy ?(z3 = "z3") ~rule_label mode label (policy : Ir.policy) =
  if List.exists (fun (rule : Ir.rule) -> not rule.match_complete) policy.rules
  then Error (label ^ " config contains an incomplete route match")
  else
    let rec check = function
      | [] -> Ok ()
      | ((left : Ir.rule), (right : Ir.rule)) :: rest ->
        let query =
          Smt_encode.condition_query ~domain:policy.request_domain
            ~name:"route-order-determinism"
            ~description:
              "unresolved routes with different decisions, guards, or observed identities overlap"
            (Ir.And [ left.match_; right.match_ ])
        in
        (match Solve.check ~z3 query with
         | Solve.Proved -> check rest
         | Solve.Violated _ ->
           Error
             (Printf.sprintf
                "%s config has overlapping routes %S and %S whose winner is not determined by the declarative config"
                label left.id right.id)
         | Solve.Unknown reason ->
           Error
             (Printf.sprintf "%s config route-order check was inconclusive: %s"
                label reason))
    in
    check (unresolved_pairs ~label:rule_label mode policy)

let route_locations (config : Ast.config) =
  let service_routes =
    List.concat_map
      (fun (service : Ast.service) ->
        List.map
          (fun (route : Ast.route) -> (route.name, Some service.name))
          service.routes)
      config.services
  in
  let service_less =
    config.top_level_routes
    |> List.filter (fun (top : Ast.top_level_route) ->
           top.service = None && not top.unsupported_reference)
    |> List.map (fun (top : Ast.top_level_route) -> (top.route.name, None))
  in
  service_routes @ service_less

let routing_identity label config =
  let locations = route_locations config in
  let service_names =
    config.Ast.services
    |> List.filter (fun (service : Ast.service) -> service.routes <> [])
    |> List.map (fun (service : Ast.service) -> service.name)
  in
  match List.find_opt (( = ) "<unnamed-service>") service_names with
  | Some _ ->
    Error (label ^ " config contains a routed service without an explicit name")
  | None ->
  match
    List.find_opt
      (fun name -> List.length (List.filter (( = ) name) service_names) > 1)
      (List.sort_uniq String.compare service_names)
  with
  | Some name ->
    Error (Printf.sprintf "%s config contains duplicate service name %S" label name)
  | None ->
  match List.find_opt (fun (route, _) -> route = "<unnamed-route>") locations with
  | Some _ -> Error (label ^ " config contains a route without an explicit name")
  | None ->
    let names = List.map fst locations in
    (match
       List.find_opt
         (fun name -> List.length (List.filter (( = ) name) names) > 1)
         names
     with
     | Some name ->
       Error
         (Printf.sprintf "%s config contains duplicate route name %S" label name)
     | None -> Ok locations)

let location_label locations (rule : Ir.rule) =
  let service = List.assoc rule.id locations in
  rule.id ^ "\x1f" ^ Option.value ~default:"<no-service>" service

let request_of_model (model : Solve.model) : Ir.request =
  { principal = if model.is_anon then Anonymous else Authenticated "subject";
    action = model.method_;
    resource = model.path;
    context = model.headers;
    source = model.src_ip;
    host = model.host;
    scheme = model.scheme;
    sni = model.sni }

let observe config (policy : Ir.policy) model =
  let request = request_of_model model in
  let routes =
    policy.Ir.rules
    |> List.filter (Ir.selected policy request)
    |> List.map (fun (rule : Ir.rule) -> rule.id)
    |> List.sort_uniq String.compare
  in
  let route = match routes with [ route ] -> Some route | _ -> None in
  { decision = Ir.evaluate policy request;
    route;
    service = Option.bind route (Lift.service_of_route config) }

let run_comparison ?(z3 = "z3") ?emit_smt ?(when_ = Ir.True)
    ?(mode = Security_decision) before_source after_source =
  match parse "before" before_source, parse "after" after_source with
  | Error error, _ | _, Error error -> Error error
  | Ok before_config, Ok after_config ->
    let profile = Assurance.profile.id in
    let before_assessment = Assurance.assess before_config in
    let after_assessment = Assurance.assess after_config in
    let identities =
      match mode with
      | Security_decision -> Ok ([], [])
      | Route_service ->
        (match routing_identity "before" before_config with
         | Error _ as error -> error
         | Ok before ->
           match routing_identity "after" after_config with
           | Error _ as error -> error
           | Ok after -> Ok (before, after))
    in
    if before_assessment.status <> Assurance.Within_profile then
      Ok
        { result = Unknown (assessment_reason "before" before_assessment);
          profile;
          mode }
    else if after_assessment.status <> Assurance.Within_profile then
      Ok
        { result = Unknown (assessment_reason "after" after_assessment);
          profile;
          mode }
    else
      match identities with
      | Error reason -> Ok { result = Unknown reason; profile; mode }
      | Ok (before_locations, after_locations) ->
      let before_policy = Lower.to_policy before_config in
      let after_policy = Lower.to_policy after_config in
      let before_label = location_label before_locations in
      let after_label = location_label after_locations in
      (match exact_policy ~z3 ~rule_label:before_label mode "before" before_policy with
       | Error reason -> Ok { result = Unknown reason; profile; mode }
       | Ok () ->
         match exact_policy ~z3 ~rule_label:after_label mode "after" after_policy with
         | Error reason -> Ok { result = Unknown reason; profile; mode }
         | Ok () ->
         let query =
           match mode with
           | Security_decision ->
             Smt_encode.decision_equivalence_query ~when_ before_policy after_policy
           | Route_service ->
             Smt_encode.route_equivalence_query ~when_
               ~left_label:before_label ~right_label:after_label before_policy
               after_policy
         in
         match Solve.check ~z3 ?emit_smt query with
         | Solve.Proved -> Ok { result = Equivalent; profile; mode }
         | Solve.Unknown reason -> Ok { result = Unknown reason; profile; mode }
         | Solve.Violated request ->
           Ok
             { result =
                 Different
                   { request;
                     before = observe before_config before_policy request;
                     after = observe after_config after_policy request };
               profile;
               mode })

let run ?z3 ?emit_smt ?mode before_source after_source =
  run_comparison ?z3 ?emit_smt ?mode before_source after_source

let escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | character when Char.code character < 0x20 ->
        Buffer.add_string buffer
          (Printf.sprintf "\\u%04x" (Char.code character))
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let jstring value = "\"" ^ escape value ^ "\""
let jopt = function None -> "null" | Some value -> jstring value

let observation_json observation =
  Printf.sprintf "{\"decision\":%s,\"route\":%s,\"service\":%s}"
    (jstring (Ir.string_of_decision observation.decision |> String.lowercase_ascii))
    (jopt observation.route) (jopt observation.service)

let witness_json witness =
  let request = witness.request in
  let headers =
    request.headers
    |> List.map (fun (name, value) ->
           Printf.sprintf "{\"name\":%s,\"value\":%s}" (jstring name) (jstring value))
    |> String.concat ","
  in
  Printf.sprintf
    "{\"request\":{\"principal\":%s,\"action\":%s,\"path\":%s,\"host\":%s,\"scheme\":%s,\"sni\":%s,\"headers\":[%s],\"source_ip\":%s},\"before\":%s,\"after\":%s}"
    (jstring (if request.is_anon then "anonymous" else "authenticated"))
    (jstring request.method_) (jstring request.path) (jstring request.host)
    (jstring request.scheme) (jstring request.sni) headers
    (jstring (Cidr.string_of_ip request.src_ip))
    (observation_json witness.before) (observation_json witness.after)

let to_json report =
  let comparison =
    match report.mode with
    | Security_decision -> "security_decision"
    | Route_service -> "route_service"
  in
  let head =
    Printf.sprintf "\"schema_version\":1,\"comparison\":%s,\"assurance_profile\":%s"
      (jstring comparison) (jstring report.profile)
  in
  match report.result with
  | Equivalent ->
    Printf.sprintf "{\"result\":\"equivalent\",%s,\"witness\":null}" head
  | Different witness ->
    Printf.sprintf "{\"result\":\"different\",%s,\"witness\":%s}" head
      (witness_json witness)
  | Unknown reason ->
    Printf.sprintf
      "{\"result\":\"unknown\",%s,\"witness\":null,\"reason\":%s}"
      head (jstring reason)

let observation_human label observation =
  Printf.sprintf "%s: %s%s%s" label (Ir.string_of_decision observation.decision)
    (match observation.route with None -> "" | Some route -> ", route " ^ route)
    (match observation.service with None -> "" | Some service -> ", service " ^ service)

let to_human report =
  match report.result with
  | Equivalent ->
    Printf.sprintf "EQUIVALENT  %s agree for every modeled request\n            Assurance: %s"
      (match report.mode with
       | Security_decision -> "security decisions"
       | Route_service -> "security decisions and selected route/service")
      report.profile
  | Unknown reason -> Printf.sprintf "UNKNOWN  %s" reason
  | Different witness ->
    let request = witness.request in
    Printf.sprintf
      "DIFFERENT  %s request %s %s makes the configs disagree\n           %s\n           %s\n           Assurance: %s"
      (if request.is_anon then "anonymous" else "authenticated")
      (if request.method_ = "" then "<any-method>" else request.method_)
      request.path (observation_human "before" witness.before)
      (observation_human "after" witness.after) report.profile

type repair_outcome =
  | Valid_repair
  | Contract_failed
  | Out_of_scope_regression of witness
  | Repair_unknown of string

type repair_report = {
  result          : repair_outcome;
  profile         : string;
  contract_report : Report.t;
  frozen_spec     : Contract_spec.t;
  mode            : mode;
}

let run_repair ?z3 ?emit_smt ?(mode = Security_decision) ~contract before_source
    after_source =
  match parse "before" before_source, parse "after" after_source with
  | Error error, _ | _, Error error -> Error error
  | Ok _, Ok _ ->
  match Verify.run ~property:(Contract_spec.to_property contract) after_source with
  | Error error -> Error error
  | Ok raw_contract_report ->
    let contract_report = Contract_spec.bind_report contract raw_contract_report in
    let profile = Assurance.profile.id in
    (match contract_report.result with
     | Report.Proved ->
       let outside = Ir.Not (Contract_spec.scope_condition contract) in
       (match
          run_comparison ?z3 ?emit_smt ~when_:outside ~mode before_source after_source
        with
        | Error error -> Error error
        | Ok comparison ->
          let result =
            match comparison.result with
            | Equivalent -> Valid_repair
            | Different witness -> Out_of_scope_regression witness
            | Unknown reason -> Repair_unknown reason
          in
          Ok { result; profile; contract_report; frozen_spec = contract; mode })
     | Report.Unknown reason ->
       Ok
         { result = Repair_unknown reason;
           profile;
           contract_report;
           frozen_spec = contract;
           mode }
     | Report.Vacuous | Report.Inconsistent _ | Report.Violated _ ->
       Ok
         { result = Contract_failed;
           profile;
           contract_report;
           frozen_spec = contract;
           mode })

let repair_to_json report =
  let comparison =
    match report.mode with
    | Security_decision -> "frozen_scope_preservation"
    | Route_service -> "frozen_route_service_preservation"
  in
  let head result =
    Printf.sprintf
      "\"result\":%s,\"schema_version\":1,\"comparison\":%s,\"assurance_profile\":%s,\"frozen_spec\":%s,\"contract_result\":%s"
      (jstring result) (jstring comparison) (jstring report.profile)
      (Contract_spec.canonical_json report.frozen_spec)
      (Report.to_json report.contract_report)
  in
  match report.result with
  | Valid_repair ->
    Printf.sprintf "{%s,\"witness\":null}" (head "valid_repair")
  | Contract_failed ->
    Printf.sprintf "{%s,\"witness\":null}" (head "contract_failed")
  | Out_of_scope_regression witness ->
    Printf.sprintf "{%s,\"witness\":%s}" (head "out_of_scope_regression")
      (witness_json witness)
  | Repair_unknown reason ->
    Printf.sprintf "{%s,\"witness\":null,\"reason\":%s}" (head "unknown")
      (jstring reason)

let repair_to_human report =
  match report.result with
  | Valid_repair ->
    Printf.sprintf
      "VALID REPAIR  replacement satisfies %s and preserves %s outside its frozen scope\n              Assurance: %s\n              Frozen spec: %s"
      report.contract_report.property_name
      (match report.mode with
       | Security_decision -> "every security decision"
       | Route_service -> "every security decision and selected route/service")
      report.profile
      (Contract_spec.canonical_json report.frozen_spec)
  | Contract_failed ->
    "INVALID REPAIR  replacement does not satisfy the frozen contract\n"
    ^ Report.to_human report.contract_report
  | Repair_unknown reason -> Printf.sprintf "UNKNOWN  %s" reason
  | Out_of_scope_regression witness ->
    let request = witness.request in
    Printf.sprintf
      "OUT-OF-SCOPE REGRESSION  %s request %s %s changed outside the frozen repair scope\n                         %s\n                         %s\n                         Frozen spec: %s"
      (if request.is_anon then "anonymous" else "authenticated")
      (if request.method_ = "" then "<any-method>" else request.method_)
      request.path (observation_human "before" witness.before)
      (observation_human "after" witness.after)
      (Contract_spec.canonical_json report.frozen_spec)
