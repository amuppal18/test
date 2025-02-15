(* -------------------------------------------------------------------------- *
 *                     Vellvm - the Verified LLVM project                     *
 *                                                                            *
 *     Copyright (c) 2017 Steve Zdancewic <stevez@cis.upenn.edu>              *
 *                                                                            *
 *   This file is distributed under the terms of the GNU General Public       *
 *   License as published by the Free Software Foundation, either version     *
 *   3 of the License, or (at your option) any later version.                 *
 ---------------------------------------------------------------------------- *)

(** * Plugging the pieces together: executable and propositional semantics for Vellvm *)

(* begin hide *)
From Coq Require Import
     Ensembles List String.

From ITree Require Import
     ITree
     Events.State.

From ExtLib Require Import
     Structures.Monads
     Data.Map.FMapAList.

From Vellvm Require Import
     AstLib
     TransformTypes
     DynamicTypes
     LLVMEvents
     Denotation
     Environment
     Handlers.Global
     Handlers.Local
     Handlers.Stack
     Handlers.Memory
     Handlers.Intrinsics
     Handlers.UndefinedBehaviour
     LLVMAst
     Util
     Error
     Handlers.Pick
     PropT.

Import MonadNotation.
Import ListNotations.
Import Monads.

Module IO := LLVMEvents.Make(Memory.A).
Module M := Memory.Make(IO).
Module D := Denotation(Memory.A)(IO).
Module INT := Intrinsics.Make(Memory.A)(IO).
Module P := Pick.Make(Memory.A)(IO).
Import IO.
Export IO.DV.

Module TopLevelEnv <: Environment.
  Definition local_env  := FMapAList.alist raw_id uvalue.
  Definition global_env := FMapAList.alist raw_id dvalue.
  Definition memory     := M.memory_stack.
  Definition stack      := @stack (list (raw_id * uvalue)).

(* Definition local_env  := FMapAList.alist raw_id uvalue. *)
(* Definition global_env := FMapAList.alist raw_id dvalue. *)


Open Scope string_scope.

(* end hide *)

(**
   This file ties things together to concretely defines the semantics of a [Vellvm]
   program. It covers two main tasks to do so: to initialize the memory, and to
   chain together the successive interpreters.
   As such, the raw denotation of a [Vellvm] program in terms of an [itree] is
   progressively stripped out of its events.
   We provide two such chains of interpretations: a model, that handles the
   internal non-determinism due to under-defined values into the non-determinism
   monad; and an executable one, that arbitrarily interpret under-defined values
   by setting its bits to 0.
 *)

(** Initialization
    The initialization phase allocates and initializes globals,
    and allocates function pointers.
    This initialization phase is internalized in [Vellvm], it is
    an [itree] as any other.
 *)

Definition allocate_global (g:global dtyp) : itree L0 unit :=
  (vis (Alloca (g_typ _ g)) (fun v => trigger (GlobalWrite (g_ident _ g) v))).

Definition allocate_globals (gs:list (global dtyp)) : itree L0 unit :=
  map_monad_ allocate_global gs.

