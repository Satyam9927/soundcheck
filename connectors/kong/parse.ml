(* Parse a decK YAML document into {!Ast.config} using the [yaml] library.
   Unknown keys are ignored; missing keys default to empty. *)

(* --- helpers over Yaml.value ([`O]/[`A]/[`String]/...) --- *)

let member key (v : Yaml.value) : Yaml.value option =
  match v with `O kvs -> List.assoc_opt key kvs | _ -> None

let to_string = function `String s -> Some s | _ -> None

let string_list (v : Yaml.value option) : string list =
  match v with Some (`A xs) -> List.filter_map to_string xs | _ -> []

let headers_of (v : Yaml.value option) : (string * string list) list =
  match v with
  | Some (`O fields) ->
    List.map (fun (name, values) -> (name, string_list (Some values))) fields
  | _ -> []

(* Kong treats a plugin as enabled unless it says otherwise, so an absent or
   non-boolean [enabled] key means true. Only an explicit [false] disables. *)
let enabled_of (v : Yaml.value) : bool =
  match member "enabled" v with Some (`Bool b) -> b | _ -> true

let bool_in key value ~default =
  match member key value with Some (`Bool boolean) -> boolean | _ -> default

let plugin_of x =
  match member "name" x with
  | Some (`String name) ->
    let cfg = member "config" x in
    let list_in key =
      match cfg with Some value -> string_list (member key value) | None -> []
    in
    Some
      ({ name; enabled = enabled_of x;
         allow = list_in "allow"; deny = list_in "deny";
         trigger =
           (match cfg with
            | Some value -> Option.bind (member "trigger" value) to_string
            | None -> None);
         anonymous_fallback =
           (match cfg with
            | Some value ->
              (match member "anonymous" value with
               | None | Some `Null -> false
               | Some _ -> true)
            | None -> false);
         run_on_preflight =
           (match cfg with
            | Some value -> bool_in "run_on_preflight" value ~default:true
            | None -> true) }
        : Ast.plugin)
  | _ -> None

let plugins_of = function
  | Some (`A values) -> List.filter_map plugin_of values
  | _ -> []

let has_relationship value =
  List.exists
    (fun key ->
      match member key value with None | Some `Null -> false | Some _ -> true)
    [ "route"; "service"; "consumer"; "consumer_group" ]

let relationship_name key value =
  match member key value with
  | None | Some `Null -> (None, false)
  | Some (`String name) -> (Some name, false)
  | Some _ -> (None, true)

let relationship_present key value =
  match member key value with None | Some `Null -> false | Some _ -> true

let root_plugins_of = function
  | Some (`A values) ->
    List.fold_right
      (fun value (global, scoped) ->
        match plugin_of value with
        | None -> (global, scoped)
        | Some plugin when has_relationship value ->
          let service, unsupported_service =
            relationship_name "service" value
          in
          let route, unsupported_route = relationship_name "route" value in
          let scoped_plugin : Ast.scoped_plugin =
            { plugin;
              service;
              route;
              consumer_scoped =
                relationship_present "consumer" value
                || relationship_present "consumer_group" value;
              unsupported_reference =
                unsupported_service || unsupported_route }
          in
          (global, scoped_plugin :: scoped)
        | Some plugin -> (plugin :: global, scoped))
      values ([], [])
  | _ -> ([], [])

let name_of v ~default =
  match member "name" v with Some (`String s) -> s | _ -> default

(* YAML numbers arrive as floats; Kong's schema default is 0 when absent. *)
let int_field key v ~default =
  match member key v with
  | Some (`Float f) -> int_of_float f
  | Some (`String s) -> (try int_of_string (String.trim s) with _ -> default)
  | _ -> default

let optional_int_field key v =
  match member key v with
  | Some (`Float f) -> Some (int_of_float f)
  | Some (`String s) -> int_of_string_opt (String.trim s)
  | _ -> None

let optional_string_field key v = Option.bind (member key v) to_string

let route_of (v : Yaml.value) : Ast.route =
  {
    name = name_of v ~default:"<unnamed-route>";
    paths = string_list (member "paths" v);
    methods = string_list (member "methods" v);
    protocols =
      (match member "protocols" v with
       | None -> [ "http"; "https" ]
       | some -> string_list some);
    plugins = plugins_of (member "plugins" v);
    hosts = string_list (member "hosts" v);
    snis = string_list (member "snis" v);
    headers = headers_of (member "headers" v);
    has_sources_or_destinations =
      (match (member "sources" v, member "destinations" v) with
       | Some (`A (_ :: _)), _ | _, Some (`A (_ :: _)) -> true
       | _ -> false);
    regex_priority = int_field "regex_priority" v ~default:0;
  }

let service_of (v : Yaml.value) : Ast.service =
  {
    name = name_of v ~default:"<unnamed-service>";
    url = optional_string_field "url" v;
    protocol = optional_string_field "protocol" v;
    host = optional_string_field "host" v;
    port = optional_int_field "port" v;
    path = optional_string_field "path" v;
    routes =
      (match member "routes" v with Some (`A xs) -> List.map route_of xs | _ -> []);
    plugins = plugins_of (member "plugins" v);
  }

let top_level_route_of value : Ast.top_level_route =
  let service, unsupported_reference = relationship_name "service" value in
  { route = route_of value; service; unsupported_reference }

let config_of (v : Yaml.value) : Ast.config =
  let global_plugins, scoped_plugins = root_plugins_of (member "plugins" v) in
  let top_level_routes =
    match member "routes" v with
    | Some (`A values) -> List.map top_level_route_of values
    | _ -> []
  in
  let services =
    match member "services" v with
    | Some (`A values) -> List.map service_of values
    | _ -> []
  in
  let services =
    List.map
      (fun (service : Ast.service) ->
        let referenced_routes =
          List.filter_map
            (fun (top : Ast.top_level_route) ->
              if
                not top.unsupported_reference
                && top.service = Some service.name
              then Some top.route
              else None)
            top_level_routes
        in
        { service with routes = service.routes @ referenced_routes })
      services
  in
  {
    services;
    global_plugins;
    scoped_plugins;
    top_level_routes;
  }

let parse_string (s : string) : (Ast.config, string) result =
  match Yaml.of_string s with
  | Ok v -> Ok (config_of v)
  | Error (`Msg m) -> Error m

(* Read a file to a string. File I/O is kept separate from parsing so adapters
   (the CLI) can read a path and hand the text to the shared {!Verify.run}, while
   {!parse_string} stays the entry for already-in-memory config (the MCP tool). *)
let read_file (path : string) : (string, string) result =
  try
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    Ok s
  with Sys_error e -> Error e

let parse_file (path : string) : (Ast.config, string) result =
  match read_file path with Ok s -> parse_string s | Error e -> Error e
