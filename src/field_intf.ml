module type FIELD = sig
  type t [@@deriving repr]

  type convert

  val set : marker:(unit -> unit) -> bytes -> off:int -> t -> unit
  (* marker is a function to mark the bytes as dirty *)

  val get : bytes -> off:int -> t

  val size : int

  val to_t : convert -> t

  val from_t : t -> convert

  val pp : t Fmt.t

  val pp_raw : Format.formatter -> bytes -> off:int -> unit
end

type kind = Leaf | Node of int [@@deriving repr]

module type INT = FIELD with type convert := int

module type BOOL = FIELD with type convert := bool

module type STRING = FIELD with type convert := string

module type KIND = sig
  include FIELD with type convert := kind

  (* "depth" here refers to the depth from the leaf upward to the root, that's unusual. Maybe name
     this "inverse_depth" or something else? *)
  val of_depth : int -> t (* kind of a node from its distance to the leaves *)

  val to_depth : t -> int (* distance to the leaves of a node, from its kind *)
end

module type SIZE = sig
  val size : int
end

module type COMMON = sig
  module Version : INT

  module Magic : STRING

  module Address : INT

  module Pointer : INT

  module Flag : BOOL

  module Kind : KIND
end

module type Field = sig
  type nonrec kind = kind [@@deriving repr]

  module type INT = INT

  module type BOOL = BOOL

  module type COMMON = COMMON

  module MakeInt : functor (Size : SIZE) -> INT

  module MakeBool : functor (Size : SIZE) -> BOOL

  module MakeString : functor (Size : SIZE) -> STRING

  module MakeCommon : functor (Params : Params.S) -> COMMON
end
