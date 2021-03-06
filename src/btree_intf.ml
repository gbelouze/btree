(*
 * Copyright (c) 2021 Tarides <contact@tarides.com>
 * Copyright (c) 2021 Gabriel Belouze <gabriel.belouze@ens.psl.eu>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

module Private = struct
  module Utils = Utils
  module Stats = Stats
  module Index_stats = Index_stats
  module Tag = Log.Tag
  module Default = Input.Default
  module Input = Input
  module Data = Data
  module Syscalls = Syscalls
end

module type S = sig
  type key

  type value

  type t

  type cache

  val empty_cache : unit -> cache
  (** [empty_cache ()] returns a fresh, empty cache. *)

  val create : ?cache:cache -> ?record:string -> string -> t
  (** [create ?cache ?record root] creates a btree storage in directory [root]. If no [cache] is
      specified each call to create opens a fresh instance. If [record] is specified then a trace is
      recorded in file [record]. *)

  val replay : string -> ?prog:[ `None | `Single | `Multiple ] -> t -> unit
  (** [replay ?prog path t] replays the operations stored in file [path]. *)

  val init : root:string -> int -> read:(int -> string) -> t
  (** [init ~root n ~read] performs a batch initialisation. [read] is an iterator-like function :
      [read n] reads the next [n] bindings and returns them in a single string chunk which is the
      concatenation of each [key ^ value]. [init] is (much) faster than adding each bindings one by
      one. It assumes that the bindings are sorted. *)

  val reconstruct : string -> t
  (** [reconstruct root] is like [create root] but assumes that the b.tree file in directory [root]
      is corrupted (nodes are possibly corrupted but the leaves are not impacted) and repairs it
      first. *)

  val add : t -> key -> value -> unit

  val remove : t -> key -> unit

  val find : t -> key -> value

  val mem : t -> key -> bool

  val clear : t -> unit

  val close : t -> unit

  val flush : t -> unit

  val iter : (key -> value -> unit) -> t -> unit

  val iteri : (int -> key -> value -> unit) -> t -> unit

  val length : t -> int
  (** [length t] is the number of bindings in [t] *)

  val pp : t Fmt.t

  val snapshot : ?depth:int -> t -> unit
  (** For every node/leaf in [t] which are at least [depth] away from the leaves,
      [snapshot ~depth t], write in a file its rep as given by their corresponding pp function. *)

  module Private : sig
    module Params : Params.S

    module Common : Field.COMMON

    module Entry : Data.Entry with type input_key = key and type input_value = value

    module Key = Entry.Key
    module Value = Entry.Value

    module Store : Store.S with module Common = Field.MakeCommon(Params)

    module Page = Store.Page

    module Leaf :
      Leaf.S
        with type value = Value.t
         and type key = Key.t
         and type store := Store.t
         and type address := Store.address

    module Node :
      Node.S
        with type key = Key.t
         and type address := Store.address
         and type store := Store.t
         and type kind := Field.kind

    val dir : t -> string

    val store : t -> Store.t

    val root : t -> int

    val go_to_leaf : t -> key -> int list

    val cache_size : t -> int

    val pp : t -> int Fmt.t
  end
end

module type MAKER = functor (InKey : Input.Key) (InValue : Input.Value) (Size : Input.Size) ->
  S with type key = InKey.t and type value = InValue.t

module Input = Input

module type Btree = sig
  module Private = Private

  module type S = S

  module Input = Input

  module Make : MAKER
end
