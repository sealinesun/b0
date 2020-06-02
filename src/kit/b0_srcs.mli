(*---------------------------------------------------------------------------
   Copyright (c) 2020 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

(** Select source files.

    This module provides a type to select source files for build units
    in B0 files. To support generated source files, selections can
    depend on the build.

    In a nutshell the declaration:
{[
let srcs = [ `Dir "src-exe"; `Dir_rec "src"; `X "src/not.ml"; `X "src/not"]
]}
    instructs to:
    {ul
    {- Select all the files in {e directory} [src-exe].}
    {- Select all the files in the {e file hierarchy} rooted at
    directory [src].}
    {- Remove from the files found in directories the files whose paths
       segments are prefixed by [src/not.ml] and [src/not].}}

    Relative file paths are expressed relative to the build unit's
    {{!B0_build.Unit.root_dir}root directory}.


    The prefix relation for exclusions respects path segments
    boundaries. In the example any file whose path matches
    [src/not.ml], [src/not.ml/*], [src/not] or [src/not/*] is
    excluded from the selection. But for example [src/not.c] is not.

    The relative order of directory selections and exclusions doesn't
    matter, the semantics is to select all the files via [`Dir] and
    [`Dir_rec] and then apply the exclusion [`X] on the resulting
    set. Exclusions affect only directory selections, not file [`File]
    and future [`Future] {{!sel}selections}.

    When a directory is selected via [`Dir] or [`Dir_rec], all its files
    are, modulo exclusions.  It is expected that build units
    themselves filter the final result by file extension or additional
    mechanisms. Consult the documentation of build units for more
    information. *)

open B00_std

(** {1:sel Source selection} *)

type fpath = string
(** The type for file paths. Must be convertible with
    {!B00_std.Fpath.of_string}. We do not use {!B00_std.Fpath} directly
    to allow for a lighter syntax in B0 files.

    {b Important.} Use only ["/"] as the directory separator even on
    Windows® platforms. Don't be upset the UI gives them back to you
    using the local platform separator. *)

val fpath : Fpath.t -> fpath
(** [fpath] is {!B00_std.Fpath.to_string}. If you prefer to specify your paths
    the clean way. TODO remove ? *)

type sel =
[ `Dir of fpath
| `Dir_rec of fpath
| `X of fpath
| `File of fpath
| `Fut of B0_build.t -> Fpath.Set.t Fut.t ]
(** The type for file selectors.
    {ul
    {- [`File f] unconditionaly selects the file [f]. [f] must exist and be
       a file.}
    {- [`Dir d] selects the files of directory [d] modulo [`X] exclusions.
       [d] must exist and be a directory. dotfile paths are ignored.}
    {- [`Dir_rec d] selects the files of the file {e hierarchy} rooted
       at [d] modulo [`X] exclusions. [d] must exist and be a directory.
       dotfile paths are ignored.}
    {- [`X x] removes from directory selections any file whose path segments
       are prefixed by [x], respecting segment boundaries. A potential trailing
       directory separators in [x] is removed.}
    {- [`Fut f] uses the given future during the build to determine
       a set of files unconditionally added to the selection.}}

    Except for [`Fut], any relative path is made absolute to the
    current build unit with {!B0_build.Unit.root_dir}. *)


type t = sel list
(** The type for source selection. *)

val select : B0_build.t -> t -> B00_fexts.map Fut.t
(** [select b sels] selects in [b] the sources specified by [sels] and
    returns them mapped by their file extension (not
    {{!B00_std.Fpath.file_exts}multiple file extension}). Each file is
    guaranteed to appear only once in the map.

    {b Important.} All files in the map that were selected via [`File],
    [`D] and [`D_rec] are automatically {{!B00.Memo.file_ready}made
    ready} in the build. For those selected via [`Fut] readyness
    determination is left to the invoked funtion.

    {b FIXME.} Provide ordering guarantes and avoid non-det from the
    fs. We likely don't want to return only file extension map. *)

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