val render : file:string -> Soundcheck_core.Report.t -> string
(** Render one GitHub workflow-command annotation for a verification report. *)

val error : file:string -> title:string -> string -> string
(** Render an error annotation for failures that occur before a report exists. *)
