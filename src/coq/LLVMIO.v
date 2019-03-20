(* -------------------------------------------------------------------------- *
 *                     Vellvm - the Verified LLVM project                     *
 *                                                                            *
 *     Copyright (c) 2017 Steve Zdancewic <stevez@cis.upenn.edu>              *
 *                                                                            *
 *   This file is distributed under the terms of the GNU General Public       *
 *   License as published by the Free Software Foundation, either version     *
 *   3 of the License, or (at your option) any later version.                 *
 ---------------------------------------------------------------------------- *)

From Coq Require Import
     ZArith
     List
     String
     Setoid
     Morphisms
     Omega
     Classes.RelationClasses.

From ExtLib Require Import
     Core.RelDec
     Programming.Eqv
     Programming.Show
     Structures.Monads.

From ITree Require Import 
     ITree
     Effects.Std.

From Vellvm Require Import
     Util
     LLVMAst
     MemoryAddress
     DynamicValues
     Error.

From Paco Require Import
     paco.

Set Implicit Arguments.
Set Contextual Implicit.

Inductive dtyp : Set :=
| DTYPE_I (sz:Z)
| DTYPE_Pointer
| DTYPE_Void
| DTYPE_Half
| DTYPE_Float
| DTYPE_Double
| DTYPE_X86_fp80
| DTYPE_Fp128
| DTYPE_Ppc_fp128
| DTYPE_Metadata
| DTYPE_X86_mmx
| DTYPE_Array (sz:Z) (t:dtyp)
| DTYPE_Struct (fields:list dtyp)
| DTYPE_Packed_struct (fields:list dtyp)
| DTYPE_Opaque
| DTYPE_Vector (sz:Z) (t:dtyp)     (* t must be integer, floating point, or pointer type *)
.

Section hiding_notation.
  Import ShowNotation.
  Local Open Scope show_scope.

  Fixpoint show_dtyp' (dt:dtyp) := 
    match dt with
    | DTYPE_I sz     => ("i" << show sz)
    | DTYPE_Pointer  => "ptr"
    | DTYPE_Void     => "dvoid"
    | DTYPE_Half     => "half"
    | DTYPE_Float    => "float"
    | DTYPE_Double   => "double"
    | DTYPE_X86_fp80 => "x86_fp80"
    | DTYPE_Fp128    => "fp128"
    | DTYPE_Ppc_fp128 => "ppc_fp128"
    | DTYPE_Metadata  => "metadata"
    | DTYPE_X86_mmx   => "x86_mmx" 
    | DTYPE_Array sz t
          => ("[" << show sz << " x " << (show_dtyp' t) << "]")
    | DTYPE_Struct fields
          => ("{" << iter_show (List.map (fun x => (show_dtyp' x) << ",") fields) << "}")
    | DTYPE_Packed_struct fields
      => ("packed{" << iter_show (List.map (fun x => (show_dtyp' x) << ",") fields) << "}")
    | DTYPE_Opaque => "opaque"
    | DTYPE_Vector sz t
      => ("<" << show sz << " x " << (show_dtyp' t) << ">")  (* TODO: right notation? *)
    end%string.

  Global Instance show_dtyp : Show dtyp := show_dtyp'.
End hiding_notation.


Module Type LLVM_INTERACTIONS (ADDR : MemoryAddress.ADDRESS).

Global Instance eq_dec_addr : RelDec (@eq ADDR.addr) := RelDec_from_dec _ ADDR.addr_dec.
Global Instance Eqv_addr : Eqv ADDR.addr := (@eq ADDR.addr).  

(* The set of dynamic types manipulated by an LLVM program.  Mostly
   isomorphic to LLVMAst.typ but
     - pointers have no further detail
     - identified types are not allowed
   Questions:
     - What to do with Opaque?
*)

Module DV := DynamicValues.DVALUE(ADDR).
Export DV.

Inductive Void :=.

(* YZ TODO: Change names to better ones *)
Inductive Locals : Type -> Type :=
| LocalWrite (id: raw_id) (dv: dvalue): Locals unit
| LocalRead  (id: raw_id): Locals dvalue.


(* IO Interactions for the LLVM IR *)
Inductive IO : Type -> Type :=
| Alloca : forall (t:dtyp), (IO dvalue)
| Load   : forall (t:dtyp) (a:dvalue), (IO dvalue)
| Store  : forall (a:dvalue) (v:dvalue), (IO unit)
| GEP    : forall (t:dtyp) (v:dvalue) (vs:list dvalue), (IO dvalue)
| ItoP   : forall (i:dvalue), (IO dvalue)
| PtoI   : forall (a:dvalue), (IO dvalue)
| Call   : forall (t:dtyp) (f:string) (args:list dvalue), (IO dvalue)

.

(* Trace of events generated by a computation. *)
Definition LLVM E := itree (Locals +' IO +' E).
Hint Unfold LLVM.

(* Trace Utilities ---------------------------------------------------------- *)

(* Debug is identical to the "Trace" effect from the itrees library,
   but debug is probably a less confusing name for us. *)
Variant debugE : Type -> Type :=
| Debug : string -> debugE unit.

Definition debug {E} `{debugE -< E} (msg : string) : itree E unit :=
  lift (Debug msg).

Definition debug_hom {E} (R : Type) (e : debugE R) : itree E R :=
  match e with
  | Debug _ => Ret tt
  end.

Definition into_debug {E F} (h : E ~> LLVM F) : Locals +' IO +' (F +' E) ~> LLVM F :=
  fun x e =>
    match e with
    | inr1 (inr1 (inr1 e)) => h _ e
    | inr1 (inr1 (inl1 e)) => vis (inr1 (inl1 e)) (fun x => Ret x)
    | inr1 (inl1 e) => vis e (fun x => Ret x)
    | inl1 e => vis e (fun x => Ret x)
    end.

Definition ignore_debug {E} : LLVM (E +' debugE) ~> LLVM E :=
  interp (into_debug debug_hom).

Definition lift_err {A B} (f : A -> LLVM (failureE +' debugE) B) (m:err A) : LLVM (failureE +' debugE) B :=
  match m with
  | inl x => fail x
  | inr x => f x
  end.
  

Notation "'do' x <- m ;; f" := (lift_err (fun x => f) m)
                                (at level 100, x ident, m at next level, right associativity).


Definition raise_LLVM {E} := @fail (Locals +' IO +' (failureE +' E)) _.
CoFixpoint catch_LLVM {E} {X} (f:string -> LLVM (failureE +' E) X) (t : LLVM (failureE +' E) X) : LLVM (failureE +' E) X :=
  match (observe t) with
  | RetF x => Ret x
  | TauF t => Tau (catch_LLVM f t)
  | VisF _ (inr1 (inr1 (inl1 (Fail s)))) k => f s
  | VisF _ (inr1 (inr1 (inr1 e))) k => vis (inr1 (inr1 e)) (fun x => catch_LLVM f (k x))
  | VisF _ e k => Vis e (fun x => catch_LLVM f (k x))
  end.

Global Instance monad_exc_LLVM : (MonadExc string (LLVM (failureE +' debugE))) := {
  raise := raise_LLVM ;
  catch := fun T m f => catch_LLVM f m ;
}.                                                              


End LLVM_INTERACTIONS.

  
Module Make(ADDR : MemoryAddress.ADDRESS) <: LLVM_INTERACTIONS(ADDR).
Include LLVM_INTERACTIONS(ADDR).
End Make.
