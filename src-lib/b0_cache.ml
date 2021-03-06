(*---------------------------------------------------------------------------
   Copyright (c) 2017 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

open B0_result

(* Unix utilties. *)

let uerror = Unix.error_message

let rec unlink p = try Unix.unlink (B0_fpath.to_string p) with
| Unix.Unix_error (Unix.EINTR, _, _) -> unlink p
| Unix.Unix_error (e, _, _) ->
    failwith (B0_string.strf "unlink %a: %s" B0_fpath.pp p (uerror e))

let rec stat p = try Unix.stat (B0_fpath.to_string p) with
| Unix.Unix_error (Unix.EINTR, _, _) -> stat p
| Unix.Unix_error (e, _, _) ->
    failwith (B0_string.strf "stat %a: %s" B0_fpath.pp p (uerror e))

let rec unlink p = try Unix.unlink (B0_fpath.to_string p) with
| Unix.Unix_error (Unix.ENOENT, _, _) -> ()
| Unix.Unix_error (Unix.EINTR, _, _) -> unlink p
| Unix.Unix_error (e, _, _) ->
    failwith (B0_string.strf "unlink %a: %s" B0_fpath.pp p (uerror e))

let rec force_link t p = (* unused for now *)
  try Unix.link (B0_fpath.to_string t) (B0_fpath.to_string p) with
  | Unix.Unix_error (Unix.EEXIST, _, _) -> unlink p; force_link t p
  | Unix.Unix_error (e, _, _) ->
      failwith (B0_string.strf "force link target %a to %a: %s"
                  B0_fpath.pp t B0_fpath.pp p (uerror e))

let rec copy p0 p1 =
  try
    begin
      let mode = (Unix.stat (B0_fpath.to_string p0)).Unix.st_perm in
      B0_os.File.read p0
      >>= fun data -> B0_os.File.write ~mode p1 data
      >>| fun () -> true
    end
    |> R.failwith_error_msg
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> false
  | Unix.Unix_error (Unix.EINTR, _, _) -> copy p0 p1
  | Unix.Unix_error (e, _, _) ->
      failwith (B0_string.strf "stat %a: %s" B0_fpath.pp p0 (uerror e))

(* Cache *)

type t =
  { dir : B0_fpath.t;
    disable : bool;  (* FIXME expand that to mode R|W|RW|Verify *)
    mutable copying : bool; (* [true] if link(2) fails with EXDEV. *)
    mutable dur_counter : B0_time.counter;
    mutable file_stamps : B0_stamp.t B0_fpath.map;
    mutable file_stamp_dur : B0_time.span; }

let dir c = c.dir
let file_stamp_dur c = c.file_stamp_dur
let file_stamps c = c.file_stamps
let cache_file c key = B0_fpath.(c.dir / B0_stamp.to_hex key)
let is_cache_file fpath = match B0_stamp.of_hex (B0_fpath.filename fpath) with
| None -> false | Some _ -> true

let time_stamp c = B0_time.count c.dur_counter

let create ~dir =
  B0_os.Dir.create dir >>= fun _ ->
  Ok { dir; disable = false; copying = false;
       dur_counter = B0_time.counter ();
       file_stamps = B0_fpath.Map.empty;
       file_stamp_dur = B0_time.zero; }

let _file_stamp c file = (* FIXME remove *)
  match B0_fpath.Map.find file c.file_stamps with
  | s -> s
  | exception Not_found ->
      let t = B0_time.counter () in
      let stamp = R.failwith_error_msg @@ B0_stamp.file file in
      let dur = B0_time.count t in
      c.file_stamps <- B0_fpath.Map.add file stamp c.file_stamps;
      c.file_stamp_dur <- B0_time.add dur c.file_stamp_dur;
      stamp

let file_stamp c file = match B0_fpath.Map.find file c.file_stamps with
| s -> Ok (Some s)
| exception Not_found ->
  let t = B0_time.counter () in
  let err p e = R.error_msgf "%a: %s" B0_fpath.pp p (Unix.error_message e) in
  match Unix.(openfile (B0_fpath.to_string file) [O_RDONLY] 0) with
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> Ok None
  | exception Unix.Unix_error (e, _, _) -> err file e
  | fd ->
      match B0_stamp.fd fd with
      | exception Unix.Unix_error (e, _, _)  ->
          (try Unix.close fd with _ -> ()); err file e
      | stamp ->
          match Unix.close fd with
          | exception Unix.Unix_error (e, _, _) -> err file e
          | () ->
              let dur = B0_time.count t in
              c.file_stamps <- B0_fpath.Map.add file stamp c.file_stamps;
              c.file_stamp_dur <- B0_time.add dur c.file_stamp_dur;
              Ok (Some stamp)

let log_xdev () =
  B0_log.warn begin fun m ->
    m "%a" B0_fmt.text
      "Using slow copying cache. Make sure the cache directory and the \
       variant directory are on the same file system."
  end

let rec put c t p =
  (* Make sure destination directory exists *)
  ignore @@ R.failwith_error_msg @@ B0_os.Dir.create (B0_fpath.parent p);
  match c.copying with
  | true -> copy t p
  | false ->
      try Unix.link (B0_fpath.to_string t) (B0_fpath.to_string p); true with
      | Unix.Unix_error (Unix.ENOENT, _, _) -> false
      | Unix.Unix_error (Unix.EINTR, _, _) -> put c t p
      | Unix.Unix_error (Unix.EXDEV, _, _) ->
          log_xdev (); c.copying <- true; copy t p
      | Unix.Unix_error (e, _, _) ->
          failwith (B0_string.strf "link target %a to %a: %s"
                      B0_fpath.pp t B0_fpath.pp p (uerror e))

let op_write_key o file =
  let stamp = B0_stamp.to_bytes @@ B0_op.stamp o in
  B0_stamp.string (stamp ^ B0_fpath.to_string file)

let log_exec o =
  B0_log.debug (fun m -> m ~header:"EXEC" "%a" B0_op.pp_log_line o)

let rec put_writes_from_cache c o =
  let rec loop o undo = function
  | [] ->
      B0_op.(set_status o Cached);
      B0_op.set_exec_end_time o (time_stamp c);
      log_exec o; true
  | f :: fs ->
      let key = op_write_key o f in
      match put c (cache_file c key) f with
      | true -> loop o (f :: undo) fs
      | false ->
          B0_op.set_exec_start_time o B0_time.zero; (* faux d??part *)
          List.iter unlink undo;
          false
  in
  let writes = B0_op.writes o in
  match B0_fpath.Set.is_empty writes with
  | true -> false (* FIXME, once multi writes are partially allowed *)
  | false ->
      B0_op.set_exec_start_time o (time_stamp c);
      loop o [] (B0_fpath.Set.elements (B0_op.writes o))

let rec put_writes_in_cache c o =
  let rec loop o = function
  | [] -> ()
  | f :: fs ->
      let key = op_write_key o f in
      let key = cache_file c key in
      match put c f key with
      | true -> loop o fs
      | false ->
          failwith begin
            B0_string.strf
              "write %a does not exist (key %a)" B0_fpath.pp f B0_fpath.pp key
          end
  in
  loop o (B0_fpath.Set.elements (B0_op.writes o))

let spawn_stamp c o s =
  let op_stamp_reads ?(init = []) c o =
    let add_read f acc = B0_stamp.to_bytes (_file_stamp c f) :: acc in
    B0_fpath.Set.fold add_read (B0_op.reads o) init
  in
  let acc = match B0_op.spawn_stdin s with
  | None -> []
  | Some f -> [B0_fpath.to_string f]
  in
  let acc = op_stamp_reads ~init:acc c o in
  let acc = Array.fold_left (fun acc v -> v :: acc) acc (B0_op.spawn_env s) in
  let acc = List.rev_append (B0_cmd.to_rev_list @@ B0_op.spawn_cmd s) acc in
  match acc with
  | [] -> assert false
  | exe :: _ as acc ->
      let exe_stamp = _file_stamp c (B0_fpath.v exe) in
      let acc = B0_stamp.to_bytes exe_stamp :: acc in
      B0_stamp.string (String.concat "" acc)

let exec_spawn c o s =
  B0_op.set_stamp o (spawn_stamp c o s);
  put_writes_from_cache c o

let exec c o =
  try match c.disable with
  | true -> false
  | false ->
      match B0_op.kind o with
      | B0_op.Spawn s -> exec_spawn c o s
      | B0_op.Copy_file _
      | B0_op.Read _
      | B0_op.Write _ | B0_op.Delete _ | B0_op.Mkdir _ | B0_op.Sync _ -> false
  with
  | Failure e ->
      B0_log.err (fun m -> m "Cached exec: op %d: %s" (B0_op.id o) e); false

let add_op c o = try match c.disable with
| true -> ()
| false ->
    match B0_op.cached o with
    | true -> ()
    | false ->
        match B0_op.kind o with
        | B0_op.Spawn _ -> put_writes_in_cache c o
        | B0_op.Copy_file _
        | B0_op.Read _
        | B0_op.Write _ | B0_op.Delete _ | B0_op.Mkdir _ | B0_op.Sync _ -> ()
with
| Failure e -> B0_log.err (fun m -> m "Cache put: op %d: %s" (B0_op.id o) e)

let files c = B0_os.Dir.contents ~dotfiles:true ~rel:false c.dir

let suspicious_files c =
  files c >>| List.filter (fun f -> not @@ is_cache_file f)

let delete_unused_files c =
  files c >>= fun fs ->
  let rec loop = function
  | [] -> ()
  | f :: fs when (stat f).Unix.st_nlink = 1 -> unlink f; loop fs
  | _ :: fs -> loop fs
  in
  try Ok (loop fs) with Failure msg -> Error (`Msg msg)

let sort_files_by_deletion c =
  (* Order by unused files then access time, break ties by deacreasing size *)
  let order_atime_size (a0, s0, _) (a1, s1, _) =
    match Pervasives.compare (a0 : float) (a1 : float) with
    | 0 -> -1 * Pervasives.compare (s0 : int) (s1 : int)
    | cmp -> cmp
  in
  files c >>= fun fs ->
  let rec loop total_size acc = function
  | [] -> total_size, List.sort order_atime_size acc
  | f :: fs ->
      let st = stat f in
      let f = match st.Unix.st_nlink = 1 with
      | true -> -.max_float (* order unused before *), st.Unix.st_size, f
      | false -> st.Unix.st_atime, st.Unix.st_size, f
      in
      loop (total_size + st.Unix.st_size) (f :: acc) fs
  in
  try Ok (loop 0 [] fs) with Failure msg -> Error (`Msg msg)

let delete_files c ~pct ~dir_byte_size =
  try
    sort_files_by_deletion c >>= fun (total_size, fs) ->
    let pct_size = truncate @@ (float total_size /. 100.) *. float pct in
    let budget = match dir_byte_size with
    | None -> pct_size | Some s -> min s pct_size
    in
    let rec delete_files current budget = function
    | [] -> ()
    | _ when current <= budget -> ()
    | (_, size, f) :: fs -> (unlink f; delete_files (current - size) budget fs)
    in
    Ok (delete_files total_size budget fs)
  with Failure msg -> Error (`Msg msg)

(* Cache directory statistics *)

module Dir_stats = struct
  type t =
    { file_count : int;
      files_byte_size : int;
      unused_file_count : int;
      unused_files_byte_size : int; }

  let file_count s = s.file_count
  let files_byte_size s = s.files_byte_size
  let unused_file_count s = s.unused_file_count
  let unused_files_byte_size s = s.unused_files_byte_size
  let pp ppf s =
    let pp_f c s ppf () =
      B0_fmt.pf ppf "%a in %d file(s)" B0_fmt.byte_size s c
    in
    B0_fmt.pf ppf "@[<v>";
    B0_fmt.field "total" (pp_f s.file_count s.files_byte_size) ppf ();
    B0_fmt.cut ppf ();
    B0_fmt.field "unused"
      (pp_f s.unused_file_count s.unused_files_byte_size) ppf ();
    B0_fmt.pf ppf "@]";
    ()
end

let dir_stats c =
  files c >>= fun fs ->
  let rec loop c cs u us = function
  | [] ->
      Dir_stats.{ file_count = c; files_byte_size = cs;
                  unused_file_count = u; unused_files_byte_size = us }
  | f :: fs ->
      let st = stat f in
      let u, us = match st.Unix.st_nlink with
      | 1 -> u + 1, us + st.Unix.st_size
      | _ -> u, us
      in
      loop (c + 1) (cs + st.Unix.st_size) u us fs
  in
  try Ok (loop 0 0 0 0 fs) with Failure msg -> Error (`Msg msg)

(*---------------------------------------------------------------------------
   Copyright (c) 2017 The b0 programmers

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
