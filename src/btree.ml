include Btree_intf
module Make (InKey : Input.Key) (InValue : Input.Value) (Size : Input.Size) =
  Ext.Make_ext (InKey) (InValue) (Size)