(* Who is in charge of allocating the addresses for external functions declared in this mcfg? *)
Definition allocate_declaration (d:declaration dtyp) : itree L0 unit :=
  (* SAZ TODO:  Don't allocate pointers for LLVM intrinsics declarations *)
    vis (Alloca DTYPE_Pointer) (fun v => trigger (GlobalWrite (dc_name _ d) v)).

Definition allocate_declarations (ds:list (declaration dtyp)) : itree L0 unit :=
  map_monad_ allocate_declaration ds.

Definition initialize_global (g:global dtyp) : itree exp_E unit :=
  let dt := (g_typ _ g) in
  a <- trigger (GlobalRead (g_ident _ g));;
  uv <- match (g_exp _ g) with
       | None => ret (UVALUE_Undef dt)
       | Some e => D.denote_exp (Some dt) e
       end ;;
  (* CB TODO: Do we need pick here? *)
  dv <- trigger (pick uv True) ;;
  trigger (Store a dv).

Definition initialize_globals (gs:list (global dtyp)): itree exp_E unit :=
  map_monad_ initialize_global gs.

Definition build_global_environment (CFG : CFG.mcfg dtyp) : itree L0 unit :=
  allocate_globals (m_globals _ _ CFG) ;;
  allocate_declarations ((m_declarations _ _ CFG) ++ (List.map (df_prototype _ _) (m_definitions _ _ CFG)));;
  translate _exp_E_to_L0 (initialize_globals (m_globals _ _ CFG)).

(** Local environment implementation
    The map-based handlers are defined parameterized over a domain of key and value.
    We now pick concrete such domain.
    Note that while local environments may store under-defined values,
    global environments are statically guaranteed to store [dvalue]s.
 *)
Definition function_env := FMapAList.alist dvalue D.function_denotation.

(**
   Denotes a function and returns its pointer.
 *)

Definition address_one_function (df : definition dtyp (CFG.cfg dtyp)) : itree L0 (dvalue * D.function_denotation) :=
  let fid := (dc_name _ (df_prototype _ _ df)) in
  fv <- trigger (GlobalRead fid) ;;
  ret (fv, D.denote_function df).

(* (for now) assume that [main (i64 argc, i8** argv)]
    pass in 0 and null as the arguments to main
   Note: this isn't compliant with standard C semantics
*)
Definition main_args := [DV.DVALUE_I64 (DynamicValues.Int64.zero);
                         DV.DVALUE_Addr (Memory.A.null)
                        ].

(**
   Transformation and normalization of types.
*)
Definition eval_typ (CFG:CFG.mcfg typ) (t:typ) : dtyp :=
      TypeUtil.normalize_type_dtyp (m_type_defs _ _ CFG) t.

Definition normalize_types (CFG:(CFG.mcfg typ)) : (CFG.mcfg dtyp) :=
  TransformTypes.fmap_mcfg _ _ (eval_typ CFG) CFG.

(**
   We are now ready to define our semantics. Guided by the events and handlers,
   we work in layers: the first layer is defined as the uninterpreted [itree]
   resulting from the denotation of the LLVM program. Each successive handler
   then transform a tree at layer n to a tree at layer (n+1).
 *)
(**
   In order to limit bloated type signature, we name the successive return types.
*)

Notation res_L0 := uvalue (* (only parsing) *).
Notation res_L1 := (global_env * res_L0)%type (* (only parsing) *).
Notation res_L2 := (local_env * stack * res_L1)%type (* (only parsing) *).
Notation res_L3 := (memory * res_L2)%type (* (only parsing) *).
Notation res_L4 := (memory * (local_env * stack * (global_env * dvalue)))%type (* (only parsing) *).

(* Initialization and denotation of a Vellvm program *)
Definition build_L0 (mcfg : CFG.mcfg dtyp) : itree L0 res_L0 :=
  build_global_environment mcfg ;;
  'defns <- map_monad address_one_function (m_definitions _ _ mcfg) ;;
  'addr <- trigger (GlobalRead (Name "main")) ;;
  D.denote_mcfg defns DTYPE_Void addr main_args.

(* Interpretation of the global environment *)
(* TODO YZ: Why do we need to provide this instance explicitly? *)
Definition build_L1 (trace : itree L0 res_L0) : itree L1 res_L1 :=
             @interp_global _ _ _ _ show_raw_id _ _ _ _ _ trace [].

(* Interpretation of the local environment: map and stack *)
Definition build_L2 (trace : itree L1 res_L1) : itree L2 res_L2 :=
  interp_local_stack (@handle_local raw_id uvalue _ _ show_raw_id _ _) trace ([], []).

(* Interpretation of the memory *)
Definition build_L3 (trace : itree L2 res_L2) : itree L3 res_L3 :=
  M.interp_memory trace (M.empty, [[]]).

(* Interpretation of under-defined values as 0 *)
(* YZ: I'm not fully convinced by this, this translate for the return value is awkward. *)
Definition build_L4 (trace : itree L3 res_L3) : itree L4 res_L4 :=
  '(m, (env, (genv, uv))) <- (P.interp_undef trace);;
   dv <- translate _failure_UB_to_L4 (P.concretize_uvalue uv);;
   ret (m, (env, (genv, dv))).

(* Interpretation of under-defined values as 0 *)
Definition model_L4 (trace : itree L3 res_L3) : PropT (itree L4) res_L3 :=
  P.model_undef trace.

Definition build_L5 (trace : itree L4 res_L4) : itree L5 res_L4 :=
  interp_UB trace.

Definition model_L5 (trace : PropT (itree L4) res_L3) : PropT (itree L5) res_L3 :=
  model_UB trace.

End TopLevelEnv.

Import TopLevelEnv.

(* YZ TODO: Rename traces better *)
Definition interpreter (prog: list (toplevel_entity typ (list (block typ)))) : itree L5 res_L4 :=
  let scfg := Vellvm.AstLib.modul_of_toplevel_entities _ prog in

  match CFG.mcfg_of_modul _ scfg with
  | Some ucfg =>

    let mcfg := normalize_types ucfg in

    let L0_trace          := build_L0 mcfg in
    let L0_trace'         := INT.interpret_intrinsics L0_trace in
    let L1_trace          := build_L1 L0_trace' in
    let L2_trace          := build_L2 L1_trace in
    let L3_Trace          := build_L3 L2_trace in
    let L4_Trace          := build_L4 L3_Trace in
    let L5_Trace          := build_L5 L4_Trace in
    L5_Trace

  | None => raise "Ill-formed program: mcfg_of_modul failed."
  end.

(* YZ TODO: Rename traces better *)
Definition model (prog: list (toplevel_entity typ (list (block typ)))) :
  PropT (itree L5) res_L3 :=
  let scfg := Vellvm.AstLib.modul_of_toplevel_entities _ prog in

  match  CFG.mcfg_of_modul _ scfg with
  | Some ucfg =>
    let mcfg := normalize_types ucfg in

    let L0_trace        := build_L0 mcfg in
    let L0_trace'       := INT.interpret_intrinsics L0_trace in
    let L1_trace        := build_L1 L0_trace' in
    let L2_trace        := build_L2 L1_trace in
    let L3_trace        := build_L3 L2_trace in
    let L4_trace        := model_L4 L3_trace in
    let L5_trace        := model_L5 L4_trace in
    L5_trace

  | None => lift (raise "Ill-formed program: mcfg_of_modul failed.")
  end.

(*
Lemma interpreter_satisfies_model: forall prog,
    model prog (ITree.map (fun '(m, (env, (genv, uv))) => (m,(env,(genv, dvalue_to_uvalue uv)))) (interpreter prog)).
Proof.
  intros prog.
  unfold model. unfold interpreter.
  destruct (CFG.mcfg_of_modul typ (modul_of_toplevel_entities typ prog)) eqn:Hmodul.
  - admit.
  - simpl. unfold I

    Print raise.
    Print ITree.map.
Qed.
*)

