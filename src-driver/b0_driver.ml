(*---------------------------------------------------------------------------
   Copyright (c) 2020 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

open B0_std

module Exit = struct
  type t = Code of int | Exec of Fpath.t * Cmd.t
  let code = function Code c -> c | _ -> invalid_arg "not an exit code"
  let b0_file_error = Code 121
  let no_b0_file = Code 122
  let no_such_name = Code 119
  let ok = Code 0
  let some_error = Code 123

  module Info = struct
    let e c doc = Cmdliner.Term.exit_info (code c) ~doc
    let b0_file_error = e b0_file_error "on B0 file error."
    let no_b0_file = e no_b0_file "no B0 file found."
    let no_such_name = e no_such_name "a specified name does not exist."
    let some_error = e some_error "on indiscriminate errors reported on stderr."
    let base_cmd =
      b0_file_error :: no_b0_file :: no_such_name :: some_error ::
      Cmdliner.Term.default_exits
  end
end

module Env = struct
  let b0_dir = B00_ui.Memo.b0_dir_env
  let b0_file = "B0_FILE"
  let cache_dir = B00_ui.Memo.cache_dir_env
  let color = "B0_COLOR"
  let code = "B0_DRIVER_CODE"
  let hash_fun = B00_ui.Memo.hash_fun_env
  let jobs = B00_ui.Memo.jobs_env
  let verbosity = "B0_VERBOSITY"
end

module Conf = struct
  let b0_file_name = "B0.ml"
  let drivers_dir_name = ".drivers"

  type t =
    { b0_dir : Fpath.t;
      b0_file : Fpath.t option;
      cache_dir : Fpath.t;
      cwd : Fpath.t;
      code : B0_ocaml.Cobj.code option;
      hash_fun : (module Hash.T);
      jobs : int;
      log_level : Log.level;
      no_pager : bool;
      memo : (B00.Memo.t, string) result Lazy.t;
      tty_cap : Tty.cap; }

  let memo ~hash_fun ~cwd ~cache_dir ~trash_dir ~jobs =
    let feedback =
      let op_howto ppf o = Fmt.pf ppf "b0 file log --id %d" (B000.Op.id o) in
      let show_op = Log.Info and show_ui = Log.Error and level = Log.level () in
      B00_ui.Memo.pp_leveled_feedback ~op_howto ~show_op ~show_ui ~level
        Fmt.stderr
    in
    B00.Memo.memo ~hash_fun ~cwd ~cache_dir ~trash_dir ~jobs ~feedback ()

  let v
      ~b0_dir ~b0_file ~cache_dir ~cwd ~code ~hash_fun ~jobs
      ~log_level ~no_pager ~tty_cap ()
    =
    let trash_dir = Fpath.(b0_dir / B00_ui.Memo.trash_dir_name) in
    let memo = lazy (memo ~hash_fun ~cwd ~cache_dir ~trash_dir ~jobs) in
    { b0_dir; b0_file; cache_dir; cwd; code; hash_fun; jobs;
      memo; log_level; no_pager; tty_cap }

  let b0_dir c = c.b0_dir
  let b0_file c = c.b0_file
  let cache_dir c = c.cache_dir
  let cwd c = c.cwd
  let code c = c.code
  let hash_fun c = c.hash_fun
  let jobs c = c.jobs
  let log_level c = c.log_level
  let memo c = Lazy.force c.memo
  let no_pager c = c.no_pager
  let tty_cap c = c.tty_cap

  let get_b0_file c = match c.b0_file with
  | Some file -> Ok file
  | None ->
      let path = Fmt.(code Fpath.pp_unquoted) in
      let code = Fmt.(code string) in
      Fmt.error
        "@[<v>No %a file found in %a or upwards.@,\
         Use option %a to specify one or %a for help.@]"
        code "B0.ml" path c.cwd Fmt.(code string) "--b0-file"
        Fmt.(code string) "--help"

  (* Setup *)

  let find_b0_file ~cwd ~b0_file = match b0_file with
  | Some b0_file -> Some (Fpath.(cwd // b0_file))
  | None ->
      let rec loop dir =
        let file = Fpath.(dir / b0_file_name) in
        match Os.File.exists file with
        | Ok true -> Some file
        | _ ->
            if not (Fpath.is_root dir) then loop (Fpath.parent dir) else None
      in
      loop cwd

  let setup_with_cli
      ~b0_dir ~b0_file ~cache_dir ~code ~hash_fun ~jobs
      ~log_level ~no_pager ~tty_cap ()
    =
    let tty_cap = B0_std_ui.get_tty_cap tty_cap in
    let log_level = B0_std_ui.get_log_level log_level in
    B0_std_ui.setup tty_cap log_level ~log_spawns:Log.Debug;
    Result.bind (Os.Dir.cwd ()) @@ fun cwd ->
    let b0_file = find_b0_file ~cwd ~b0_file in
    let root = match b0_file with Some f -> Fpath.parent f | None -> cwd  in
    let b0_dir = B00_ui.Memo.get_b0_dir ~cwd ~root ~b0_dir in
    let cache_dir = B00_ui.Memo.get_cache_dir ~cwd ~b0_dir ~cache_dir in
    let hash_fun = B00_ui.Memo.get_hash_fun ~hash_fun in
    let jobs = B00_ui.Memo.get_jobs ~jobs in
    Ok (v ~b0_dir ~b0_file ~cache_dir ~cwd ~code ~hash_fun
          ~jobs ~log_level ~no_pager ~tty_cap ())
end

module Cli = struct
  open Cmdliner

  let docs = Manpage.s_common_options
  let b0_dir = B00_ui.Memo.b0_dir ~docs ()
  let b0_file =
    let env = Arg.env_var Env.b0_file in
    let doc = "Use $(docv) as the B0 file." and docv = "PATH" in
    let none = "B0.ml file in cwd or first upwards" in
    Arg.(value & opt (Arg.some ~none B0_std_ui.fpath) None &
         info ["b0-file"] ~doc ~docv ~docs ~env)

  let cache_dir = B00_ui.Memo.cache_dir ~docs ()
  let code =
    let env = Arg.env_var Env.code in
    let code_enum = [ "byte", Some B0_ocaml.Cobj.Byte;
                      "native", Some B0_ocaml.Cobj.Native;
                      "auto", None ]
    in
    let code = Arg.enum code_enum in
    let docv = "CODE" in
    let doc =
      "Compile driver to $(docv). $(docv) must be $(b,byte), $(b,native) or \
       $(b,auto). If $(b,auto) favors native code if available."
    in
    Arg.(value & opt code None & info ["driver-code"] ~doc ~docv ~docs ~env)

  let hash_fun = B00_ui.Memo.hash_fun ~docs ()
  let jobs = B00_ui.Memo.jobs ~docs ()
  let log_level = B0_std_ui.log_level ~docs ~env:(Arg.env_var Env.verbosity) ()
  let tty_cap = B0_std_ui.tty_cap ~docs ~env:(Arg.env_var Env.color) ()
  let no_pager = B0_pager.don't ~docs ()
  let conf =
    let conf
        b0_dir b0_file cache_dir code hash_fun jobs log_level no_pager tty_cap
      =
      Result.map_error (fun s -> `Msg s) @@
      Conf.setup_with_cli
        ~b0_dir ~b0_file ~cache_dir ~code ~hash_fun ~jobs ~log_level
        ~no_pager ~tty_cap ()
    in
    Term.term_result @@
    Term.(const conf $ b0_dir $ b0_file $ cache_dir $ code $
          hash_fun $ jobs $ log_level $ no_pager $ tty_cap)
end

(* Drivers *)

type main = unit -> Exit.t Cmdliner.Term.result
type t =
  { name : string;
    version : string;
    libs : B0_ocaml_lib.Name.t list }

let create ~name ~version ~libs = { name; version; libs }
let name d = d.name
let version d = d.version
let libs d = d.libs

let has_b0_file = ref false (* set by run *)
let driver = ref None
let set ~driver:d ~main = driver := Some (d, main)
let run ~has_b0_file:b0_file = match !driver with
| None -> invalid_arg "No driver set via B0_driver.set"
| Some (d, main) ->
    let wrap_main main () =
      try main () with B0_def.Scope.After_seal e ->
        (* FIXME I suspect we may never see this it will be catched
           by memo protection. At least make a good error msg. *)
        let bt = Printexc.get_raw_backtrace () in
        Log.err (fun m -> m ~header:"" "@[<v>%a@,@[%s@]@]" Fmt.backtrace bt e);
        `Ok Exit.b0_file_error
    in
    let run_main main =
      Log.time begin fun _ m ->
        let b0_file = if b0_file then "with B0.ml" else "no B0.ml" in
        m "total time %s %s %s" d.name d.version b0_file
      end main
    in
    let exit_main = function
    | Exit.Code c -> exit c
    | Exit.Exec (exec, cmd) ->
        exit @@ Log.if_error ~use:Exit.(code some_error) @@
        Result.bind (Os.Cmd.execv exec cmd) @@ fun _ -> assert false
    in
    has_b0_file := b0_file;
    match run_main (wrap_main main) with
    | `Ok res -> exit_main res
    | e -> Cmdliner.Term.exit ~term_err:Exit.(code some_error) e

let has_b0_file () = !has_b0_file

module Compile = struct
  let build_dir c ~driver =
    Fpath.(Conf.b0_dir c / Conf.drivers_dir_name / name driver)

  let build_log c ~driver =
    Fpath.(Conf.b0_dir c / Conf.drivers_dir_name / name driver / "log")

  let exe c ~driver =
    Fpath.(Conf.b0_dir c / Conf.drivers_dir_name / name driver / "exe")

  let write_src m c src ~src_file  =
    let esrc = B00.Memo.fail_if_error m (B0_file_src.expand src) in
    let reads = B0_file_src.expanded_file_manifest esrc in
    List.iter (B00.Memo.file_ready m) reads;
    B00.Memo.write m ~reads src_file @@ fun () ->
    Ok (B0_file_src.expanded_src esrc)

  let find_compiler c m =
    (* XXX something like this should be moved to B0 care. *)
    let comp t code m = B00.Memo.tool m t, code in
    let byte m = comp B0_ocaml.Tool.ocamlc B0_ocaml.Cobj.Byte m in
    let native m = comp B0_ocaml.Tool.ocamlopt B0_ocaml.Cobj.Native m in
    match Conf.code c with
    | Some B0_ocaml.Cobj.Byte -> byte m
    | Some B0_ocaml.Cobj.Native -> native m
    | None ->
        match B00.Memo.tool_opt m B0_ocaml.Tool.ocamlopt with
        | None -> byte m
        | Some comp -> comp, B0_ocaml.Cobj.Native

  let base_libs =
    [ B0_ocaml_lib.Name.v "cmdliner/cmdliner";
      B0_ocaml_lib.Name.v "ocaml/unix"; (* FIXME system switches *)
      B0_ocaml_lib.Name.v "b0.std/b0_std";
      B0_ocaml_lib.Name.v "b0.b00/b00";
      B0_ocaml_lib.Name.v "b0.care/b0_care"; (* FIXME b00 care ! *)
      B0_ocaml_lib.Name.v "b0.defs/b0_defs";
      B0_ocaml_lib.Name.v "b0.file/b0_file";
      B0_ocaml_lib.Name.v "b0.driver/b0_driver"; ]

  let find_libs libs r k =
    let rec loop acc = function
    | [] -> k (List.rev acc)
    | l :: libs ->
        B0_ocaml_lib.Resolver.find r l @@ fun lib -> loop (lib :: acc) libs
    in
    loop [] libs

  let find_libs m ~build_dir ~driver f k =
    B0_ocaml_lib.Ocamlpath.get m None @@ fun ocamlpath ->
    let memo_dir = Fpath.(build_dir / "ocaml-lib-resolve") in
    let r = B0_ocaml_lib.Resolver.create m ~memo_dir ~ocamlpath in
    (* FIXME we are loosing locations here would be nice to
       have them to report errors. *)
    let requires = List.map fst (B0_file_src.requires f) in
    find_libs requires r @@ fun requires ->
    find_libs (libs driver) r @@ fun driver_libs ->
    find_libs base_libs r @@ fun base_libs ->
    let all_libs = base_libs @ driver_libs @ requires in
    let seen_libs = base_libs @ requires in
    k (all_libs, seen_libs)

  let compile_src m
      (comp, code) ~build_dir ~all_libs ~seen_libs ~clib_ext ~src_file ~exe
    =
    let base = Fpath.rem_ext src_file in
    let writes = match code with
    | B0_ocaml.Cobj.Byte -> [ Fpath.(base + ".cmo"); exe ]
    | B0_ocaml.Cobj.Native ->
        [ Fpath.(base + ".cmx"); Fpath.(base + ".o"); exe ]
    in
    let dirs = List.map B0_ocaml_lib.dir seen_libs in
    let incs = Cmd.unstamp @@ Cmd.paths ~slip:"-I" dirs in
    let archives = List.map (B0_ocaml_lib.archive ~code) all_libs in
    let c_archives = List.map (fun p -> Fpath.(p -+ clib_ext)) archives in
    let ars = List.rev_append archives c_archives in
    (* FIXME this should be done b the resolver *)
    List.iter (B00.Memo.file_ready m) ars;
    let reads = src_file :: ars in
    B00.Memo.spawn m ~reads ~writes @@
    comp Cmd.(arg "-linkall" % "-g" % "-o" %% unstamp (path exe) % "-opaque" %%
              incs %% (unstamp @@ (paths archives %% path src_file)))

  let write_log_file ~log_file m =
    Log.if_error ~use:() @@ B00_ui.Memo.Log.(write log_file (of_memo m))

  let compile c ~driver src =
    Result.bind (Conf.memo c) @@ fun m ->
    let build_dir = build_dir c ~driver in
    let src_file = Fpath.(build_dir / "src.ml") in
    let log_file = build_log c ~driver in
    let exe = exe c ~driver in
    let comp = find_compiler c m in
    (* That shit should be streamlined: brzo, odig, b0caml all
       have similar setup/log/reporting bits. *)
    Os.Sig_exit.on_sigint
      ~hook:(fun () -> write_log_file ~log_file m) @@ fun () ->
    B00.Memo.spawn_fiber m begin fun () ->
      B00.Memo.delete m build_dir @@ fun () ->
      B00.Memo.mkdir m build_dir @@ fun () ->
      write_src m c src ~src_file;
      find_libs m ~build_dir ~driver src @@ fun (all_libs, seen_libs) ->
      B0_ocaml.Conf.lib_ext m @@ fun clib_ext ->
      compile_src m comp
        ~build_dir ~all_libs ~seen_libs ~clib_ext ~src_file ~exe;
    end;
    B00.Memo.stir ~block:true m;
    write_log_file ~log_file m;
    match B00.Memo.status m with
    | Ok () -> Ok exe
    | Error e ->
        let name = name driver in
        let dopt = if name = "b0" then "" else Fmt.str " --driver %s" name in
        let read_howto ppf _ = Fmt.pf ppf "b0 file log%s -r " dopt in
        let write_howto ppf _ = Fmt.pf ppf "b0 file log%s -w " dopt in
        B000_conv.Op.pp_aggregate_error
          ~read_howto ~write_howto () Fmt.stderr e;
        Fmt.error "Could not compile B0 file %a"
          Fmt.(code Fpath.pp_unquoted) (B0_file_src.file src)
end

let with_b0_file ~driver cmd =
  let run conf cmd = match has_b0_file () with
  | true -> cmd conf
  | false ->
      Log.if_error ~use:Exit.no_b0_file @@
      Result.bind (Conf.get_b0_file conf) @@ fun b0_file ->
      Log.if_error' ~use:Exit.b0_file_error @@
      Result.bind (Os.File.read b0_file) @@ fun s ->
      Result.bind (B0_file_src.of_string ~file:b0_file s) @@ fun src ->
      Result.bind (Compile.compile conf ~driver src) @@ fun exe ->
      let argv = Cmd.of_list (fun x -> x) (Array.to_list Sys.argv) in
      Ok (Exit.Exec (exe, argv))
  in
  Cmdliner.Term.(pure run $ Cli.conf $ cmd)

(*---------------------------------------------------------------------------
   Copyright (c) 2020 The b0 programmers

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
