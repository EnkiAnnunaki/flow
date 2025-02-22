(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Utils_js
open Type
open Reason
open Loc_collections
module EnvMap = Env_api.EnvMap

module LookupMode = struct
  type t =
    | ForValue
    | ForType
    | ForTypeof
end

open LookupMode

let get_global_value_type cx name reason =
  match Context.global_value_cache_find_opt cx name with
  | Some t -> t
  | None ->
    let t = Flow_js.get_builtin_result cx name reason in
    Context.add_global_value_cache_entry cx name t;
    t

let get_class_entries cx =
  let { Loc_env.class_stack; class_bindings; _ } = Context.environment cx in
  Base.List.fold
    ~f:(fun lst l ->
      ALocMap.find_opt l class_bindings |> Base.Option.value_map ~f:(fun c -> c :: lst) ~default:lst)
    ~init:[]
    class_stack

let has_hint cx loc =
  if Context.typing_mode cx <> Context.CheckingMode then
    false
  else
    let { Loc_env.hint_map; _ } = Context.environment cx in
    ALocMap.find_opt loc hint_map |> Base.Option.value_map ~f:fst ~default:false

let get_hint cx loc =
  if Context.typing_mode cx <> Context.CheckingMode then
    Type.hint_unavailable
  else
    let { Loc_env.hint_map; _ } = Context.environment cx in
    ALocMap.find_opt loc hint_map |> Base.Option.value ~default:Type.hint_unavailable

let set_scope_kind cx k =
  let env = Context.environment cx in
  let old = env.Loc_env.scope_kind in
  Context.set_environment cx { env with Loc_env.scope_kind = k };
  old

let in_class_scope cx loc f =
  let ({ Loc_env.class_stack; _ } as env) = Context.environment cx in
  Context.set_environment cx { env with Loc_env.class_stack = loc :: class_stack };
  let res = f () in
  let env = Context.environment cx in
  Context.set_environment cx { env with Loc_env.class_stack };
  res

let is_var_kind cx k = (Context.environment cx).Loc_env.scope_kind = k

let in_async_scope cx = is_var_kind cx Name_def.Async || is_var_kind cx Name_def.AsyncGenerator

let var_scope_kind cx = (Context.environment cx).Loc_env.scope_kind

let in_global_scope cx = is_var_kind cx Name_def.Global

let in_toplevel_scope cx = is_var_kind cx Name_def.Module

let is_provider cx id_loc =
  let { Loc_env.var_info = { Env_api.providers; _ }; _ } = Context.environment cx in
  Env_api.Provider_api.is_provider providers id_loc

(* We don't want the new-env to throw if we encounter some new case in the wild for which we did
 * not adequately prepare. Instead, we return `any` in prod mode, but still crash in build mode.
 *)
let with_debug_exn cx loc f =
  try f () with
  | exn ->
    let exn = Exception.wrap exn in
    if Build_mode.dev then
      Exception.reraise exn
    else (
      Flow_js_utils.add_output cx (Error_message.EInternal (loc, Error_message.MissingEnvWrite loc));
      AnyT.at (AnyError None) loc
    )

let with_debug_exn_error cx loc ~f ~error =
  try f () with
  | exn ->
    let exn = Exception.wrap exn in
    if Build_mode.dev then
      Exception.reraise exn
    else (
      Flow_js_utils.add_output cx (Error_message.EInternal (loc, Error_message.MissingEnvWrite loc));
      error ()
    )

let t_option_value_exn cx loc t =
  with_debug_exn cx loc (fun () ->
      match t with
      | Some t -> t
      | None ->
        failwith
          (Utils_js.spf "Missing location entry: %s" (ALoc.debug_to_string ~include_source:true loc))
  )

(************************)
(* Helpers **************)
(************************)

let enforced_env_read_error_opt cx kind loc =
  let ({ Loc_env.under_resolution; var_info; _ } as env) = Context.environment cx in
  match EnvMap.find_opt (kind, loc) var_info.Env_api.env_entries with
  | Some Env_api.NonAssigningWrite -> None
  | _ ->
    (match Loc_env.find_write env kind loc with
    | None -> Some Error_message.(EInternal (loc, MissingEnvWrite loc))
    | Some (OpenT (_, id)) ->
      if not (Loc_env.is_readable env kind loc) then
        Some Error_message.(EInternal (loc, ReadOfUnreachedTvar kind))
      else if not (Env_api.EnvSet.mem (kind, loc) under_resolution) then
        match Context.find_graph cx id with
        | Type.Constraint.FullyResolved _ -> None
        | _ -> Some Error_message.(EInternal (loc, ReadOfUnresolvedTvar kind))
      else
        None
    | Some t -> assert_false ("Expect only OpenTs in env, instead we have " ^ Debug_js.dump_t cx t))

let check_readable cx kind loc =
  enforced_env_read_error_opt cx kind loc |> Base.Option.iter ~f:(Flow_js_utils.add_output cx)

let checked_find_loc_env_write cx kind loc =
  let get_t () =
    let env = Context.environment cx in
    t_option_value_exn cx loc (Loc_env.find_write env kind loc)
  in
  enforced_env_read_error_opt cx kind loc |> Base.Option.iter ~f:(Flow_js_utils.add_output cx);
  get_t ()

let checked_find_loc_env_write_opt cx kind loc =
  let get_t () =
    let env = Context.environment cx in
    Loc_env.find_write env kind loc
  in
  enforced_env_read_error_opt cx kind loc |> Base.Option.iter ~f:(Flow_js_utils.add_output cx);
  get_t ()

let find_var_opt { Env_api.env_values; _ } loc =
  match ALocMap.find_opt loc env_values with
  | Some x -> Ok x
  | None -> Error loc

let find_refi { Env_api.refinement_of_id; _ } = refinement_of_id

let find_providers { Env_api.providers; _ } loc =
  Env_api.Provider_api.providers_of_def providers loc
  |> Base.Option.value_map ~f:(fun { Env_api.Provider_api.providers; _ } -> providers) ~default:[]
  |> Base.List.map ~f:(fun { Env_api.Provider_api.reason; _ } -> Reason.loc_of_reason reason)

let is_def_loc_annotated { Env_api.providers; _ } loc =
  let providers = Env_api.Provider_api.providers_of_def providers loc in
  match providers with
  | Some { Env_api.Provider_api.state = Find_providers.AnnotatedVar _; _ } -> true
  | _ -> false

let provider_type_for_def_loc ?(intersect = false) cx env def_loc =
  let { Loc_env.var_info; _ } = env in
  let providers =
    find_providers var_info def_loc
    |> Base.List.filter_map ~f:(fun loc ->
           match checked_find_loc_env_write_opt cx Env_api.OrdinaryNameLoc loc with
           | Some w -> Some w
           | None ->
             (match EnvMap.find_opt_ordinary loc var_info.Env_api.env_entries with
             | None
             | Some Env_api.NonAssigningWrite ->
               None
             | _ ->
               Flow_js_utils.add_output
                 cx
                 Error_message.(
                   EInternal
                     ( loc,
                       EnvInvariant
                         (Env_api.Impossible
                            (spf
                               "Missing provider write at %s for %s"
                               (Reason.string_of_aloc loc)
                               (Reason.string_of_aloc def_loc)
                            )
                         )
                     )
                 );
               None)
       )
  in
  match providers with
  | [] -> MixedT.make (mk_reason (RCustom "no providers") def_loc)
  | [t] -> t
  | t1 :: t2 :: ts when intersect ->
    IntersectionT (mk_reason (RCustom "providers") def_loc, InterRep.make t1 t2 ts)
  | t1 :: t2 :: ts -> UnionT (mk_reason (RCustom "providers") def_loc, UnionRep.make t1 t2 ts)

(*************)
(*  Reading  *)
(*************)

(** Computes the phi type for a node given all its lower bounds
 *  Currently, this just produces a new type variable with the types of
 *  all the incoming writes as lower bounds. In the future, however, we
 *  may want to compute a more specific least upper bound for these writes.
 *)
let phi cx reason ts =
  match ts with
  | [t] -> t
  | _ ->
    let tvar = Tvar.mk cx reason in
    let errs =
      Base.List.concat_map
        ~f:(function
          | Ok t ->
            Flow_js.flow_t cx (t, tvar);
            []
          | Error (t, errs) ->
            Flow_js.flow_t cx (t, tvar);
            Nel.to_list errs)
        ts
    in
    (match errs with
    | [] -> Ok tvar
    | hd :: tl -> Error (tvar, (hd, tl)))

let rec predicate_of_refinement cx =
  Env_api.Refi.(
    function
    | AndR (r1, r2) -> AndP (predicate_of_refinement cx r1, predicate_of_refinement cx r2)
    | OrR (r1, r2) -> OrP (predicate_of_refinement cx r1, predicate_of_refinement cx r2)
    | NotR r -> NotP (predicate_of_refinement cx r)
    | TruthyR -> ExistsP
    | NullR -> NullP
    | UndefinedR -> VoidP
    | MaybeR -> MaybeP
    | InstanceOfR (loc, _) ->
      (* Instanceof refinements store the loc they check against, which is a read in the env *)
      let reason = mk_reason (RCustom "RHS of `instanceof` operator") loc in
      Debug_js.Verbose.print_if_verbose_lazy
        cx
        ( lazy
          [spf "reading from location %s (in instanceof refinement)" (Reason.string_of_aloc loc)]
          );
      let t = checked_find_loc_env_write cx Env_api.ExpressionLoc loc in
      Flow_js.flow cx (t, AssertInstanceofRHST reason);
      LeftP (InstanceofTest, t)
    | IsArrayR -> ArrP
    | BoolR loc -> BoolP loc
    | FunctionR -> FunP
    | NumberR loc -> NumP loc
    | BigIntR loc -> BigIntP loc
    | ObjectR -> ObjP
    | StringR loc -> StrP loc
    | SymbolR loc -> SymbolP loc
    | SingletonBoolR { loc; sense = _; lit } -> SingletonBoolP (loc, lit)
    | SingletonStrR { loc; sense; lit } -> SingletonStrP (loc, sense, lit)
    | SingletonNumR { loc; sense; lit } -> SingletonNumP (loc, sense, lit)
    | SingletonBigIntR { loc; sense; lit } -> SingletonBigIntP (loc, sense, lit)
    | SentinelR (prop, loc) ->
      Debug_js.Verbose.print_if_verbose_lazy
        cx
        (lazy [spf "reading from location %s (in sentinel refinement)" (Reason.string_of_aloc loc)]);
      let other_t = checked_find_loc_env_write cx Env_api.ExpressionLoc loc in
      LeftP (SentinelProp prop, other_t)
    | LatentR { func = (func_loc, _); index; _ } ->
      let call_info = read_pred_func_info_exn cx func_loc in
      LatentP (call_info, index)
    | PropNullishR { propname; loc } ->
      NotP (PropNonMaybeP (propname, mk_reason (RProperty (Some (OrdinaryName propname))) loc))
    | PropExistsR { propname; loc } ->
      PropExistsP (propname, mk_reason (RProperty (Some (OrdinaryName propname))) loc)
  )

and refine cx reason loc refi res =
  Base.Option.value_map
    ~f:(fun predicate ->
      let map_t t =
        let predicate = predicate |> snd |> predicate_of_refinement cx in
        let reason = mk_reason (RRefined (desc_of_reason reason)) loc in
        Tvar.mk_no_wrap_where cx reason (fun tvar ->
            Flow_js.flow cx (t, PredicateT (predicate, tvar))
        )
      in
      match res with
      | Ok t -> Ok (map_t t)
      | Error (t, errs) -> Error (map_t t, errs))
    ~default:res
    refi

and res_of_state ~lookup_mode cx env loc reason write_locs val_id refi =
  let { Loc_env.var_info; _ } = env in
  let find_write_exn kind reason =
    let loc = Reason.loc_of_reason reason in
    checked_find_loc_env_write cx kind loc
  in
  let rec res_of_state states val_id refi =
    let t =
      lazy
        (Base.List.map
           ~f:(fun entry ->
             match (entry, lookup_mode) with
             | (Env_api.Undefined reason, _)
             | (Env_api.Uninitialized reason, _) ->
               Ok Type.(VoidT.make reason)
             | (Env_api.Number reason, _) -> Ok Type.(NumT.make reason)
             | (Env_api.DeclaredFunction loc, _) ->
               Ok (provider_type_for_def_loc ~intersect:true cx env loc)
             | (Env_api.Undeclared (_name, def_loc), ForType) ->
               Ok (checked_find_loc_env_write cx Env_api.OrdinaryNameLoc def_loc)
             | (Env_api.Undeclared (name, def_loc), (ForValue | ForTypeof)) ->
               Error
                 ( Type.(AnyT.make (AnyError None) reason),
                   Nel.one (Env_api.ReferencedBeforeDeclaration { name; def_loc })
                 )
             | (Env_api.With_ALoc.EmptyArray { reason; arr_providers = _ }, _)
             | (Env_api.With_ALoc.Write reason, _) ->
               Debug_js.Verbose.print_if_verbose_lazy
                 cx
                 ( lazy
                   [
                     spf
                       "reading %s from location %s"
                       (Reason.string_of_aloc loc)
                       (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                   ]
                   );
               Ok (find_write_exn Env_api.OrdinaryNameLoc reason)
             | (Env_api.With_ALoc.IllegalWrite reason, _) ->
               Debug_js.Verbose.print_if_verbose_lazy
                 cx
                 ( lazy
                   [
                     spf
                       "reading %s from illegal write location %s"
                       (Reason.string_of_aloc loc)
                       (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                   ]
                   );
               Ok Type.(AnyT.make (AnyError None) reason)
             | (Env_api.With_ALoc.Refinement { refinement_id; writes; write_id }, _) ->
               find_refi var_info refinement_id |> Base.Option.some |> res_of_state writes write_id
             | (Env_api.With_ALoc.Global name, _) ->
               get_global_value_type cx (Reason.OrdinaryName name) reason
             | (Env_api.With_ALoc.GlobalThis reason, _) -> Ok (ObjProtoT reason)
             | (Env_api.With_ALoc.IllegalThis reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading illegal this(%s) from location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok Type.(AnyT.make (AnyError None) reason)
             | (Env_api.With_ALoc.FunctionThis reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading function this(%s) from location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok (find_write_exn Env_api.FunctionThisLoc reason)
             | (Env_api.With_ALoc.ClassInstanceThis reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading instance this(%s) from location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok (find_write_exn Env_api.ClassInstanceThisLoc reason)
             | (Env_api.With_ALoc.ClassStaticThis reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading static this(%s) from location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok (find_write_exn Env_api.ClassStaticThisLoc reason)
             | (Env_api.With_ALoc.ClassInstanceSuper reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading instance super(%s) from location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok (find_write_exn Env_api.ClassInstanceSuperLoc reason)
             | (Env_api.With_ALoc.ClassStaticSuper reason, _) ->
               Debug_js.Verbose.print_if_verbose
                 cx
                 [
                   spf
                     "reading %s from illegal write location %s"
                     (Reason.string_of_aloc loc)
                     (Reason.loc_of_reason reason |> Reason.string_of_aloc);
                 ];
               Ok (find_write_exn Env_api.ClassStaticSuperLoc reason)
             | (Env_api.With_ALoc.ModuleScoped _, _) -> Ok Type.(AnyT.at AnnotatedAny loc)
             | (Env_api.With_ALoc.Unreachable loc, _) ->
               let reason = mk_reason (RCustom "unreachable value") loc in
               Ok (EmptyT.make reason)
             | (Env_api.With_ALoc.Projection loc, _) ->
               Ok (checked_find_loc_env_write cx Env_api.OrdinaryNameLoc loc))
           states
        |> phi cx reason
        )
    in
    let t =
      match val_id with
      | Some id ->
        if Context.typing_mode cx <> Context.CheckingMode then
          Lazy.force t
        else
          let for_value =
            match lookup_mode with
            | ForValue
            | ForTypeof ->
              true
            | ForType -> false
          in
          (match Context.env_cache_find_opt cx ~for_value id with
          | None ->
            let t = Lazy.force t in
            Context.add_env_cache_entry cx ~for_value id t;
            t
          | Some t -> t)
      | _ -> Lazy.force t
    in
    t |> refine cx reason loc refi
  in
  res_of_state write_locs val_id refi

and type_of_state ~lookup_mode cx env loc reason write_locs val_id refi =
  res_of_state ~lookup_mode cx env loc reason write_locs val_id refi
  |> Flow_js_utils.apply_env_errors cx loc

and read_entry ~lookup_mode cx loc reason =
  let ({ Loc_env.var_info; _ } as env) = Context.environment cx in
  match find_var_opt var_info loc with
  | Error loc -> Error loc
  | Ok { Env_api.def_loc; write_locs; val_kind; name; id } ->
    (match (val_kind, name, def_loc, lookup_mode) with
    | (Some (Env_api.Type { imported }), Some name, Some def_loc, (ForValue | ForTypeof)) ->
      Flow_js.add_output
        cx
        (Error_message.EBindingError
           (Error_message.ETypeInValuePosition { imported; name }, loc, OrdinaryName name, def_loc)
        );
      Ok (AnyT.at (AnyError None) loc)
    | _ -> Ok (type_of_state ~lookup_mode cx env loc reason write_locs id None))

and read_entry_exn ~lookup_mode cx loc reason =
  with_debug_exn cx loc (fun () ->
      match read_entry ~lookup_mode cx loc reason with
      | Error loc -> failwith (Utils_js.spf "LocEnvEntryNotFound %s" (Reason.string_of_aloc loc))
      | Ok x -> x
  )

and read_pred_func_info_exn cx loc =
  let f () = ALocMap.find loc (Context.environment cx).Loc_env.pred_func_map in
  let error () = lazy (unknown_use, loc, AnyT.at (AnyError None) loc, None, []) in
  with_debug_exn_error cx loc ~f ~error

and predicate_refinement_maps cx loc =
  let { Loc_env.var_info; _ } = Context.environment cx in
  let { Env_api.predicate_refinement_maps; _ } = var_info in
  let read_to_predicate ({ Env_api.write_locs; _ }, _, _) =
    let predicates =
      Base.List.filter_map write_locs ~f:(function
          | Env_api.With_ALoc.Refinement { refinement_id; _ } ->
            Some (find_refi var_info refinement_id |> snd |> predicate_of_refinement cx)
          | _ -> None
          )
    in
    predicates
    |> Nel.of_list
    |> Base.Option.map ~f:(fun (p, rest) ->
           Base.List.fold rest ~init:p ~f:(fun acc p -> OrP (acc, p))
       )
  in
  let to_predicate_key_map map =
    map
    |> SMap.elements
    |> Base.List.filter_map ~f:(fun (name, read) ->
           read_to_predicate read |> Base.Option.map ~f:(fun p -> ((OrdinaryName name, []), p))
       )
    |> Key_map.of_list
  in
  match ALocMap.find_opt loc predicate_refinement_maps with
  | None -> None
  | Some (expr_reason, p_map, n_map) ->
    Some (expr_reason, to_predicate_key_map p_map, to_predicate_key_map n_map)

and type_guard_at_return cx reason ~param_loc ~return_loc write_locs =
  let rec is_invalid (acc_result, acc_locs) write_loc =
    match write_loc with
    | Env_api.Write reason when ALoc.equal (Reason.loc_of_reason reason) param_loc ->
      (acc_result, acc_locs)
    | Env_api.Refinement { refinement_id = _; writes; write_id = _ } ->
      Base.List.fold_left ~init:(acc_result, acc_locs) writes ~f:is_invalid
    | Env_api.Write r -> (true, Reason.loc_of_reason r :: acc_locs)
    | _ ->
      (* These cases are unlikely. Not all of them provide an error location.
       * Just record the error without loc. *)
      (true, acc_locs)
  in
  let (is_invalid, invalid_writes) =
    Base.List.fold_left write_locs ~init:(false, []) ~f:is_invalid
  in
  let env = Context.environment cx in
  if is_invalid then
    Error invalid_writes
  else
    let lookup_mode = LookupMode.ForValue in
    Ok (type_of_state ~lookup_mode cx env return_loc reason write_locs None None)

let ref_entry_exn ~lookup_mode cx loc reason =
  let t = read_entry_exn ~lookup_mode cx loc reason in
  Flow_js.reposition cx loc t

let find_write cx kind reason =
  let loc = Reason.loc_of_reason reason in
  match checked_find_loc_env_write_opt cx kind loc with
  | Some t -> t
  | None -> Tvar.mk cx reason

let get_module_exports cx loc =
  let env = Context.environment cx in
  t_option_value_exn cx loc (Loc_env.find_write env Env_api.CJSModuleExportsLoc loc)

let get_refinement cx key loc =
  let reason = mk_reason (Key.reason_desc key) loc in
  match read_entry ~lookup_mode:ForValue cx loc reason with
  | Ok x -> Some (Flow_js.reposition cx loc x)
  | Error _ -> None

let get_var ?(lookup_mode = ForValue) cx name loc =
  ignore lookup_mode;
  let name = OrdinaryName name in
  read_entry_exn ~lookup_mode cx loc (mk_reason (RIdentifier name) loc)

let query_var ?(lookup_mode = ForValue) cx name ?desc loc =
  let desc =
    match desc with
    | Some desc -> desc
    | None -> RIdentifier name
  in
  read_entry_exn ~lookup_mode cx loc (mk_reason desc loc)

let intrinsic_ref cx ?desc name loc =
  let desc =
    match desc with
    | Some desc -> desc
    | None -> RIdentifier name
  in
  let reason = mk_reason desc loc in
  let read =
    let ({ Loc_env.var_info; _ } as env) = Context.environment cx in
    match find_var_opt var_info loc with
    | Error loc -> Error loc
    | Ok { Env_api.def_loc; write_locs; val_kind; name; id } ->
      (match (val_kind, name, def_loc) with
      | (Some (Env_api.Type { imported = _ }), Some _, Some _)
      | (_, _, None) ->
        Error loc
      | (_, _, Some def_loc) ->
        Ok (res_of_state ~lookup_mode:ForValue cx env loc reason write_locs id None, def_loc))
  in
  match read with
  | Error _ -> None
  | Ok ((Ok x | Error (x, _)), def_loc) -> Some (Flow_js.reposition cx loc x, def_loc)

let var_ref ?(lookup_mode = ForValue) cx ?desc name loc =
  let t = query_var ~lookup_mode cx name ?desc loc in
  Flow_js.reposition cx loc t

let read_class_self_type cx loc =
  match checked_find_loc_env_write_opt cx Env_api.ClassSelfLoc loc with
  | Some t -> t
  | None -> Tvar.mk cx (mk_reason (RCustom "unreachable") loc)

let is_global_var cx loc =
  let { Loc_env.var_info; _ } = Context.environment cx in
  match find_var_opt var_info loc with
  | Ok read -> Env_api.With_ALoc.is_global_var read
  | Error _ -> false

let local_scope_entry_exists cx loc = not (is_global_var cx loc)

let get_var_declared_type ?(lookup_mode = ForValue) ?(is_declared_function = false) cx name loc =
  match (name, lookup_mode) with
  | ((OrdinaryName _ | InternalModuleName _), ForType)
  | (InternalModuleName _, ForValue) ->
    (match checked_find_loc_env_write_opt cx Env_api.OrdinaryNameLoc loc with
    | Some t -> t
    | None ->
      Flow_js_utils.add_output cx (Error_message.EInternal (loc, Error_message.MissingEnvWrite loc));
      Type.(AnyT.at (AnyError None) loc))
  | _ ->
    let env = Context.environment cx in
    provider_type_for_def_loc cx env ~intersect:is_declared_function loc

let constraining_type ~default cx loc =
  let { Loc_env.var_info; _ } = Context.environment cx in
  match EnvMap.find_opt_ordinary loc var_info.Env_api.env_entries with
  | Some Env_api.NonAssigningWrite -> default
  | _ ->
    let providers =
      find_providers var_info loc
      |> Base.List.map ~f:(fun loc -> checked_find_loc_env_write_opt cx Env_api.OrdinaryNameLoc loc)
      |> Base.Option.all
    in
    (match providers with
    | None
    | Some [] ->
      default
    | Some [t] -> t
    | Some (t1 :: t2 :: ts) -> UnionT (mk_reason (RCustom "providers") loc, UnionRep.make t1 t2 ts))

(*************)
(*  Writing  *)
(*************)

(* Unifies `t` with the entry in the loc_env's map. This allows it to be looked up for Write
 * entries reported by the name_resolver as well as providers for the provider analysis *)
let unify_write_entry cx ~use_op t def_loc_type loc =
  Debug_js.Verbose.print_if_verbose
    cx
    [spf "writing to %s %s" (Env_api.show_def_loc_type def_loc_type) (Reason.string_of_aloc loc)];
  match checked_find_loc_env_write_opt cx def_loc_type loc with
  | None ->
    (* If we don't see a spot for this write, it's because it's never read from. *)
    ()
  | Some w -> Flow_js.unify cx ~use_op w t

(* Subtypes the given type against the providers for a def loc. Should be used on assignments to
 * non-import value bindings *)
let subtype_against_providers cx ~use_op ?potential_global_name t loc =
  let ({ Loc_env.var_info = { Env_api.providers; scopes; _ } as var_info; _ } as env) =
    Context.environment cx
  in
  (* We only perform a subtyping check if this is an assigning write. We call
   * writes to immutable bindings non-assigning writes. For example:
   * const x: number = 3;
   * x = 'string';
   *
   * Since the x = 'string' doesn't actually assign a value to x, we should
   * not perform a subtyping check and a second error saying string is incompatible
   * with number. We should only emit an error saying that a const cannot be reassigned. *)
  match EnvMap.find_opt_ordinary loc var_info.Env_api.env_entries with
  | Some Env_api.NonAssigningWrite -> ()
  | Some (Env_api.GlobalWrite _) ->
    if is_provider cx loc then
      Base.Option.iter potential_global_name ~f:(fun name ->
          let name = Reason.OrdinaryName name in
          let (_ : Type.t) =
            get_global_value_type cx name (mk_reason (RIdentifier name) loc)
            |> Flow_js_utils.apply_env_errors cx loc
          in
          ()
      )
  | _ ->
    if not (is_provider cx loc) then
      let general = provider_type_for_def_loc cx env loc in
      if is_def_loc_annotated var_info loc then
        Flow_js.flow cx (t, UseT (use_op, general))
      else
        let use_op =
          match Scope_api.With_ALoc.(def_of_use_opt scopes loc) with
          | Some { Scope_api.With_ALoc.Def.locs = (declaration, _); actual_name = name; _ } ->
            let provider_locs =
              Base.Option.value_map
                ~f:(fun { Env_api.Provider_api.providers; _ } -> providers)
                ~default:[]
                (Env_api.Provider_api.providers_of_def providers loc)
            in
            Frame
              ( ConstrainedAssignment
                  {
                    name;
                    declaration;
                    providers =
                      Base.List.map
                        ~f:(fun { Env_api.Provider_api.reason; _ } -> loc_of_reason reason)
                        provider_locs;
                    array = false;
                  },
                use_op
              )
          | None -> use_op
        in
        Context.add_constrained_write cx (t, use_op, general)

let resolve_env_entry ~use_op ~update_reason cx t kind loc =
  unify_write_entry cx ~use_op t kind loc;
  let env = Context.environment cx in
  let env =
    if update_reason then
      Loc_env.update_reason env kind loc (TypeUtil.reason_of_t t)
    else
      env
  in
  Context.set_environment cx env

let subtype_entry cx ~use_op t loc =
  let env = Context.environment cx in
  match checked_find_loc_env_write_opt cx Env_api.OrdinaryNameLoc loc with
  | None ->
    (* If we don't see a spot for this write it is because the annotated
     * binding being looked up here is one that caused a redeclaration
     * error *)
    assert (
      EnvMap.find_opt_ordinary loc env.Loc_env.var_info.Env_api.env_entries
      = Some Env_api.NonAssigningWrite
    )
  | Some w -> Flow_js.flow cx (t, UseT (use_op, w))

(* init_entry is called on variable declarations (not assignments), and `t`
   is the RHS type. If the variable is annotated, we just need to check t against
   its type; but if it's not annotated, the RHS t becomes the variable's type. *)
let init_entry cx ~use_op t loc =
  let { Loc_env.var_info; _ } = Context.environment cx in
  if is_def_loc_annotated var_info loc then subtype_entry cx ~use_op t loc

let set_var cx ~use_op name t loc =
  subtype_against_providers cx ~use_op ~potential_global_name:name t loc

let set_module_exports cx t =
  let env = Context.environment cx in
  Base.Option.iter
    env.Loc_env.declare_module_exports_write_loc
    ~f:(unify_write_entry cx ~use_op:unknown_use t Env_api.CJSModuleExportsLoc)

let bind_function_param cx t loc =
  unify_write_entry cx ~use_op:Type.unknown_use t Env_api.FunctionParamLoc loc

let bind_function_this cx t loc =
  if Context.typing_mode cx = Context.CheckingMode then
    unify_write_entry cx ~use_op:Type.unknown_use t Env_api.FunctionThisLoc loc

let bind_class_instance_this cx t loc =
  unify_write_entry cx ~use_op:Type.unknown_use t Env_api.ClassInstanceThisLoc loc

let bind_class_static_this cx t loc =
  unify_write_entry cx ~use_op:Type.unknown_use t Env_api.ClassStaticThisLoc loc

let bind_class_instance_super cx t loc =
  unify_write_entry cx ~use_op:Type.unknown_use t Env_api.ClassInstanceSuperLoc loc

let bind_class_static_super cx t loc =
  unify_write_entry cx ~use_op:Type.unknown_use t Env_api.ClassStaticSuperLoc loc

let init_var cx ~use_op t loc = init_entry cx ~use_op t loc

let init_let cx ~use_op t loc = init_entry cx ~use_op t loc

let init_implicit_let cx ~use_op t loc = init_entry cx ~use_op t loc

let init_const cx ~use_op t loc = init_entry cx ~use_op t loc

let init_implicit_const cx ~use_op t loc = init_entry cx ~use_op t loc

let read_declared_type cx reason loc =
  Tvar.mk_where cx reason (fun t ->
      unify_write_entry cx ~use_op:unknown_use t Env_api.OrdinaryNameLoc loc
  )

(************************)
(* Variable Declaration *)
(************************)
let init_env cx toplevel_scope_kind =
  let ({ Loc_env.var_info; _ } as env) = Context.environment cx in
  let initialize_entry def_loc_type loc env_entry env =
    let env' =
      match env_entry with
      | Env_api.AssigningWrite reason
      | Env_api.GlobalWrite reason ->
        let t = Tvar.mk cx reason in
        Loc_env.initialize env def_loc_type loc t
      | Env_api.NonAssigningWrite ->
        if is_provider cx loc then
          (* If an illegal write is considered as a provider, we still need to give it a
             slot to prevent crashing in code that queries provider types. *)
          let reason = mk_reason (RCustom "non-assigning provider") loc in
          let t =
            Tvar.mk_no_wrap_where cx reason (fun (_, id) ->
                Flow_js.resolve_id cx id (AnyT.error reason)
            )
          in
          Loc_env.initialize env def_loc_type loc t
        else
          env
    in
    Context.set_environment cx env';
    env'
  in

  let env =
    EnvMap.fold
      (fun (def_loc_type, loc) env_entry env ->
        (* Array providers must be initialized first *)
        match def_loc_type with
        | Env_api.ArrayProviderLoc -> initialize_entry def_loc_type loc env_entry env
        | _ -> env)
      var_info.Env_api.env_entries
      env
    |> EnvMap.fold
         (fun (def_loc_type, loc) env_entry env ->
           match def_loc_type with
           | Env_api.ArrayProviderLoc -> env
           | _ -> initialize_entry def_loc_type loc env_entry env)
         var_info.Env_api.env_entries
  in
  let env =
    { env with Loc_env.scope_kind = toplevel_scope_kind; readable = Env_api.EnvSet.empty }
  in
  Context.set_environment cx env

let discriminant_after_negated_cases cx switch_loc refinement_key_opt =
  let reason_desc =
    match refinement_key_opt with
    | None -> RCustom "discriminant of switch"
    | Some refinement_key -> Key.reason_desc refinement_key
  in
  match read_entry ~lookup_mode:ForValue cx switch_loc (mk_reason reason_desc switch_loc) with
  | Ok t -> Some t
  | Error _ -> None

let get_next cx loc =
  let name = InternalName "next" in
  read_entry_exn ~lookup_mode:ForValue cx loc (mk_reason (RIdentifier name) loc)
