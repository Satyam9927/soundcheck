let read_all channel =
  let buffer = Buffer.create 512 in
  (try
     while true do
       Buffer.add_string buffer (input_line channel);
       Buffer.add_char buffer '\n'
     done
   with End_of_file -> ());
  Buffer.contents buffer

let expected_exit = function
  | "proved" -> 0
  | "violated" -> 3
  | "unknown" -> 4
  | "vacuous" -> 5
  | result -> failwith ("unknown expected result " ^ result)

let run soundcheck file result extra =
  let arguments =
    Array.of_list
      ([ soundcheck; "verify"; file; "--format"; "github" ] @ extra)
  in
  let channel = Unix.open_process_args_in soundcheck arguments in
  let output = read_all channel in
  let status = Unix.close_process_in channel in
  let expected = expected_exit result in
  (match status with
   | Unix.WEXITED actual when actual = expected -> ()
   | _ -> failwith (Printf.sprintf "%s did not exit %d" result expected));
  let level = if result = "proved" then "notice" else "error" in
  let prefix = Printf.sprintf "::%s file=%s,title=Soundcheck%%3A " level file in
  if not (String.starts_with ~prefix output) then
    failwith (Printf.sprintf "unexpected %s annotation: %s" result output)

let () =
  if Array.length Sys.argv <> 5 then
    failwith "expected soundcheck and three Kong config paths";
  let soundcheck = Sys.argv.(1) in
  run soundcheck Sys.argv.(2) "violated" [];
  run soundcheck Sys.argv.(3) "proved" [];
  run soundcheck Sys.argv.(4) "unknown" [];
  run soundcheck Sys.argv.(3) "vacuous"
    [ "--property"; "admin-api-not-reachable"; "--trusted-cidr";
      "0.0.0.0/0" ]
