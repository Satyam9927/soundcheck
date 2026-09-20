type feature = {
  code        : string;
  description : string;
}

type profile = {
  id           : string;
  connector    : string;
  version      : int;
  target       : string;
  modeled      : feature list;
  conservative : feature list;
  unsupported  : feature list;
}

type status = Within_profile | Conservative | Unsupported

type finding = {
  code    : string;
  service : string option;
  route   : string option;
  detail  : string;
}

type assessment = {
  status   : status;
  findings : finding list;
}

let feature code description = { code; description }

let profile =
  { id = "kong-traditional-http-v5";
    connector = "kong";
    version = 5;
    target = "Kong Gateway traditional/traditional_compatible HTTP routing";
    modeled =
      [ feature "literal-path-prefix" "literal HTTP path-prefix matching";
        feature "normalized-request-path" "Kong-normalized request-path domain and literal route validation";
        feature "regular-path-regex" "the documented regular subset of Kong path regexes";
        feature "http-method" "HTTP method matching";
        feature "lowercase-host" "lowercase exact and wildcard Host matching";
        feature "exact-header-match" "case-insensitive exact HTTP header matching, including repeated values";
        feature "http-https-protocol" "HTTP subsystem selection and HTTPS-only rejection";
        feature "exact-sni" "exact SNI matching for HTTPS and Kong's HTTP bypass";
        feature "traditional-route-priority" "two-layer traditional-router priority without created_at";
        feature "known-auth-plugins" "authentication requirement from Soundcheck's known plugin list";
        feature "known-rate-limit-plugins" "rate-limit coverage from Soundcheck's known plugin list";
        feature "ipv4-ip-restriction" "IPv4 ip-restriction allow and deny guards over Kong's derived client IP";
        feature "request-termination" "unconditional request-termination denial with Kong plugin precedence";
        feature "default-admin-ports" "Admin API recognition on default ports 8001 and 8444";
        feature "default-deny" "denying fallthrough when no route guard allows a request" ];
    conservative =
      [ feature "route-created-at-tie" "created_at is absent from decK and unresolved route order remains tied";
        feature "route-header-regex" "regex header values are over-approximated and the route is left incomparable";
        feature "wildcard-sni" "wildcard SNI depends on router flavor and is over-approximated";
        feature "route-stream-match" "source/destination criteria are over-approximated and the route is left incomparable";
        feature "uppercase-host" "uppercase route hosts are left incomparable because request hosts are lowercased";
        feature "unrecognized-plugin" "unrecognized plugins provide no modeled auth or rate-limit behavior";
        feature "invalid-ip-cidr" "IPv6 or malformed ip-restriction entries are dropped, weakening the guard";
        feature "conditional-request-termination" "triggered request-termination depends on unmodeled query parameters" ];
    unsupported =
      [ feature "unsupported-path-regex" "non-regular or untranslated regex constructs make the whole result unknown" ] }

let string_of_status = function
  | Within_profile -> "within_profile"
  | Conservative -> "conservative"
  | Unsupported -> "unsupported"

let finding ?service ?route code detail = { code; service; route; detail }

let plugin_findings ?route service plugins =
  List.concat_map
    (fun (plugin : Ast.plugin) ->
      if not plugin.enabled then []
      else
      let known =
        Lower.is_auth_plugin plugin.name || Lower.is_rate_limit_plugin plugin.name
        || plugin.name = "ip-restriction" || plugin.name = "request-termination"
      in
      let unknown =
        if known then []
        else
          [ finding ~service ?route "unrecognized-plugin"
              (Printf.sprintf "plugin %S has no modeled security semantics" plugin.name) ]
      in
      let invalid_cidrs =
        if plugin.name <> "ip-restriction" then []
        else
          List.filter_map
            (fun entry ->
              match Soundcheck_core.Cidr.parse entry with
              | Ok _ -> None
              | Error _ ->
                Some
                  (finding ~service ?route "invalid-ip-cidr"
                     (Printf.sprintf "ip-restriction entry %S is not modeled as IPv4" entry)))
            (plugin.allow @ plugin.deny)
      in
      let conditional_termination =
        match (plugin.name, plugin.trigger) with
        | "request-termination", Some trigger ->
          [ finding ~service ?route "conditional-request-termination"
              (Printf.sprintf
                 "request-termination trigger %S depends on header or query presence"
                 trigger) ]
        | _ -> []
      in
      unknown @ invalid_cidrs @ conditional_termination)
    plugins

