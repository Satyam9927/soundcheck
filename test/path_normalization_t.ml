open Soundcheck_core
open Soundcheck_kong

let expect_normalized raw expected =
  let actual = Path_normalization.normalize_literal raw in
  if actual <> expected then
    failwith
      (Printf.sprintf "normalize %S: expected %S, got %S" raw expected actual);
  if not (Path_normalization.is_normalized_request_path expected) then
    failwith (Printf.sprintf "normalized output %S is outside request domain" expected)

let expect_not_normalized path =
  if Path_normalization.is_normalized_request_path path then
    failwith (Printf.sprintf "unnormalized request path accepted: %S" path)

let contains haystack needle =
  let haystack_length = String.length haystack in
  let needle_length = String.length needle in
  let rec search offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || search (offset + 1))
  in
  needle_length = 0 || search 0

let () =
  (* Transcribed from Kong's kong.tools.uri unit cases. *)
  List.iter (fun (raw, expected) -> expect_normalized raw expected)
    [ ("/a%2fb%2fc/", "/a%2Fb%2Fc/");
      ("/f%6f%6f", "/foo");
      ("/%6B%6f%6e%67", "/kong");
      ("/%2E", "/");
      ("/./.././../", "/");
      ("/a/b/c/./../../g", "/a/g");
      ("/a//b//", "/a/b/") ];

  List.iter expect_not_normalized
    [ ""; "/a//b"; "/a/./b"; "/a/../b"; "/%2e"; "/%41";
      "/a%2fb"; "/a%zz" ];

  List.iter
    (fun path ->
      if not (Path_normalization.is_normalized_request_path path) then
        failwith (Printf.sprintf "canonical request path rejected: %S" path))
    [ "/"; "/admin"; "/a.../b"; "/a%2Fb"; "/endeløst" ];

  let impossible =
    Smt_encode.condition_query ~domain:Path_normalization.request_domain
      ~name:"normalized-domain" ~description:"exclude raw paths"
      (Ir.Path_exact "/admin/../secret")
    |> Solve.check
  in
  (match impossible with
   | Solve.Proved -> ()
   | _ -> failwith "SMT request domain admitted an unnormalized path");

  let outside_request : Ir.request =
    { principal = Anonymous;
      action = "GET";
      resource = "/raw/../path";
      context = [];
      source = 0l;
      host = "";
      scheme = "http";
      sni = "" }
  in
  let allow_by_default : Ir.policy =
    { request_domain = Path_normalization.request_domain;
      rules = [];
      default = Allow }
  in
  if Ir.evaluate allow_by_default outside_request <> Deny
     || Ir.definitely_allows allow_by_default outside_request
  then failwith "concrete policy evaluation admitted a request outside its domain";

  let invalid_config =
    "services: [{name: api, routes: [{name: bad, paths: [/admin/%2e%2e/secret]}]}]"
  in
  (match
     Verify.run ~property:(Verify.No_anonymous_access "/admin") invalid_config
   with
   | Error error when contains error "not normalized; use \"/secret\"" -> ()
   | Error error -> failwith ("unexpected invalid-path error: " ^ error)
   | Ok _ -> failwith "non-normalized literal Kong route path was accepted");

  (match
     Verify.run ~property:(Verify.No_anonymous_access "/admin/../secret")
       "services: []"
   with
   | Error error when contains error "property path_prefix" -> ()
   | Error error -> failwith ("unexpected property-scope error: " ^ error)
   | Ok _ -> failwith "non-normalized property scope was accepted");

  (* Percent signs in authored regexes are regex syntax, not URI escapes. *)
  (match
     Verify.run ~property:(Verify.No_anonymous_access "/admin")
       "services: [{name: api, routes: [{name: regex, paths: ['~/admin%bar']}]}]"
   with
   | Ok _ -> ()
   | Error error -> failwith ("regex path was URI-normalized: " ^ error))
