let check_path (service : Ast.service) (route : Ast.route) path =
  if Fragment.is_regex_path path then Ok ()
  else if not (Path_normalization.has_valid_percent_encoding path) then
    Error
      (Printf.sprintf
         "invalid Kong config: route %S (service %S) path %S has an invalid percent escape"
         route.Ast.name service.Ast.name path)
  else if Path_normalization.is_normalized_literal path then Ok ()
  else
    Error
      (Printf.sprintf
         "invalid Kong config: route %S (service %S) literal path %S is not normalized; use %S"
         route.Ast.name service.Ast.name path
         (Path_normalization.normalize_literal path))

let protocol_family = function
  | "http" | "https" -> Some "http"
  | "tcp" | "tls" | "udp" -> Some "stream"
  | "tls_passthrough" -> Some "tls_passthrough"
  | "grpc" | "grpcs" -> Some "grpc"
  | _ -> None

let check_route (service : Ast.service) (route : Ast.route) =
  if route.protocols = [] then
    Error
      (Printf.sprintf
         "invalid Kong config: route %S (service %S) protocols must not be empty"
         route.name service.name)
  else
    let families =
      List.filter_map protocol_family route.protocols |> List.sort_uniq compare
    in
    if
      List.exists (fun protocol -> Option.is_none (protocol_family protocol))
        route.protocols
      || List.length families <> 1
    then
      Error
        (Printf.sprintf
           "invalid Kong config: route %S (service %S) has unknown or incompatible protocols"
           route.name service.name)
    else if
      route.snis <> []
      && not
           (List.for_all
              (fun protocol ->
                List.mem protocol [ "https"; "grpcs"; "tls"; "tls_passthrough" ])
              route.protocols)
    then
      Error
        (Printf.sprintf
           "invalid Kong config: route %S (service %S) snis require secure protocols"
           route.name service.name)
    else Ok ()

let check_scoped_plugin (config : Ast.config) (scoped : Ast.scoped_plugin) =
  if scoped.consumer_scoped || scoped.unsupported_reference then Ok ()
  else
    let service =
      Option.bind scoped.service (fun name ->
          List.find_opt (fun (service : Ast.service) -> service.name = name)
            config.services)
    in
    let route_owner =
      Option.bind scoped.route (fun name ->
          List.find_map
            (fun (service : Ast.service) ->
              Option.map (fun route -> (service, route))
                (List.find_opt
                   (fun (route : Ast.route) -> route.name = name)
                   service.routes))
            config.services)
    in
    match (scoped.service, service, scoped.route, route_owner) with
    | Some name, None, _, _ ->
      Error
        (Printf.sprintf
           "invalid Kong config: root plugin %S references unknown service %S"
           scoped.plugin.name name)
    | _, _, Some name, None when not config.has_top_level_routes ->
      Error
        (Printf.sprintf
           "invalid Kong config: root plugin %S references unknown route %S"
           scoped.plugin.name name)
    | Some service_name, Some _, Some route_name, Some (owner, _)
      when owner.name <> service_name ->
      Error
        (Printf.sprintf
           "invalid Kong config: root plugin %S references route %S outside service %S"
           scoped.plugin.name route_name service_name)
    | _ -> Ok ()

let check (config : Ast.config) =
  let rec services = function
    | [] -> Ok ()
    | (service : Ast.service) :: rest ->
      let rec routes = function
        | [] -> services rest
        | (route : Ast.route) :: remaining ->
          (match check_route service route with
           | Error _ as error -> error
           | Ok () ->
          let rec paths = function
            | [] -> routes remaining
            | path :: tail ->
              (match check_path service route path with
               | Ok () -> paths tail
               | Error _ as error -> error)
          in
          paths route.paths)
      in
      routes service.routes
  in
  match services config.services with
  | Error _ as error -> error
  | Ok () ->
    let rec scoped = function
      | [] -> Ok ()
      | plugin :: rest ->
        (match check_scoped_plugin config plugin with
         | Ok () -> scoped rest
         | Error _ as error -> error)
    in
    scoped config.scoped_plugins
