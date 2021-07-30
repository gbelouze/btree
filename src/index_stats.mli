type t = {
  mutable bytes_read : int;
  mutable nb_reads : int;
  mutable bytes_written : int;
  mutable nb_writes : int;
  mutable nb_replace : int;
}
(** The type for stats for an index I.

    - [bytes_read] is the number of bytes read from disk;
    - [nb_reads] is the number of reads from disk;
    - [bytes_written] is the number of bytes written to disk;
    - [nb_writes] is the number of writes to disk;
    - [nb_replace] is the number of calls to [I.replace]. *)

val get : unit -> t

val reset_stats : unit -> unit

val add_read : int -> unit

val add_write : int -> unit

val incr_nb_replace : unit -> unit
