module Index = Context.Index
module Btree = Context.MyBtree

let () = Printexc.record_backtrace true

let ( // ) a b = a ^ "/" ^ b

let rec rm_R dir =
  (* rm -R implementation *)
  if Sys.is_directory dir then (
    Array.iter (fun name -> rm_R (dir // name)) (Sys.readdir dir);
    Unix.rmdir dir)
  else Sys.remove dir

let with_progress_bar ~message ~n ~unit =
  let open Progress in
  let w = if n = 0 then 1 else float_of_int n |> log10 |> floor |> int_of_float |> succ in
  let w_pp = Printer.int ~width:w in
  let bar =
    Line.(
      list
        [
          const message;
          count_to ~pp:w_pp n;
          const unit;
          elapsed ();
          bar ~style:`UTF8 ~color:(`magenta |> Color.ansi) n;
          eta n |> brackets;
        ])
  in
  Progress.with_reporter bar

let main setup_log n fresh =
  let from = Fmt.str "generate_index_%i" n in
  let dist = Fmt.str "generate_btree_%i" n in

  let cached = Sys.file_exists from in
  if fresh && cached then rm_R from;
  if not (Sys.file_exists from) then Unix.mkdir from 0o777;
  if not (Sys.file_exists dist) then Unix.mkdir dist 0o777;
  setup_log dist;
  let index = Index.v from in
  if fresh || not cached then (
    with_progress_bar ~message:"Creating index" ~n ~unit:"bindings" @@ fun prog ->
    for i = 1 to n do
      if i mod 43 = 0 then prog 43;
      Encoding.random () |> fun (k, v) -> Index.replace index k v
    done;
    prog (n mod 43));
  Index.filter index (fun _ -> true) (* [filter] flushes [log] and [log_async] into [data] :D *);
  let from = from // "index" in
  if Sys.file_exists dist then rm_R dist;
  let btree = Btree.v dist from in
  Index.iter (fun k v -> assert (Btree.find btree k = v)) index;
  Index.close index;
  Btree.close btree

let startswith s prefix =
  let l = String.length prefix in
  String.length s >= l && String.sub s 0 l = prefix

let clean dir =
  Array.iter
    (fun name ->
      if startswith name "generate_index_" || startswith name "generate_btree_" then rm_R name)
    (Sys.readdir dir)

open Cmdliner

let setup_log = Term.(const Context.setup_btreelog $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let env_var s = Arg.env_var ("MIGRATION_" ^ s)

let n_bindings =
  let doc = "The number of bindings." in
  let env = env_var "NUM_BINDINGS" in
  Arg.(value & opt int 10_000 & info [ "n"; "num-bindings" ] ~env ~doc)

let fresh =
  let doc = "Don't use already existing index files. Btree is always recomputed." in
  let env = env_var "FRESH" in
  Arg.(value & flag & info [ "fresh" ] ~env ~doc)

let dir =
  let doc = "Directory to clean." in
  Arg.(value & pos 0 string "." & info [] ~doc)

let clean_cmd =
  let doc = "Delete all generated files." in
  (Term.(const clean $ dir), Term.info "clean" ~doc ~exits:Term.default_exits)

let cmd =
  let doc = "Generate an index and migrate it to btrees." in
  ( Term.(const main $ setup_log $ n_bindings $ fresh),
    Term.info "generate" ~doc ~exits:Term.default_exits )

let () =
  let choices = [ clean_cmd ] in
  Term.(exit @@ eval_choice cmd choices)
