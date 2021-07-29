module type S = sig
  val fanout : int
  (** The fanout characterizes the number of bindings in a vertex, which is between fanout and 2 *
      fanout for all vertexes except for the root of the btree. *)

  val version : int
  (** The version of the btree. *)

  val tree_height_sz : int
  (** The height of the tree. *)

  val page_sz : int
  (** The page size (in B). It should be the max between (max_key * (key_sz + page_address_sz)) and
      (max_key * (key_sz + value_sz)). *)

  val cache_sz : int
  (** The cache size (in MB). *)

  val key_sz : int
  (** Key sizes.*)

  val value_sz : int
  (** Value sizes.*)

  val max_key : int
  (** The maximum number of keys per page (usually 2 * fanout + 1). *)

  val max_key_sz : int
  (** The size of the max_key. *)

  val version_sz : int
  (** Version size (in B). *)

  val btree_magic : string
  (** Magic string written on disk to mark the header of a btree file. *)

  val page_magic : string
  (** Magic string written on disk to mark the header of a page. *)

  val magic_sz : int
  (** Magic size (in B). *)

  val key_repr_sz : int
  (** The size of key_sz (in B). Useful for variable length keys or for the (not yet implemented)
      suffix truncation of keys. *)

  val page_address_sz : int
  (** The size of a page address (in B). *)

  val offset_sz : int
  (** Offset size (in B). *)

  val debug : bool
  (** Specifies if the run is in debug mode which checks sortedness after key insertion and
      deletion. *)

  module Debug : sig
    val random_failure : bool
  end
end

module Constant = struct
  let version_sz = 1

  let btree_magic = "TREE"

  let page_magic = "PAGE"

  let tree_height_sz = 2

  let page_address_sz = 4

  let offset_sz = 4

  let flag = 1
end

module Make : functor (I : Input.Size) (Key : Input.Key) (Value : Input.Value) -> S =
functor
  (I : Input.Size)
  (Key : Input.Key)
  (Value : Input.Value)
  ->
  struct
    include I
    include Constant

    let value_sz = Value.encoded_size

    let key_sz = Key.encoded_size

    let max_key = (2 * fanout) + 1

    let max_key_sz = max_key |> Utils.b256size

    let magic_sz = String.(max (length btree_magic) (length page_magic))

    let key_repr_sz = key_sz |> Utils.b256size

    let () =
      if 1 lsl (4 * offset_sz) < page_sz then failwith "Pages are too large to be fully addressable"
  end
