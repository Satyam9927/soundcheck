type result =
  | Proved
  | Vacuous of Contract.clause
  | Inconsistent of Contract.clause * Contract.clause
  | Violated of Contract.clause * Solve.model
  | Unknown of string

let rec check_inhabited domain = function
  | [] -> None
  | clause :: rest ->
    let query =
      Smt_encode.condition_query ~domain ~name:(Contract.name clause)
        ~description:(Contract.description clause)
        (Contract.request_class clause)
    in
    (match Solve.check query with
     | Solve.Proved -> Some (Vacuous clause)
     | Solve.Unknown reason -> Some (Unknown reason)
     | Solve.Violated _ -> check_inhabited domain rest)

let rec check_consistent domain = function
  | [] -> None
  | (safety, functionality) :: rest ->
    (match Solve.check (Smt_encode.overlap_query ~domain safety functionality) with
     | Solve.Violated _ -> Some (Inconsistent (safety, functionality))
     | Solve.Unknown reason -> Some (Unknown reason)
     | Solve.Proved -> check_consistent domain rest)

let rec check_clauses policy = function
  | [] -> Proved
  | clause :: rest ->
    (match Solve.check (Smt_encode.contract_clause_query policy clause) with
     | Solve.Violated model -> Violated (clause, model)
     | Solve.Unknown reason -> Unknown reason
     | Solve.Proved -> check_clauses policy rest)

let run policy contract =
  match check_inhabited policy.Ir.request_domain contract.Contract.clauses with
  | Some result -> result
  | None ->
    (match
       check_consistent policy.request_domain
         (Contract.safety_functionality_overlaps contract)
     with
     | Some result -> result
     | None -> check_clauses policy contract.clauses)
