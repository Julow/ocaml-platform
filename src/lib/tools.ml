open! Import
open Astring
open Bos
module OV = Ocaml_version
open Result.Syntax

type tool = { name : string; pure_binary : bool; version : string option }
(* FIXME: Once we use the opam library, let's use something like
   [OpamPackage.Name.t] for the type of [name] and something like ... for the
   type of [compiler_constr].*)

let parse_constraints s =
  let open Angstrom in
  let is_whitespace = function
    | '\x20' | '\x0a' | '\x0d' | '\x09' -> true
    | _ -> false
  in
  let whitespace = take_while is_whitespace in
  let whitespaced p = whitespace *> p <* whitespace in
  let quoted p = whitespaced @@ (char '"' *> p) <* char '"' in
  let bracketed p = whitespaced @@ (char '{' *> p) <* char '}' in
  let quoted_ocaml = quoted @@ string "ocaml" in
  let quoted_version =
    quoted @@ take_till (( = ) '"') >>| fun version_string ->
    OV.of_string_exn version_string
  in
  let is_comparator = function '<' | '>' | '=' -> true | _ -> false in
  let comparator =
    whitespaced @@ peek_char >>= function
    | Some c ->
        if is_comparator c then
          take_till is_whitespace >>= function
          | ("<" | "<=" | ">" | ">=" | "=") as e -> return (Some e)
          | _ -> fail "not a comparator"
        else return None
    | None -> return None
  in
  let constraint_ = both comparator quoted_version in
  let constraints = sep_by (whitespaced @@ char '&') constraint_ in
  let finally = quoted_ocaml *> bracketed constraints <* end_of_input in
  match parse_string ~consume:Consume.All finally s with
  | Ok a -> Ok a
  | Error m -> Error (`Msg m)

let verify_constraint version constraint_ =
  match constraint_ with
  | Some "<=", constraint_version -> OV.compare version constraint_version < 1
  | Some "<", constraint_version -> OV.compare version constraint_version < 0
  | Some ">=", constraint_version -> OV.compare version constraint_version > -1
  | Some ">", constraint_version -> OV.compare version constraint_version > 0
  | _ -> failwith "impossible"

let verify_constraints version constraints =
  List.for_all (verify_constraint version) constraints

let best_available_version sandbox name =
  Opam.opam_run_s Cmd.(v "show" % "-f" % "available-versions" % name)
  >>| fun versions ->
  let version =
    String.cuts ~sep:"  " versions
    |> List.rev
    |> List.find (fun version ->
           let ocaml_depends =
             Opam.opam_run_l
               Cmd.(v "show" % "-f" % "depends:" % (name ^ "." ^ version))
             >>| List.find_opt (String.is_prefix ~affix:"\"ocaml\"")
           in
           match ocaml_depends with
           | Ok (Some ocaml_constraint) ->
               let result =
                 parse_constraints ocaml_constraint >>| fun constraints ->
                 verify_constraints
                   (Sandbox_switch.ocaml_version sandbox)
                   constraints
               in
               Result.value ~default:false result
           | Ok None -> true
           | _ -> false)
  in
  version

let binary_name_of_tool sandbox tool =
  (match tool.version with
  | Some ver -> Ok ver
  | None -> best_available_version sandbox tool.name)
  >>| fun ver ->
  Binary_package.binary_name sandbox ~name:tool.name ~ver
    ~pure_binary:tool.pure_binary

let make_binary_package sandbox repo bname tool =
  if Binary_package.has_binary_package repo bname then Ok ()
  else
    Sandbox_switch.install sandbox ~pkg:(tool.name, tool.version) >>= fun () ->
    Binary_package.make_binary_package sandbox repo bname ~name:tool.name

let install_binary_tool sandbox repo tool =
  binary_name_of_tool sandbox tool >>= fun bname ->
  make_binary_package sandbox repo bname tool >>= fun () ->
  Repo.with_repo_enabled (Binary_repo.repo repo) (fun () ->
      Opam.opam_run Cmd.(v "install" % Binary_package.name_to_string bname))

let install _ tools =
  let binary_repo_path =
    Fpath.(Opam.root / "plugins" / "ocaml-platform" / "cache")
  in
  Opam.opam_run_s Cmd.(v "show" % "ocaml" % "-f" % "version" % "--normalise")
  >>= fun ovraw ->
  OV.of_string ovraw >>= fun ocaml_version ->
  Binary_repo.init binary_repo_path >>= fun repo ->
  Sandbox_switch.with_sandbox_switch ~ocaml_version (fun sandbox ->
      Result.fold_list
        (fun () tool -> install_binary_tool sandbox repo tool)
        tools ())

let find_ocamlformat_version () =
  match OS.File.read_lines (Fpath.v ".ocamlformat") with
  | Ok f ->
      List.filter_map
        (fun s ->
          Astring.String.cut ~sep:"=" s |> function
          | Some (a, b) -> Some (String.trim a, String.trim b)
          | None -> None)
        f
      |> List.assoc_opt "version"
  | Error (`Msg _) -> None

(** TODO: This should be moved to an other module to for example do automatic
    recognizing of ocamlformat's version. *)
let platform () =
  [
    { name = "dune"; pure_binary = true; version = None };
    { name = "dune-release"; pure_binary = false; version = None };
    { name = "merlin"; pure_binary = false; version = None };
    { name = "ocaml-lsp-server"; pure_binary = false; version = None };
    { name = "odoc"; pure_binary = false; version = None };
    {
      name = "ocamlformat";
      pure_binary = false;
      version = find_ocamlformat_version ();
    };
  ]
