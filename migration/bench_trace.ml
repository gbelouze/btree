let with_timer f =
  let t0 = Sys.time () in
  let a = f () in
  let t1 = Sys.time () -. t0 in
  (t1, a)

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

module FSHelper = struct
  let file f = try (Unix.stat f).st_size with Unix.Unix_error (Unix.ENOENT, _, _) -> 0

  let index root =
    let index_dir = Filename.concat root "index" in
    let a = file (Filename.concat index_dir "data") in
    let b = file (Filename.concat index_dir "log") in
    let c = file (Filename.concat index_dir "log_async") in
    (a + b + c) / 1024 / 1024

  let size root = index root

  let get_size root = size root

  let rm_dir root =
    if Sys.file_exists root then (
      let cmd = Printf.sprintf "rm -rf %s" root in
      Logs.info (fun l -> l "exec: %s" cmd);
      let _ = Sys.command cmd in
      ())
end

let decoded_seq_of_encoded_chan_with_prefixes : 'a Repr.ty -> in_channel -> 'a Seq.t =
 fun repr channel ->
  let decode_bin = Repr.decode_bin repr |> Repr.unstage in
  let decode_prefix = Repr.(decode_bin int32 |> unstage) in
  let produce_op () =
    try
      (* First read the prefix *)
      let prefix = really_input_string channel 4 in
      let len', len = decode_prefix prefix 0 in
      assert (len' = 4);
      let len = Int32.to_int len in
      (* Then read the repr *)
      let content = really_input_string channel len in
      let len', op = decode_bin content 0 in
      assert (len' = len);
      Some (op, ())
    with End_of_file -> None
  in
  Seq.unfold produce_op ()

type int63 = Encoding.int63 [@@deriving repr]

type config = { commit_data_file : string; root : string; nofalse : bool }

module Trace = struct
  type key = string [@@deriving repr]

  type op = Flush | Mem of key * bool | Find of key * bool | Add of key * (int63 * int * char)
  [@@deriving repr]

  let open_ops_sequence path : op Seq.t =
    let chan = open_in_bin path in
    decoded_seq_of_encoded_chan_with_prefixes op_t chan
end

module Benchmark = struct
  type result = { time : float; size : int }

  let run config f =
    let time, res = with_timer f in
    let size = FSHelper.get_size config.root in
    ({ time; size }, res)

  let pp_results ppf result =
    Format.fprintf ppf "Total time: %f@\nSize on disk: %d M" result.time result.size
end

module type S = sig
  type key

  type value

  type t

  val find : t -> key -> value

  val mem : t -> key -> bool

  val replace : t -> key -> value -> unit

  val flush : t -> unit

  val v : string -> t

  val close : t -> unit
end

module Index = Context.Index

module MyBtree = struct
  include Context.MyBtree

  let v root = v root "index_BL/index"
end

type bins = { add : Mybentov.bin list; mem : Mybentov.bin list; find : Mybentov.bin list }
[@@deriving repr]

module Bench_suite (Store : S with type key = Encoding.Hash.t and type value = int63 * int * char) =
struct
  type histos = { add : Mybentov.histogram; mem : Mybentov.histogram; find : Mybentov.histogram }

  let key_to_hash k =
    match Encoding.Hash.of_string k with
    | Ok k -> k
    | Error (`Msg m) -> Fmt.failwith "error decoding hash %s" m

  let timeit hist func =
    let before = Mtime_clock.now () in
    func ();
    let after = Mtime_clock.now () in
    let span = Mtime.span before after |> Mtime.Span.to_us in
    Mybentov.add (Float.log span) hist

  (* use the log to spread small values into several bins *)

  let add_operation ?n config store op_seq () =
    with_progress_bar ~message:"Replaying trace"
      ~n:(match n with None -> 164_502_918 | Some n -> n)
      ~unit:"operations"
    @@ fun progress ->
    let histos : histos =
      { add = Mybentov.create 50; mem = Mybentov.create 50; find = Mybentov.create 50 }
    in
    let rec aux op_seq i =
      match n with
      | Some n when n <= i -> i
      | _ -> (
          match op_seq () with
          | Seq.Nil -> i
          | Cons (Trace.Flush, op_seq) -> aux op_seq i
          | Cons (op, op_seq) ->
              (match op with
              | Add (k, v) ->
                  let k = key_to_hash k in
                  timeit histos.add @@ fun () -> Store.replace store k v
              | Find (k, b) ->
                  let k = key_to_hash k in
                  timeit histos.find @@ fun () ->
                  let b' =
                    try
                      Store.find store k |> ignore;
                      true
                    with Not_found -> false
                  in
                  assert (config.nofalse || b = b')
              | Mem (k, b) ->
                  let k = key_to_hash k in
                  timeit histos.mem @@ fun () ->
                  let b' = Store.mem store k in
                  assert (config.nofalse || b' = b)
              | Flush -> () (* this cannot happen *));
              progress 1;
              aux op_seq (i + 1))
    in
    ( ({
         add = histos.add |> Mybentov.bins;
         find = histos.find |> Mybentov.bins;
         mem = histos.mem |> Mybentov.bins;
       }
        : bins),
      aux op_seq 0 )

  let run_read_trace config n_opt =
    let op_seq = Trace.open_ops_sequence config.commit_data_file in
    let store = Store.v config.root in

    let result, (bins, nb_ops) =
      (match n_opt with
      | None -> add_operation config store op_seq
      | Some n -> add_operation ~n config store op_seq)
      |> Benchmark.run config
    in

    Store.close store;
    let out = config.root ^ "/histo" in
    let outchan = open_out_gen [ Open_append; Open_creat; Open_trunc ] 0o655 out in
    let outppf = Format.formatter_of_out_channel outchan in
    bins |> Repr.(bins_t |> to_json_string) |> Fmt.pf outppf "%s@.";
    fun ppf ->
      Format.fprintf ppf "Tezos trace for %d nb_ops @\nResults: @\n%a@\n" nb_ops
        Benchmark.pp_results result
end

let main style_renderer level commit_data_file btree nofalse n_opt =
  let module Choice = (val if btree then (module MyBtree) else (module Index) : S
                         with type key = Encoding.Hash.t
                          and type value = int63 * int * char)
  in
  let module Bench = Bench_suite (Choice) in
  Printexc.record_backtrace true;
  Random.self_init ();
  let config =
    {
      commit_data_file;
      root = (if btree then Fmt.str "btree_BL%i" MyBtree.version else "index_BL");
      nofalse;
    }
  in
  if btree then Context.setup_btreelog style_renderer level config.root
  else Context.setup_indexlog style_renderer level;

  let results = Bench.run_read_trace config n_opt in
  Logs.app (fun l -> l "%a@." (fun ppf f -> f ppf) results);
  if btree then Fmt.pr "%a@." Btree.Private.Stats.pp (Btree.Private.Stats.get ())

open Cmdliner

let commit_data_file =
  let doc = Arg.info ~docv:"PATH" ~doc:"Trace of Tezos operations to be replayed." [] in
  Arg.(required @@ pos 0 (some string) None doc)

let btree =
  let doc = "Use btree instead of index." in
  Arg.(value & flag & info [ "btree" ] ~doc)

let nofalse =
  let doc = "Don't fail on false positive" in
  Arg.(value & flag & info [ "no-false" ] ~doc)

let n_op =
  let doc = "Number of operations to replay." in
  Arg.(value & opt (some int) None & info [ "n"; "nb-operations" ] ~doc)

let main_term =
  Term.(
    const main
    $ Fmt_cli.style_renderer ()
    $ Logs_cli.level ()
    $ commit_data_file
    $ btree
    $ nofalse
    $ n_op)

let () =
  let man =
    [
      `S "DESCRIPTION";
      `P
        "Benchmarks for index operations. Requires traces of operations \
         (/data/ioana/trace_index.repr) and initial index store (/data/ioana/index_BL.tar.gz)";
    ]
  in
  Random.init 42;
  let info = Term.info ~man ~doc:"Benchmarks for index operations" "bench-index" in
  Term.exit @@ Term.eval (main_term, info)
