let () =
  try
    match Array.to_list Sys.argv with
    | [ _; manifest_path ] ->
      let root = Unix.realpath (Filename.dirname manifest_path) in
      (match Pilot.read_regular ~root (Filename.basename manifest_path) with
       | Error () -> print_endline (Pilot.fatal_json "manifest_read_error"); exit 1
       | Ok source ->
         match Pilot.parse_manifest source with
         | Error () -> print_endline (Pilot.fatal_json "manifest_invalid"); exit 1
         | Ok manifest ->
           let rows = Pilot.run ~root manifest in
           print_endline (Pilot.to_json rows);
           exit (Pilot.exit_code rows))
    | _ ->
      prerr_endline "usage: dune exec bench/pilot/main.exe -- MANIFEST.yaml";
      exit 2
  with _ ->
    (* Input errors and exceptions may contain private paths/config values. *)
    print_endline (Pilot.fatal_json "runner_error");
    exit 1
