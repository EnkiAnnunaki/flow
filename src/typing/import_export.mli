(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

val mk_module_t : Context.t -> Reason.t -> ALoc.t -> Type.t

val get_module_t : Context.t -> ?declare_module:bool -> ALoc.t * string -> Type.t

val require : Context.t -> legacy_interop:bool -> ALoc.t -> string -> Type.t -> Type.t

val import_ns : Context.t -> Reason.t -> Type.t -> Type.t

val cjs_clobber : Context.t -> ALoc.t -> Type.t -> unit

val export :
  Context.t ->
  Reason.name ->
  ?preferred_def_locs:ALoc.t Nel.t ->
  name_loc:ALoc.t ->
  is_type_only_export:bool ->
  Type.t ->
  unit

val export_type :
  Context.t ->
  Reason.name ->
  ?preferred_def_locs:ALoc.t Nel.t ->
  name_loc:ALoc.t option ->
  Type.t ->
  unit

val export_binding :
  Context.t ->
  ?is_function:bool ->
  Reason.name ->
  ?preferred_def_locs:ALoc.t Nel.t ->
  name_loc:ALoc.t ->
  Flow_ast.Statement.export_kind ->
  unit

val export_star : Context.t -> ALoc.t -> Type.t -> unit

val export_type_star : Context.t -> ALoc.t -> Type.t -> unit

val module_exports_sig_loc : Context.t -> ALoc.t option
