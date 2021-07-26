  (*
     The volatile mechanism should be reworked. 2 problematic cases:
     - `iter` releases its intermediate nodes while iterating on it
     - Calling `mem` during `iter` releases everything at the end of mem

     A solution would be to change the signature to [val unpin t -> key -> unit], so that
     the cache can keep a [key -> int * t] where [unpin] would decrease the [int] and [0]
     would trigger a collection.

     Another solution would be to use a weakmap somehow.

     I also think that the Lru pages should be pinned too, to avoid the salvaging of pages
     still in use.
   *)


module type CALIFORNIA = sig
  (* You can (almost) never leave the california cache *)

  type key

  type value

  type t

  val v :
    flush:(key -> value -> unit) ->
    load:(?available:value -> key -> value) ->
    (* the [value] argument can be useful to reutilise memory precedently allocated to some other value *)
    filter:(value -> [ `California | `Lru | `Volatile ]) ->
    int ->
    int ->
    t

  val find : t -> key -> value

  val reload : t -> key -> unit

  val update_filter : t -> filter:(value -> [ `California | `Lru | `Volatile ]) -> unit

  val release : t -> unit

  val deallocate : t -> key -> unit

  val clear : t -> unit

  val flush : t -> unit
end

module type MAKER = functor (K : Hashtbl.HashedType) (V : Lru.Weighted) ->
  CALIFORNIA with type key = K.t and type value = V.t

module type Cache = sig
  module Make : MAKER
end
