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

let check (config : Ast.config) =
  let rec services = function
    | [] -> Ok ()
    | (service : Ast.service) :: rest ->
      let rec routes = function
        | [] -> services rest
        | (route : Ast.route) :: remaining ->
          let rec paths = function
            | [] -> routes remaining
            | path :: tail ->
              (match check_path service route path with
               | Ok () -> paths tail
               | Error _ as error -> error)
          in
          paths route.paths
      in
      routes service.routes
  in
  services config.services
