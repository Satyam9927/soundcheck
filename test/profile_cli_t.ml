open Soundcheck_kong

let read_all channel =
  let buffer = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_string buffer (input_line channel);
       Buffer.add_char buffer '\n'
     done
   with End_of_file -> ());
  Buffer.contents buffer

let run soundcheck format =
  let arguments = [| soundcheck; "profile"; "kong"; "--format"; format |] in
  let channel = Unix.open_process_args_in soundcheck arguments in
  let output = read_all channel in
  match Unix.close_process_in channel with
  | Unix.WEXITED 0 -> output
  | _ -> failwith ("soundcheck profile kong --format " ^ format ^ " failed")

let expect_output soundcheck format expected =
  let actual = run soundcheck format in
  let expected = expected ^ "\n" in
  if actual <> expected then
    failwith (Printf.sprintf "unexpected %s profile output\nexpected: %s\nactual: %s"
                format expected actual)

let () =
  if Array.length Sys.argv <> 2 then failwith "expected path to soundcheck executable";
  let soundcheck = Sys.argv.(1) in
  expect_output soundcheck "human" (Assurance.profile_human ());
  expect_output soundcheck "json" (Assurance.profile_json ())
