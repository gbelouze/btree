include Field_intf

type kind = _kind [@@deriving repr]

module MakeInt (Size : SIZE) = struct
  type t = int [@@deriving repr]

  let size = Size.size

  let get, set =
    match size with
    | 1 -> Bytes.((fun b ~off -> get_uint8 b off), fun b ~off -> set_uint8 b off)
    | 2 -> Bytes.((fun b ~off -> get_uint16_be b off), fun b ~off -> set_uint16_be b off)
    | 4 ->
        Bytes.
          ( (fun b ~off -> get_int32_be b off |> Int32.to_int),
            fun b ~off t -> t |> Int32.of_int |> set_int32_be b off )
    | 8 ->
        Bytes.
          ( (fun b ~off -> get_int64_be b off |> Int64.to_int),
            fun b ~off t -> t |> Int64.of_int |> set_int64_be b off )
    | n -> failwith (Fmt.str "Unsupported int length %i" n)

  let set ~marker buff ~off t =
    marker ();
    set buff ~off t

  let from_t = Fun.id

  let to_t = Fun.id

  let pp = Fmt.int

  let pp_raw ppf buff ~off =
    Bytes.sub_string buff off size |> Hex.of_string |> Hex.show |> Fmt.string ppf
end

module MakeBool (Size : SIZE) = struct
  type t = bool [@@deriving repr]

  let size = Size.size

  let set ~marker b ~off t =
    marker ();
    Bytes.set b off (if t then '\255' else '\254')

  let get b ~off =
    match Bytes.get b off with
    | '\255' -> true
    | '\254' -> false
    | c -> Fmt.str "Unknown bool with code %i" (Char.code c) |> failwith

  let from_t = Fun.id

  let to_t = Fun.id

  let pp = Fmt.bool

  let pp_raw ppf buff ~off =
    Bytes.sub_string buff off size |> Hex.of_string |> Hex.show |> Fmt.string ppf
end

module MakeString (Size : SIZE) = struct
  type t = string [@@deriving repr]

  let size = Size.size

  let set ~marker b ~off t =
    assert (String.length t = size);
    marker ();
    Bytes.blit_string t 0 b off size

  let get b ~off = Bytes.sub_string b off size

  let from_t = Fun.id

  let to_t = Fun.id

  let pp = Fmt.string

  let pp_raw ppf buff ~off =
    Bytes.sub_string buff off size |> Hex.of_string |> Hex.show |> Fmt.string ppf
end

module MakeCommon (Params : Params.S) : COMMON = struct
  module Version = MakeInt (struct
    let size = Params.version_sz
  end)

  module Magic = MakeString (struct
    let size = Params.magic_sz
  end)

  module Address = MakeInt (struct
    let size = Params.page_address_sz
  end)

  module Pointer = MakeInt (struct
    let minimal_size = Params.page_sz - 1 |> Fmt.str "%x" |> String.length |> fun x -> (x + 1) / 2

    let size = [ 1; 2; 4; 8 ] |> List.filter (( <= ) minimal_size) |> List.hd
  end)

  module Flag = MakeBool (struct
    let size = Params.flag
  end)

  module Kind = struct
    type t = kind [@@deriving repr]

    let size = Params.tree_height_sz

    let of_depth n = if n = 0 then Leaf else Node n

    let to_depth t = match t with Leaf -> 0 | Node n -> n

    module AsInt = MakeInt (struct
      let size = size
    end)

    let of_int i = if i = 0 then Leaf else Node i
    (* this could change if we added more variants to [kind] *)

    let to_int t = match t with Leaf -> 0 | Node n -> n
    (* this could change if we added more variants to [kind] *)

    let from_t = Fun.id

    let to_t = Fun.id

    let get b ~off = AsInt.get b ~off |> of_int

    let set ~marker b ~off t = t |> to_int |> AsInt.set ~marker b ~off

    let pp = Repr.pp t

    let pp_raw ppf buff ~off =
      Bytes.sub_string buff off size |> Hex.of_string |> Hex.show |> Fmt.string ppf
  end
end
