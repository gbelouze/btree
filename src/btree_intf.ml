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

module type S = Ext.S

module type MAKER = functor (InKey : Input.Key) (InValue : Input.Value) (Size : Input.Size) ->
  S with type key = InKey.t and type value = InValue.t

module Input = Input

module Index = struct
  module type S = Btree_index.S

  module Make = Btree_index.Make
  module Stats = Btree_index.Stats
end

module type Btree = sig
  module Private = Private

  module type S = S

  module Input = Input

  module Make : MAKER

  module Index = Index
end
