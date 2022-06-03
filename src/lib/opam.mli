open Bos_setup
open Import

module GlobalOpts : sig
  type t = {
    root : Fpath.t;
    switch : string option;  (** Whether to pass the [--switch] option. *)
    env : string String.map option;
        (** Environment to use when calling commands. *)
  }

  val v : root:Fpath.t -> ?switch:string -> ?env:string String.map -> unit -> t
  val default : t
end

module Config : sig
  module Var : sig
    val get : GlobalOpts.t -> string -> (string, 'e) Result.or_msg
    val get_opt : GlobalOpts.t -> string -> (string option, 'e) Result.or_msg

    val set :
      GlobalOpts.t ->
      global:bool ->
      string ->
      string ->
      (unit, 'e) Result.or_msg

    val unset :
      GlobalOpts.t -> global:bool -> string -> (unit, 'e) Result.or_msg
  end
end

module Switch : sig
  val list : GlobalOpts.t -> (string list, [> Rresult.R.msg ]) result

  val create :
    ocaml_version:string option ->
    GlobalOpts.t ->
    string ->
    (unit, [> `Msg of string ]) result
  (** When [ocaml_version] is [None], create a switch with no compiler
      installed. *)

  val remove : GlobalOpts.t -> string -> (string, [> `Msg of string ]) result
end

module Repository : sig
  val add :
    GlobalOpts.t -> url:string -> string -> (unit, [> `Msg of string ]) result

  val remove : GlobalOpts.t -> string -> (unit, [> `Msg of string ]) result
end

module Show : sig
  val list_files :
    GlobalOpts.t -> string -> (string list, [> `Msg of string ]) result

  val available_versions :
    GlobalOpts.t -> string -> (string list, [> `Msg of string ]) result

  val installed_version :
    GlobalOpts.t -> string -> (string option, [> `Msg of string ]) result

  val installed_versions :
    GlobalOpts.t ->
    string list ->
    ((string * string option) list, 'a) Result.or_msg

  val depends :
    GlobalOpts.t -> string -> (string list, [> `Msg of string ]) result

  val version :
    GlobalOpts.t -> string -> (string list, [> `Msg of string ]) result
end

val install : GlobalOpts.t -> string list -> (unit, [> `Msg of string ]) result
(** [install atoms] installs the [atoms] into the current local switch. If opam
    has not been initialised, or if their is no local switch this function will
    also create those too. *)

val remove : GlobalOpts.t -> string list -> (unit, [> `Msg of string ]) result
(** [remove atoms] removes the [atoms] from the current local switch. Returns
    the list of package removed. *)

val update : GlobalOpts.t -> string list -> (unit, [> `Msg of string ]) result
(** [update names] updates the repositories by their [names] that the current
    local switch has set. *)

val upgrade : GlobalOpts.t -> string list -> (unit, [> `Msg of string ]) result
(** [upgrade atoms] will try to upgrade the packages whilst keeping [atoms]
    installed. *)

val check_init : unit -> (unit, [> `Msg of string ]) result
