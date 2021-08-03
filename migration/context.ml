let ( // ) a b = a ^ "/" ^ b

module Index = struct
  open Encoding
  module Index = Index_unix.Make (Key) (Val) (Index.Cache.Unbounded)
  include Index

  let replace t key value = replace t key value

  (* remove ?overcommit optional argument from the signature *)

  let flush t = flush t (* remove optional arguments from signature *)

  let cache = Index.empty_cache ()

  let v root = Index.v ~cache ~readonly:false ~fresh:false ~log_size:500_000 root

  let close t = Index.close t
end

module MyBtree = struct
  open Encoding

  let version = 2

  module Size = struct
    include Btree.Private.Default.Size

    let version = version

    let debug = false
  end

  module MyBtree =
    Btree.Make
      (struct
        include Key

        let decode s = decode s 0
      end)
      (struct
        include Val

        let decode s = decode s 0
      end)
      (Size)

  include MyBtree

  let replace = add

  let migrate root from =
    let module IO = Index_unix.Private.IO in
    let file = from // "data" in
    assert (Sys.file_exists file);
    let store = IO.v ~fresh:false ~generation:Optint.Int63.zero ~fan_size:Optint.Int63.zero file in
    let entry_size = Key.encoded_size + Val.encoded_size in
    let header_size = IO.size_header store in
    let fd = Unix.(openfile file [ O_RDONLY ] 0o655) in
    Unix.(lseek fd header_size SEEK_SET) |> ignore;

    let buff = Bytes.create entry_size in
    let oracle () =
      let read_sz = Unix.read fd buff 0 entry_size in
      assert (read_sz = entry_size);
      Bytes.sub_string buff 0 entry_size
    in

    let out = from // "sorted_data" in
    (if not (Sys.file_exists out) then
     let module StringValue = (val Oracle.stringv ~encode_sz:entry_size) in
     let module Sorter = Oracle.Make (StringValue) (Oracle.Default) in
     let n = (IO.offset store |> Optint.Int63.to_int) / entry_size in
     Sorter.sort ~with_prog:true ~oracle ~out n);
    Unix.close fd;

    let fd = Unix.(openfile out [ O_RDONLY ] 0o655) in
    let buff = Bytes.create (entry_size * Size.fanout * 2) in
    let read n =
      let read_sz = Unix.read fd buff 0 (n * entry_size) in
      assert (read_sz = n * entry_size);
      Bytes.sub_string buff 0 (n * entry_size)
    in
    let total = fd |> Unix.fstat |> fun x -> x.st_size / entry_size in
    let t = init ~root total ~read in
    Unix.close fd;
    t

  let v root from =
    let module Stats = Btree.Private.Stats in
    Stats.Btree.setup_log [ "add"; "find"; "mem" ];
    Stats.Store.setup_log [ "io read"; "io write" ];

    let tree =
      if Sys.file_exists (Fmt.str "%s/b.tree" root) then create root else migrate root from
    in
    tree

  let close _t = ()
end

let nop_fmt = Format.make_formatter (fun _ _ _ -> ()) (fun () -> ())

let app_reporter =
  let counter = Mtime_clock.counter () in
  let report src level ~over k msgf =
    let dt = Mtime_clock.count counter |> Mtime.Span.to_ms in
    let k _ =
      over ();
      k ()
    in
    let print header tags k fmt =
      let open Btree.Private.Tag in
      let kind = match tags with None -> None | Some tags -> Logs.Tag.find kind_tag tags in
      let formatter = match kind with Some Stats -> nop_fmt | _ -> Fmt.stdout in
      Fmt.kpf k formatter
        ("[%+04.0fms] %a %a @[" ^^ fmt ^^ "@]@.")
        dt Logs_fmt.pp_header (level, header)
        Fmt.(styled `Magenta string)
        (Logs.Src.name src)
    in
    msgf @@ fun ?header ?tags fmt -> print header tags k fmt
  in
  { Logs.report }

let combine reporter =
  let report src level ~over k msgf =
    let v = app_reporter.Logs.report src level ~over:(fun () -> ()) k msgf in
    reporter.Logs.report src level ~over (fun () -> v) msgf
  in
  { Logs.report }

let reporter logppf statsppf =
  let counter = Mtime_clock.counter () in
  let report _src level ~over k msgf =
    let dt = Mtime_clock.count counter |> Mtime.Span.to_ms in
    let k _ =
      over ();
      k ()
    in
    let print header tags k fmt =
      let open Btree.Private.Tag in
      let kind = match tags with None -> None | Some tags -> Logs.Tag.find kind_tag tags in
      match kind with
      | Some Stats -> Fmt.kpf k statsppf ("%f;" ^^ fmt ^^ "@.") dt
      | _ ->
          Fmt.kpf k logppf
            ("[%+04.0fms] %a @[" ^^ fmt ^^ "@]@.")
            dt Logs_fmt.pp_header (level, header)
    in
    msgf @@ fun ?header ?tags fmt -> print header tags k fmt
  in
  { Logs.report } |> combine

let setup_btreelog style_renderer level root =
  let logchan = open_out_gen [ Open_append; Open_creat; Open_trunc ] 0o600 (root // "b.log") in
  let logppf = Format.formatter_of_out_channel logchan in
  let statschan =
    open_out_gen [ Open_append; Open_creat; Open_trunc ] 0o600 (root // "stats.log")
  in
  let statppf = Format.formatter_of_out_channel statschan in

  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (reporter logppf statppf)

let setup_indexlog style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter app_reporter
