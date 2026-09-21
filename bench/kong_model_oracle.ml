open Soundcheck_core
open Soundcheck_kong

let usage () =
  prerr_endline
    "usage: kong_model_oracle CONFIG METHOD PATH HOST [HEADER-NAME:VALUE ...]";
  exit 2

let parse_header value =
  match String.index_opt value ':' with
  | Some index ->
    let name = String.sub value 0 index |> String.lowercase_ascii in
    let contents =
      String.sub value (index + 1) (String.length value - index - 1)
      |> String.lowercase_ascii
    in
    (name, contents)
  | None ->
    prerr_endline (Printf.sprintf "invalid header %S (expected NAME:VALUE)" value);
    exit 2

let service_for_route (config : Ast.config) route =
  let services =
    List.filter_map
      (fun (service : Ast.service) ->
        if List.exists (fun (candidate : Ast.route) -> candidate.name = route) service.routes
        then Some service.name
        else None)
      config.services
    |> List.sort_uniq String.compare
  in
  match services with
  | [] -> "-"
  | [ service ] -> service
  | _ ->
    prerr_endline
      (Printf.sprintf "route name %S is not unique across services" route);
    exit 2

let () =
  if Array.length Sys.argv < 5 then usage ();
  let config =
    match Parse.parse_file Sys.argv.(1) with
    | Ok config -> config
    | Error error -> prerr_endline error; exit 2
  in
  (match Validate.check config with
   | Error error -> prerr_endline error; exit 2
   | Ok () -> ());
  (match Fragment.check config with
   | Error error -> prerr_endline error; exit 2
   | Ok () -> ());
  let headers =
    List.init (Array.length Sys.argv - 5) (fun index ->
        parse_header Sys.argv.(index + 5))
  in
  let request : Ir.request =
    { principal = Anonymous;
      action = String.uppercase_ascii Sys.argv.(2);
      resource = Sys.argv.(3);
      context = headers;
      source = 0l;
      host = String.lowercase_ascii Sys.argv.(4);
      scheme = "http";
      sni = "" }
  in
  let policy = Lower.to_policy config in
  let routes =
    policy.rules
    |> List.filter (Ir.selected policy request)
    |> List.map (fun (rule : Ir.rule) -> rule.id)
    |> List.sort_uniq String.compare
  in
  let route, service =
    match routes with
    | [] -> ("-", "-")
    | [ route ] -> (route, service_for_route config route)
    | _ ->
      prerr_endline
        ("model leaves multiple routes selectable: " ^ String.concat ", " routes);
      exit 2
  in
  Printf.printf "%s\t%s\t%s\n"
    (Ir.evaluate policy request |> Ir.string_of_decision |> String.lowercase_ascii)
    route service