let route_findings (service : Ast.service) (route : Ast.route) =
  let location code detail = finding ~service:service.name ~route:route.name code detail in
  let routing =
    (if
       List.exists
         (fun (_, values) -> Lower.is_header_regex values)
         (Lower.routable_headers route)
     then
       [ location "route-header-regex"
           "route has a regex header value that is conservatively approximated" ]
     else [])
    @ (if Lower.has_wildcard_sni route then
         [ location "wildcard-sni"
             "route has wildcard SNI behavior that depends on router flavor" ]
       else [])
    @ (if route.has_sources_or_destinations then
         [ location "route-stream-match" "route has source or destination matching criteria" ]
       else [])
    @ List.filter_map
        (fun host ->
          if String.lowercase_ascii host = host then None
          else Some (location "uppercase-host" (Printf.sprintf "route host %S contains uppercase" host)))
        route.hosts
  in
  let regex =
    List.filter_map
      (fun path ->
        if not (Fragment.is_regex_path path) then None
        else
          match Soundcheck_core.Regex.parse (Fragment.pattern_of path) with
          | Ok _ -> None
          | Error why ->
            Some
              (location "unsupported-path-regex"
                 (Printf.sprintf "path %S is unsupported: %s" path why)))
      route.paths
  in
  routing @ regex @ plugin_findings ~route:route.name service.name route.plugins

let assess (config : Ast.config) =
  let findings =
    List.concat_map
      (fun (service : Ast.service) ->
        plugin_findings service.name service.plugins
        @ List.concat_map (route_findings service) service.routes)
      config.services
  in
  let status =
    if List.exists (fun finding -> finding.code = "unsupported-path-regex") findings
    then Unsupported
    else if findings = [] then Within_profile
    else Conservative
  in
  { status; findings }

let escape_json value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | character -> Buffer.add_char buffer character)
    value;
  Buffer.contents buffer

let json_string value = "\"" ^ escape_json value ^ "\""

let features_json features =
  features
  |> List.map (fun (feature : feature) ->
         Printf.sprintf "{\"code\":%s,\"description\":%s}"
           (json_string feature.code) (json_string feature.description))
  |> String.concat ","
  |> Printf.sprintf "[%s]"

let profile_json () =
  Printf.sprintf
    "{\"schema_version\":1,\"id\":%s,\"connector\":%s,\"version\":%d,\"target\":%s,\"modeled\":%s,\"conservative\":%s,\"unsupported\":%s}"
    (json_string profile.id) (json_string profile.connector) profile.version
    (json_string profile.target) (features_json profile.modeled)
    (features_json profile.conservative) (features_json profile.unsupported)

let human_features title features =
  let rows =
    features
    |> List.map (fun (feature : feature) ->
           Printf.sprintf "  - %s: %s" feature.code feature.description)
    |> String.concat "\n"
  in
  Printf.sprintf "%s:\n%s" title rows

let profile_human () =
  String.concat "\n"
    [ Printf.sprintf "KONG ASSURANCE PROFILE  %s" profile.id;
      Printf.sprintf "Connector: %s" profile.connector;
      Printf.sprintf "Profile version: %d" profile.version;
      Printf.sprintf "Target: %s" profile.target;
      "";
      human_features "Modeled" profile.modeled;
      "";
      human_features "Conservative" profile.conservative;
      "";
      human_features "Unsupported" profile.unsupported ]
