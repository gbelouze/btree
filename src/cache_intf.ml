module type CALIFORNIA = sig
  (* You can (almost) never leave the california cache *)

  type key

  type value

  type t

  (* Need documentation on the parameters! *)
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
