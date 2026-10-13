(* Retained only to make historical invocations fail explicitly. The old survey
   duplicated stale semantics (nested routes, generic regex acceptance, and
   unknown-plugin treatment), so it cannot supply v11 coverage evidence. *)
let () =
  prerr_endline
    "The historical directory survey is retired: its heuristic counts are not current assurance evidence.\n\
     Use the explicit, frozen-contract local evaluator documented in bench/pilot/README.md.\n\
     No inputs were scanned or verified.";
  exit 2
