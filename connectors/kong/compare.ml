open Soundcheck_core

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

let unresolved_pairs (policy : Ir.policy) =
  let rec pairs = function
    | [] -> []
    | rule :: rest -> List.map (fun other -> (rule, other)) rest @ pairs rest
  in
  pairs policy.rules
  |> List.filter (fun ((left : Ir.rule), (right : Ir.rule)) ->
         not (Ir.outranks left.priority right.priority)
         && not (Ir.outranks right.priority left.priority)
         && (left.decision <> right.decision || left.guard <> right.guard))

let exact_policy ?(z3 = "z3") label (policy : Ir.policy) =
  if List.exists (fun (rule : Ir.rule) -> not rule.match_complete) policy.rules
  then Error (label ^ " config contains an incomplete route match")
  else
    let rec check = function
      | [] -> Ok ()
      | ((left : Ir.rule), (right : Ir.rule)) :: rest ->
        let query =
          Smt_encode.condition_query ~domain:policy.request_domain
            ~name:"route-order-determinism"
            ~description:"unresolved routes with different decisions or guards overlap"
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
    check (unresolved_pairs policy)

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

let run ?(z3 = "z3") ?emit_smt before_source after_source =
  match parse "before" before_source, parse "after" after_source with
  | Error error, _ | _, Error error -> Error error
  | Ok before_config, Ok after_config ->
    let profile = Assurance.profile.id in
    let before_assessment = Assurance.assess before_config in
    let after_assessment = Assurance.assess after_config in
    if before_assessment.status <> Assurance.Within_profile then
      Ok
        { result = Unknown (assessment_reason "before" before_assessment);
          profile }
    else if after_assessment.status <> Assurance.Within_profile then
      Ok
        { result = Unknown (assessment_reason "after" after_assessment);
          profile }
    else
      let before_policy = Lower.to_policy before_config in
      let after_policy = Lower.to_policy after_config in
      (match exact_policy ~z3 "before" before_policy with
       | Error reason -> Ok { result = Unknown reason; profile }
       | Ok () ->
         match exact_policy ~z3 "after" after_policy with
         | Error reason -> Ok { result = Unknown reason; profile }
         | Ok () ->
         let query =
           Smt_encode.decision_equivalence_query before_policy after_policy
         in
         match Solve.check ~z3 ?emit_smt query with
         | Solve.Proved -> Ok { result = Equivalent; profile }
         | Solve.Unknown reason -> Ok { result = Unknown reason; profile }
         | Solve.Violated request ->
           Ok
             { result =
                 Different
                   { request;
                     before = observe before_config before_policy request;
                     after = observe after_config after_policy request };
               profile })

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
  let head =
    Printf.sprintf "\"schema_version\":1,\"comparison\":\"security_decision\",\"assurance_profile\":%s"
      (jstring report.profile)
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
    Printf.sprintf "EQUIVALENT  security decisions agree for every modeled request\n            Assurance: %s"
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
