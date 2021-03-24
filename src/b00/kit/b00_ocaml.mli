(*---------------------------------------------------------------------------
   Copyright (c) 2019 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

(** B00 [ocaml] support.

    This module exposes a first low-level abtraction layer over the
    OCaml toolchain. *)

open B00_std
open B00

(** Tools. *)
module Tool : sig

  (** {1:comp Compilers} *)

  val comp_env_vars : Tool.env_vars
  (** [comp_env_vars] are environment variables that influence the
      OCaml toolchain outputs. *)

  val ocamlc : Tool.t
  (** [ocamlc] is the [ocamlc] tool. *)

  val ocamlopt : Tool.t
  (** [ocamlopt] is the [ocamlopt] tool. *)

  val ocamldep : Tool.t
  (** [ocamldep] is the [ocamldep] tool. *)

  val ocamlmklib : Tool.t
  (** [ocamlmklib] is the [ocamlmklib] tool. *)

  val ocamlobjinfo : Tool.t
  (** [ocamlobjinfo] is the [ocamlobjinfo] tool. *)

  (** {1:top Toplevels} *)

  val top_env_vars : Tool.env_vars
  (** [top_env_vars] are environment variables that influence the
      OCaml toplevel. *)

  val ocaml : Tool.t
  (** [ocaml] is the [ocaml] tool. *)

  val ocamlnat : Tool.t
  (** [ocamlnat] is the [ocamlnat] tool. *)
end

(** Toolchain configuration.

    This module provides access to the OCaml toolchain configuration
    as output by [ocaml{c,opt} -config]. *)
module Conf : sig

  (** {1:conf Configuration} *)

  type code = [ `Byte | `Native ]
  (** The type for code generated by the OCaml compiler. Either
      bytecode or native-code. *)

  type t
  (** The type for the OCaml toolchain configuration. *)

  val of_string : ?file:Fpath.t -> string -> (t, string) result
  (** [of_string ~file data] parses toolchain configuration from [data]
      as output by the compiler's [-config] option assuming it was read
      from file [file] (defaults to {!B00_std.Fpath.dash}). *)

  val write : B00.Memo.t -> comp:B00.Tool.t -> o:Fpath.t -> unit
  (** [write m ~o] writes the toolchain configuration to [o] by
      running [comp] with [-config]. *)

  val read : B00.Memo.t -> Fpath.t -> t Fut.t
  (** [read m file] reads a toolchain configuration from [file]. *)

  (** {1:fields Fields} *)

  val find : string -> t -> string option
  (** [find f c] looks up the field [f] in configuration [c].
      See [ocamlc -config] for the list of fields. *)

  val version : t -> int * int * int * string option
  (** [version c] is the compiler version string
      ["major.minor[.patchlevel][+additional-info]"] parsed
      using
      [(major, minor, patch, additional-info)]. If [patch-level]
      is absent it is turned into a [0]. *)

  val where : t -> Fpath.t
  (** [where c] is the location of OCaml's library directory. *)

  val asm_ext : t -> Fpath.ext
  (** [asm_ext] is the file extension for assembly files. *)

  val dll_ext : t -> Fpath.ext
  (** [dll_ext] is the file extension for C dynamic libraries. *)

  val exe_ext : t -> Fpath.ext
  (** [ext_ext] is the file extension for executable binaries. *)

  val lib_ext : t -> Fpath.ext
  (** [ext_lib] is the file extension for C static libraries. *)

  val obj_ext : t -> Fpath.ext
  (** [obj_ext] is the file extension for C object files. *)

  val has_dynlink : t -> bool
  (** [has_dynlink] determines whether the platform supports
      dynamic linking. *)

  (** {1:convert Converting} *)

  val to_string_map : t -> string String.Map.t
  (** [to_string_map c] are the fields of [c] as a string map. *)

  val of_string_map : string String.Map.t -> (t, string) result
  (** [of_string_map m] is a configuration from string map [m].
      [m] needs at least on key for each parsed field above otherwise
      the function errors. *)
end

(** Module names, sources and digested references. *)
module Mod : sig

  (** Module names. *)
  module Name : sig

    (** {1:name Module names} *)

    type t = string
    (** The type for unqualified, capitalized, module names. *)

    val v : string -> t
    (** [v n] is a module name for [n], the result is capitalized. *)

    val of_filename : Fpath.t -> t
    (** [of_filename f] is the basename of [f], without extension, capitalized.
        This assumes the basename of [f] follows the OCaml file naming
        convention mandated by the toolchain. If you know that may not
        be the case use {!of_mangled_filename}. *)

    val equal : t -> t -> bool
    (** [equal n0 n1] is [true] iff [n0] and [n1] are the same module name. *)

    val compare : t -> t -> int
    (** [comare n0 n1] is a total order on module names compatiable with
        {!equal}. *)

    val pp : t Fmt.t
    (** [pp] formats a module name. *)

    (** Module name sets. *)
    module Set = String.Set

    (** Module name maps. *)
    module Map = String.Map

    (** {1:mangled Filename mangling} *)

    val of_mangled_filename : string -> t
    (** [of_mangled_filename s] is module name obtained by mangling
        the filename of [s] as follows:

        {ol
        {- Remove any trailing [.ml] or [.mli].}
        {- Map any dash [-] (0x2D) or dot [.] (0x2E) to an underscore
          [_] (0x5F).}
        {- Map any byte not allowed in OCaml compilation unit names to its two
          digits capital hexadecimal encoding.}
        {- If the result does not start with an US-ASCII letter, prefix
          the unit name with ['M'].}
        {- Capitalize the first letter.}}

        The transformation is consistent with {!of_filename} on files
        that follows the OCaml toolchain convention. However the
        transformation is not injective. Here are a few examples:

{v
           filename   Module name
 ----------------------------------------
    publish-website   Publish_website
    publish_website   Publish_website
     import-data.ml   Import_data
 import-data.xml.ml   Import_data_xml
 import-data.script   Import_data_script
          mix+match   Mix2Bmatch
        _release.ml   M_release
v} *)
  end

  (** Module digested references.

      {b TODO.} Use that in [B00_odoc]. *)
  module Ref : sig

    (** {1:modrefs Module references} *)

    type t
    (** The type for module references as found in compilation objects.
        This is a module name and a digest of its interface. *)

    val v : string -> Digest.t -> t
    (** [v n d] is a module reference with name [n] and digest [d]. *)

    val name : t -> Name.t
    (** [name m] is the capitalized module name of module reference [m]. *)

    val digest : t -> Digest.t
    (** [digest m] is the interface digest of module reference [m]. *)

    val equal : t -> t -> bool
    (** [equal m m'] is [true] iff [m] and [m'] are the same reference. *)

    val compare : t -> t -> int
    (** [compare m m'] is a total order on module references. *)

    val pp : t Fmt.t
    (** [pp] formats a module reference. *)

    (** Module reference sets. *)
    module Set : sig
      include Set.S with type elt = t

      val pp : ?sep:unit Fmt.t -> elt Fmt.t -> t Fmt.t
      (** [pp ~sep pp_elt ppf rs] formats the elements of [rs] on [ppf].
          Each element is formatted with [pp_elt] and elements are
          separated by [~sep] (defaults to {!Fmt.cut}). If the set is
          empty leaves [ppf] untouched. *)

      val dump : t Fmt.t
      (** [dump ppf ss] prints an unspecified representation of [ss] on
          [ppf]. *)
    end

    (** Module reference maps. *)
    module Map : sig
      include Map.S with type key = t

      val dom : 'a t -> Set.t
      (** [dom m] is the domain of [m]. *)

      val of_list : (key * 'a) list -> 'a t
      (** [of_list bs] is [List.fold_left (fun m (k, v) -> add k v m) empty
          bs]. *)

      (** {1:add Additional adds} *)

      val add_to_list : key -> 'a -> 'a list t -> 'a list t
      (** [add k v m] is [m] with [k] mapping to [l] such that [l] is
          [v :: find k m] if [k] was bound in [m] and [[v]] otherwise. *)

      val add_to_set :
        (module B00_std.Stdlib_set.S with type elt = 'a and type t = 'set) ->
        key -> 'a -> 'set t -> 'set t
      (** [add (module S) k v m] is [m] with [k] mapping to [s] such that [s] is
          [S.add v (find k m)] if [k] was bound in [m] and [S.singleton [v]]
          otherwise. *)

      (** {1:fmt Formatting} *)

      val pp : ?sep:unit Fmt.t -> (key * 'a) Fmt.t -> 'a t Fmt.t
      (** [pp ~sep pp_binding ppf m] formats the bindings of [m] on
          [ppf]. Each binding is formatted with [pp_binding] and
          bindings are separated by [sep] (defaults to
          {!Format.pp_print_cut}). If the map is empty leaves [ppf]
          untouched. *)

      val dump : 'a Fmt.t -> 'a t Fmt.t
      (** [dump pp_v ppf m] prints an unspecified representation of [m] on
          [ppf] using [pp_v] to print the map codomain elements. *)
    end
  end

  (** Module sources.

      A small abstraction to represent OCaml modules to compile
      and find out about source dependencies via {!Tool.ocamldep}.

      {b XXX.} This abstraction supports having [.ml] and [.mli]
      in different directories. The
      {{:https://github.com/ocaml/ocaml/issues/9717}current reality though
      prevents us from that}. *)
  module Src : sig

    (** {1:mods Modules} *)

    (** Source dependencies.

        As found by {!Tool.ocamldep}. *)
    module Deps : sig
      val write :
        ?src_root:Fpath.t -> Memo.t -> srcs:Fpath.t list -> o:Fpath.t -> unit
      (** [write m ~src_root ~srcs ~o] writes the module dependencies of each
          file in [srcs] in file [o]. If [src_root] if specified it is used
          as the [cwd] for the operation and assumed to be a prefix of every
          file in [srcs], this allows the output not to the depend on absolute
          paths.

          {b UPSTREAM FIXME.} We don't actually do what is mentioned
          about [src_root]. The problem is that the path of parse errors
          end up being wrongly reported. It would be nice to add an
          option for output prefix trimming to the tool and/or control
          on the whole toolchain for how errors are reported. This means
          that for now we cannot cache these operations across
          machines. *)

      val read :
        ?src_root:Fpath.t -> Memo.t -> Fpath.t -> Name.Set.t Fpath.Map.t Fut.t
        (** [read ~src_root file] reads dependencies produced by {!write}
            as a map from absolute file paths to their dependencies.
            Relative file paths are made absolute relative to {!src_root}
            if specified. *)
    end

    type t
    (** The type for OCaml module sources, represents a module to compile
        in a build directory. *)

    val v :
      mod_name:Name.t -> opaque:bool -> mli:Fpath.t option ->
      mli_deps:Name.Set.t -> ml:Fpath.t option -> ml_deps:Name.Set.t ->
      build_dir:Fpath.t -> t
    (** [v ~mod_name ~opaque ~mli ~mli_deps ~ml ~ml_deps ~build_dir]
        is a module whose name is [name], interface file is [mli] (if
        any), interface file module dependencies is [mli_deps],
        implementation is [ml] (if any) and implementation file module
        dependencies [ml_deps].  The module is expected to be built in
        [build_dir]. For [opaque] see {!opaque}. *)

    val mod_name : t -> Name.t
    (** [mod_name m] is [m]'s name. *)

    val opaque : t -> bool
    (** [opaque m] indicates whether the module should be treated as
        opaque for compilation. See the [-opaque] option in the OCaml
        manual. *)

    val mli : t -> Fpath.t option
    (** [mli m] is [m]'s interface file (if any). *)

    val mli_deps : t -> Name.Set.t
    (** [mli_deps m] are [m]'s interface file dependencies. *)

    val ml : t -> Fpath.t option
    (** [ml m] is [m]'s implementation file (if any). *)

    val ml_deps : t -> Name.Set.t
    (** [ml_deps m] are [m]'s implementation file dependencies. *)

    (** {1:files Constructing file paths} *)

    val build_dir : t -> Fpath.t
    (** [build_dir m] is the build directory for the module. *)

    val built_file : t -> ext:string -> Fpath.t
    (** [built_file m ~ext] is a file for module [m] with extension [ext]
        in directory {!build_dir}[ m]. *)

    val cmi_file : t -> Fpath.t
    (** [cmi_file m] is [built_file m ext:".cmi"]. *)

    val cmo_file : t -> Fpath.t option
    (** [cmo_file m] is [built_file m ext:".cmo"] if {!ml} is [Some _]. *)

    val cmx_file : t -> Fpath.t option
    (** [cmx_file m] is [built_file m ext:".cmx"] if {!ml} is [Some _]. *)

    val impl_file : code:Conf.code -> t -> Fpath.t option
    (** [impl_file ~code m] is {!cmx_file} or {!cmo_file}
        according to [code]. *)

    val as_intf_dep_files : ?init:Fpath.t list -> t -> Fpath.t list
    (** [as_intf_dep_files ~init m] adds to [init] (defaults to [[]])
        the files that are read by the OCaml compiler if module source
        [m] is compiled in {!build_dir} and used as an interface
        compilation dependency. *)

    val as_impl_dep_files :
      ?init:Fpath.t list -> code:Conf.code -> t -> Fpath.t list
    (** [as_impl_dep_files ~init ~code m] adds to [init] (defaults to
        [[]]) the files that are read by the OCaml compiler if module
        source [m] is compiled in {!build_dir} and used an
        implementation file dependency for code [code]. *)

    (** {1:map Module name maps} *)

    val map_of_srcs :
      Memo.t -> build_dir:Fpath.t -> srcs:Fpath.t list ->
      src_deps:Name.Set.t Fpath.Map.t -> t Name.Map.t
    (** [of_srcs m ~srcs ~src_deps] determines source modules values
        to be built in [build_dir] (mapped by their names) given
        sources [srcs] and their dependencies [src_deps]
        (e.g. obtainted via {!Deps.read}. If there's more than one
        [mli] or [ml] file for a given module name a warning is
        notified on [m] and a single one is kept. *)

    val sort :
      ?stable:t list -> deps:(t -> Name.Set.t) -> t Name.Map.t -> t list
    (** [sort ~stable ~deps srcs] sorts [srcs] in [deps] dependency order
        respecting elements mentioned in [stable] (if any). *)

    val find : Name.Set.t -> t Name.Map.t -> t list * Name.Set.t
    (** [find names srcs] is [(mods, remain)] with [mods] the names
        of [names] found in [srcs] and [remain] those that are not. *)

    (** {1:convenience Convenience} *)

    val map_of_files :
      ?only_mlis:bool -> Memo.t -> build_dir:Fpath.t -> src_root:Fpath.t ->
      srcs:B00_fexts.map -> t Name.Map.t Fut.t
    (** [map_of_files m ~only_mlis ~build_dir ~src_root ~srcs] looks for
        [.ml] (if [only_mlis] is [false], default) and [.mli] files in
        [srcs] and determines sorted module sources. [src_root]
        indicates a root for the sources in [srcs] and [build_dir] are
        used to write the {!Deps} sort. *)

    val pp : t Fmt.t
    (** [pp] formats a module source *)
  end
end

(** Compiled object information. *)
module Cobj : sig

  val archive_ext_of_code : Conf.code -> Fpath.ext
  (** [archive_ext_of_code c] is [.cma] or [.cmxa] according to [c]. *)

  val object_ext_of_code : Conf.code -> Fpath.ext
  (** [object_ext_of_code c] is [.cmo] or [.cmx] according to [c]. *)

  (** {1:cobjs Compilation objects} *)

  type t
  (** The type for compilation objects. This can represent one
      of a [cmi], [cmti], [cmo], [cmx], [cmt], [cma] or [cmxa] file. *)

  val file : t -> Fpath.t
  (** [file c] is the compilation object file path. *)

  val defs : t -> Mod.Ref.Set.t
  (** [defs c] are the modules defined by the compilation object. If
      there's more than one you are looking an archive. *)

  val deps : t -> Mod.Ref.Set.t
  (** [deps c] is the set of modules needed by [defs c]. More precisely
      these are the module interfaces imported by [c]. See also {!link_deps}. *)

  val link_deps : t -> Mod.Ref.Set.t
  (** [link_deps c] is the set of modules needed to link [defs c].

      {b Note.} Unclear whether this is the right data. Basically
      these are the module references that of {!deps} whose name is in the
      {{:https://github.com/ocaml/ocaml/blob/a0fa9aa6e85ca4db9fc19389f89be9ff0d3bd00f/file_formats/cmo_format.mli#L36}required globals}
      (bytecode) or {{:https://github.com/ocaml/ocaml/blob/trunk/file_formats/cmx_format.mli#L43}imported implementations} (native code) as reported
      by ocamlobjinfo. Initially we'd use [deps] for link dependencies
      but it turns out that this may break on
      {{:https://github.com/ocaml/ocaml/issues/8728}certain} install
      structures. It's unclear whether we need both {!deps} and
      {!link_deps} and/or if that's the correct information. *)

  val pp : t Fmt.t
  (** [pp] formats an compilation object. *)

  val sort : ?deps:(t -> Mod.Ref.Set.t) -> t list -> t list * Mod.Ref.Set.t
  (** [sort ~deps cobjs] is [cobjs] stable sorted in dependency
      order according to [deps] (defaults to {!link_deps}), tupled with
      external dependencies needed by [cobjs]. *)

  val equal : t -> t -> bool
  (** [equal c0 c1] is [Fpath.equal (file c0) (file c1)]. *)

  val compare : t -> t -> int
  (** [compare] is a total order on compilation objects compatible
      with {!equal}. *)

  (** Compilation objects sets. *)
  module Set : Set.S with type elt = t

  (** Compilation objectx maps. *)
  module Map : Map.S with type key = t

  (** {1:io IO} *)

  val write : B00.Memo.t -> cobjs:Fpath.t list -> o:Fpath.t -> unit
  (** [write m ~cobjs o] writes information about the compilation [cobjs]
      to [o]. *)

  val read : B00.Memo.t -> Fpath.t -> t list Fut.t
  (** [read m file] has the [cobjs] of a {!write} to [file]. *)

  val of_string : ?file:Fpath.t -> string -> (t list, string) result
  (** [of_string ~file data] parses compilation object information from
      [data] as output by {!Tool.ocamlobjinfo} assuming it was
      read from [file] (defaults to {!B00_std.Os.File.dash}). *)
end

(** Library information and lookup.

    An OCaml library is a directory with interfaces and object
    files. OCaml libraries are resolved by {{!Name}name} using a {!Resolver}. *)
module Lib : sig

  (** {1:name Library names} *)

  (** Library names.

      Library names are dot separated segments of uncapitalized OCaml
      compilation unit names. Replacing the dots by the platform
      directory separator yields the directory of the library relative to the
      [OCAMLPATH]. Here are examples of library names and corresponding
      library directories for the following [OCAMLPATH]:
{v
OCAMLPATH=/home/bactrian/opam/lib:/usr/lib/ocaml

Library name       Library directory
----------------------------------------------------------------
ptime.clock.jsoo   /home/bactrian/opam/lib/ptime/clock/jsoo
re.emacs           /home/bactrian/opam/lib/re/emacs
ocamlgraph         /usr/lib/ocaml/ocamlgraph
ocaml.unix         /usr/lib/ocaml/ocaml/unix
N/A (shadowed)     /usr/lib/ocaml/re/emacs
v}

      For legacy reasons library names also correspond to [ocamlfind]
      package names. *)
  module Name : sig

    (** {1:name Library names} *)

    type t
    (** The type for library names looked up in [OCAMLPATH].
        For legacy reasons this may also correspond to an [ocamlfind]
        package name. *)

    val v : string -> t
    (** [v s] is a library for [n]. Raises [Invalid_argument] if [s] is
        not a valid library name. *)

    val first : t -> string
    (** [first n] is [n]'s first name, that is the rightmost one. *)

    val last : t -> string
    (** [last n] is [n]'s last name, that is the leftmost one. *)

    val undot : rep:Char.t -> t -> string
    (** [undot ~rep n] is [n] with [.] replaced by [rep]. *)

    val to_archive_name : t -> string
    (** [to_archive_name n] is [undot ~rep:'_' n]. *)

    val of_string : string -> (t, string) result
    (** [of_string s] is a library name from [n]. *)

    val to_string : t -> string
    (** [to_string n] is [n] as a string. *)

    val to_fpath : t -> Fpath.t
    (** [to_fpath n] is [n] with dots replaced by
        {!B00_std.Fpath.dir_sep_char}. *)

    val equal : t -> t -> bool
    (** [equal n0 n1] is [true] iff [n0] and [n1] are the same library name. *)

    val compare : t -> t -> int
    (** [compare n0 n1] is a total order on library names compatible with
        {!equal}. *)

    val pp : t Fmt.t
    (** [pp] formats a library name. *)

    (** Library name sets. *)
    module Set : Set.S with type elt = t

    (** Library name maps. *)
    module Map : Map.S with type key = t
  end

  (** {1:libs Libraries} *)

  type t
  (** The type for libraries. *)

  val v :
    name:Name.t -> requires:Name.t list -> dir:Fpath.t ->
    cmis:Fpath.t list -> cmxs:Fpath.t list -> cma:Fpath.t option ->
    cmxa:Fpath.t option -> c_archive:Fpath.t option ->
    c_stubs:Fpath.t list -> t
  (** [v ~name ~cmis ~cmxs ~cma ~cmxa] is a library named [name] which
      requires libraries [requires], and library directory [dir], has
      [cmis] cmi files, [cmxs] cmx files, [cma] bytecode archive,
      [cmxa] native code archive and it's companion [c_archive] as
      well as [c_stubs] archives. Theoretically all files should be in
      [dir]. *)

  val of_dir :
    Memo.t -> clib_ext:Fpath.ext -> name:Name.t -> requires:Name.t list ->
    dir:Fpath.t -> archive:string option -> (t, string) result Fut.t
  (** [of_dir m ~clib_ext ~name ~requires ~dir ~archive] is a library named
      [name] which requires libraries [requires], with library
      directory [dir] and library archive name [archive] (without
      extension and if any). This looks up all files other files in
      [dir] and makes them ready in [m]. [clib_ext] is the platform
      specific extension for C libraries.

      {b Note.} If [dir] doesn't follow the one library per directory
      convention this over-approximate [cmis], [cmxs] and [c_stubs]
      files. *)

  val name : t -> Name.t
  (** [name l] is the library name of [l]. *)

  val requires : t -> Name.t list
  (** [requires l] are the libraries that are required by [l]. *)

  val dir : t -> Fpath.t
  (** [dir l] is [l]'s library directory. *)

  val cmis : t -> Fpath.t list
  (** [cmis l] is the list of cmis for the library. *)

  val cmxs : t -> Fpath.t list
  (** [cmxs l] is the list of cmxs for the library. *)

  val cma : t -> Fpath.t option
  (** [cma l] is the library's cma file (if any). *)

  val cmxa : t -> Fpath.t option
  (** [cmxa l] is the library's cmxa file (if any). *)

  val c_archive : t -> Fpath.t option
  (** [c_archive l] is the library's [cmxa]'s companion C archive. Must
      exist if the [cmxa] exists. *)

  val c_stubs : t -> Fpath.t list
  (** [c_stubs l] is the library's C stubs archives (if any). *)

  (** Library resolvers. *)
  module Resolver : sig

    (** {1:scopes Resolution scopes}

        Resolution scopes allow to compose and order multiple library
        resolution mechanisms. In particular it allows [b0] to lookup
        for libraries in builds before trying to resolve them in in
        the build environment. *)

    type lib = t
    (** The type for libraries, see {!B00_ocaml.Lib.t}. *)

    type scope
    (** The type for scopes. A scope has a name, a library lookup function
        and possibly a function to indicate how to troubleshoot a missing
        library. *)

    type scope_find = Conf.t -> Memo.t -> Name.t -> lib option Fut.t
    (** The type for the scope finding function. *)

    type scope_suggest = Conf.t -> Memo.t -> Name.t -> string option Fut.t
    (** The type for the scope missing library suggestion function. *)

    val scope : name:string -> find:scope_find -> suggest:scope_suggest -> scope
    (** [scope ~name ~find ~suggest] is a scope named [name] looking
        up libraries with [find] and giving suggestions on missing
        libraries with [suggest]. *)

    val scope_name : scope -> string
    (** [scope_name s] is the name of [s]. *)

    val scope_find : scope -> scope_find
    (** [scope_find s] is the lookup funtion of [s]. *)

    val scope_suggest : scope -> scope_suggest
    (** [scope_suggest s] is the scope suggestion function. *)

    (** {2:predef_scopes Predefined resolution scopes} *)

    val ocamlpath : cache_dir:Fpath.t -> ocamlpath:Fpath.t list -> scope
    (** [ocampath ~cache_dir ~ocamlpath] looks up libraries according
        to the OCaml library convention in the [OCAMLPATH] [ocamlpath]
        using [cache_dir] to cache results.

        {b Note.} This is a nop for now. *)

    val ocamlfind : cache_dir:Fpath.t -> scope
    (** [ocamlfind ~cache_dir] looks up libraries using [ocamlfind]
        and caches the result in [cache_dir].

        A few simplyifing assumptions are made by the resolver, which
        basically boil down to query the library name [LIB] with:
{[
ocamlfind query LIB -predicates byte,native -format "%m:%d:%A:%(requires)"
]}
      to derive a {!Lib.t} value. This may fail on certain libraries. In
      particular it assumes a one-to-one map between [ocamlfind] package
      names and library names and that the archives are in the library
      directory. Also the [ocaml.threads], [threads] and [threads.posix]
      libraries are treated specially, the all lookup the latter and
      [mt,mt_posix] is added to the predicates. [threads.vm] is unsupported
      (but deprecated anyways). *)

    (** {1:resolver Resolver} *)

    type t
    (** The type for library resolvers. *)

    val create : B00.Memo.t -> Conf.t -> scope list -> t
    (** [create m ocaml_conf scopes] is a library resolver looking for
        libraries in the given [scopes], in order. [ocaml_conf] is the
        toolchain configuration. [m] gets marked by [ocamlib]. *)

    val ocaml_conf : t -> Conf.t
    (** [ocaml_conf r] is the OCaml configuration of the resolver. *)

    val find : t -> Name.t -> lib option Fut.t
    (** [find r n] finds library name [n] in [l]. *)

    val get : t -> Name.t -> lib Fut.t
    (** [find r l] finds library name [l] using [r]. The memo of [r]
        fails if a library cannot be found. *)

    val get_list :  t -> Name.t list -> lib list Fut.t
    (** [get_list b ns] looks up the libraries [ns] in the build [b]
        using {!lib_resolver}. Libraries are returned in the given
        order and the memo of [r] fails if a library cannot be
        found. *)

    val get_list_and_deps : t -> Name.t list -> lib list Fut.t
    (** [get_list_and_deps b ns] looks up the libraires [ns] and their
        dependencies in the build [b] using {!lib_resolver}. The result
        is a sorted in (stable) dependency order.  *)
  end
end

(** OCAMLPATH search path.

    FIXME, maybe this should be a store key. *)
module Ocamlpath : sig

  val get : Memo.t -> Fpath.t list option -> Fpath.t list Fut.t
  (** [get m o k] is [k ps] if [o] is [Some ps] and otherwise in order:
      {ol
      {- If the [OCAMLPATH] environment variable is defined in [m] and
         non-empty its content is parsed s according to
         {!B00_std.Fpath.list_of_search_path}.}
      {- If the [OPAM_SWITCH_PREFIX] environment variable is defined with
         a path [P] then [[P/lib]] is used.}
      {- The memo fails.}} *)
end

(** Compiling.

    Tool invocations for compiling. *)
module Compile : sig

  val c_to_o :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    comp:B00.Tool.t -> opts:Cmd.t -> reads:Fpath.t list -> c:Fpath.t ->
    o:Fpath.t -> unit
  (** [c_to_o m ~comp ~opts ~reads ~c ~o] compiles the C file [c] to
      the object file [o] with options [opts] and using compiler
      [comp].  It assumes the compilation depends on C include header
      files [reads] whose parent directories are added as [-I]
      options. *)

  val mli_to_cmi :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> and_cmti:bool ->
    Memo.t -> comp:B00.Tool.t -> opts:Cmd.t -> reads:Fpath.t list ->
    mli:Fpath.t -> o:Fpath.t -> unit
  (** [mli_to_cmi ~and_cmti m ~comp ~opts ~reads ~mli ~o] compiles the
      file [mli] to the cmi file [o] and, if [and_cmti] is [true], to
      the cmti file [Fpath.(o -+ ".cmti")] with options [opts] and
      using compiler [comp]. It assumes the compilation depends on cmi
      files [reads] whose parent directories are added as [-I]
      options. *)

  val ml_to_cmo :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> and_cmt:bool ->
    Memo.t -> opts:Cmd.t -> reads:Fpath.t list -> has_cmi:bool -> ml:Fpath.t ->
    o:Fpath.t -> unit
  (** [ml_to_cmo ~and_cmt m ~opts ~reads ~has_cmi ~ml ~o] compiles the
      file [ml] to cmo file [o] and, if [and_cmt] is [true], to the
      cmt file [Fpath.(o -+ ".cmt")] with options [opts]. It assumes
      the compilation depends on the cmi files [reads] whose parent
      directories are added as [-I] options. [has_cmi] indicates
      whether the [ml] file already a corresponding cmi file, in which
      case it should be in [reads] (FIXME specify path directly ?). *)

  val ml_to_cmx :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> and_cmt:bool ->
    Memo.t -> opts:Cmd.t -> reads:Fpath.t list -> has_cmi:bool -> ml:Fpath.t ->
    o:Fpath.t -> unit
  (** [ml_to_cmx ~and_cmt m ~opts ~reads ~has_cmi ~ml ~o ~and_cmt]
      compiles the file [ml] to cmx file [o] and, if [and_cmt] is
      [true], to the cmt file [Fpath.(o -+ ".cmt")] with options
      [opts]. It assumes the compilation depends on the cmi and cmx
      files [reads] whose parent directories are added as [-I]
      options. [has_cmi] indicates whether the [ml] file already has a
      corresponding cmi file, in which case it should be in [reads]
      (FIXME specify path directly ?). *)

  val ml_to_impl :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    code:Conf.code -> opts:Cmd.t -> reads:Fpath.t list -> has_cmi:bool ->
    ml:Fpath.t -> o:Fpath.t -> and_cmt:bool -> unit
  (** [ml_to_impl] is {!ml_to_cmo} or {!ml_to_cmx} according to [code].
       Beware that the given arguments must be common to both *)

  (** {1:srcs [Mod.Src] convenience}

      A few helpers that deal directly with the {!Mod.Src} abstraction. *)

  val mod_src_intf :
    and_cmti:bool -> Memo.t -> comp:B00.Tool.t -> opts:Cmd.t ->
    requires:Lib.t list -> mod_srcs:Mod.Src.t Mod.Name.Map.t -> Mod.Src.t ->
    unit
  (** [mod_src_intf m ~opts ~requires ~mod_srcs ~and_cmti src]
      compiles the interface of [src] with options [opts] and compiler
      [comp] assuming its dependencies are in [mod_srcs] and
      [requires]. If [and_cmti] is [true] the [cmti] file is also
      produced. If [src] has no [.mli] this is a nop. *)

  val mod_src_impl :
    and_cmt:bool -> Memo.t -> code:Conf.code -> opts:Cmd.t ->
    requires:Lib.t list -> mod_srcs:Mod.Src.t Mod.Name.Map.t -> Mod.Src.t ->
    unit
  (** [mod_src_impl m ~code ~opts ~requires ~mod_srcs src] compile the
      implementation of [src] with option [opts] to code [code]
      asuming it dependencies are in [mod_src]. If [and_cmt] is [true]
      the [cmt] file is also produced. If [src] has no [.ml] this is
      a nop. *)

  val intfs :
    and_cmti:bool -> Memo.t -> comp:B00.Tool.t -> opts:Cmd.t ->
    requires:Lib.t list -> mod_srcs:Mod.Src.t Mod.Name.Map.t -> unit
  (** [intfs] iters {!mod_src_intf} over the elements of [mod_srcs]. *)

  val impls :
    and_cmt:bool -> Memo.t -> code:Conf.code -> opts:Cmd.t ->
    requires:Lib.t list -> mod_srcs:Mod.Src.t Mod.Name.Map.t -> unit
   (** [impls] iters {!mod_src_impl} over the elements of [mod_srcs]. *)
end

(** Archiving.

    Tool invocations for archiving. *)
module Archive : sig

  val cstubs :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> c_objs:Fpath.t list -> odir:Fpath.t ->
    oname:string -> unit
  (** [cstubs m ~conf ~opts ~c_objs ~odir ~oname] creates in directory
      [odir] C stubs archives for a library named [oname]. *)

  (* FIXME change the odir/oname into files as usual and pass the
     c stubs archive directly. *)

  val byte :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> has_cstubs:bool -> cobjs:Fpath.t list ->
    odir:Fpath.t -> oname:string -> unit
  (** [byte_archive m ~opts ~has_cstubs ~cobjs ~obase] creates in directory
      [odir] a bytecode archive named [oname] with the OCaml bytecode
      compilation objects [cobjs]. *)

  val native :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> has_cstubs:bool -> cobjs:Fpath.t list ->
    odir:Fpath.t -> oname:string -> unit
  (** [native m ~opts ~has_cstubs ~cobjs ~obase] creates in directory
      [odir] a native code archive named [oname] with the OCaml native
      code compilation objects [cobjs]. *)

  val code :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> code:Conf.code -> has_cstubs:bool ->
    cobjs:Fpath.t list -> odir:Fpath.t -> oname:string -> unit
  (** [archive] is {!byte_archive} or {!native_archive} according to
      [code]. *)

  val native_dynlink :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> has_cstubs:bool -> cmxa:Fpath.t ->
    o:Fpath.t -> unit
end

(** Linking.

    Tool invocations for linking. *)
module Link : sig
  val byte :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> c_objs:Fpath.t list -> cobjs:Fpath.t list ->
    o:Fpath.t -> unit
  (** [byte_exe m ~opts ~c_objs ~cmos ~o] links the C objects [c_objs]
      and the OCaml compilation object files [cobjs] into a byte code
      executable [o] compiled in [-custom] mode. *)

  val native :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> c_objs:Fpath.t list -> cobjs:Fpath.t list ->
    o:Fpath.t -> unit
  (** [byte_exe m ~opts ~c_objs ~cobjs ~o] links the C objects
      [c_objs] and the OCaml compilation object files [cobjs] into a
      native code executable [o]. An include is added to each element
      of [cobjs] in order to lookup potential C stubs. *)

  val code :
    ?post_exec:(B000.Op.t -> unit) -> ?k:(int -> unit) -> Memo.t ->
    conf:Conf.t -> opts:Cmd.t -> code:Conf.code -> c_objs:Fpath.t list ->
    cobjs:Fpath.t list -> o:Fpath.t -> unit
  (** [code] is {!byte} or {!native} according to [code]. *)
end

(** Crunching data into OCaml values. *)
module Crunch : sig
  val string_to_string : id:string -> data:string -> string
  (** [string_to_string ~id ~data] let binds binary [data] to [id] using
      a string. *)
end

(*---------------------------------------------------------------------------
   Copyright (c) 2019 The b0 programmers

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)