(* -------------------------------------------------------------------------- *
 *                     Vellvm - the Verified LLVM project                     *
 *                                                                            *
 *     Copyright (c) 2017 Dmitri Garbuzov <dmitri@sease.upenn.edu>            *
 *     Copyright (c) 2017 Steve Zdancewic <stevez@cis.upenn.edu>              *
 *                                                                            *
 *   This file is distributed under the terms of the GNU General Public       *
 *   License as published by the Free Software Foundation, either version     *
b *   3 of the License, or (at your option) any later version.                 *
 ---------------------------------------------------------------------------- *)

From Coq Require Import
     List
     Omega
     RelationClasses.
Import ListNotations.

Set Implicit Arguments.


(* Monads ------------------------------------------------------------------- *)
(* TODO: Add to ExtLib *)

Require Import ExtLib.Structures.Monads.
Import MonadNotation.
Open Scope monad_scope.

Section monad.
  Variable m : Type -> Type.
  Variable M : Monad m.
  
  Fixpoint monad_fold_right {A B} (f : B -> A -> m B) (l:list A) (b : B) : m B :=
    match l with
    | [] => ret b
    | x::xs => 
      r <- monad_fold_right f xs b ;;
      f r x
    end.

Definition monad_app_fst {A B C} (f : A -> m C) (p:A * B) : m (C * B)%type :=
  let '(x,y) := p in
  z <- f x ;;
  ret (z,y).

Definition monad_app_snd {A B C} (f : B -> m C) (p:A * B) : m (A * C)%type :=
  let '(x,y) := p in
  z <- f y ;;
  ret (x,z).

Definition map_monad {A B} (f:A -> m B) (l:list A) : m (list B) :=
  let fix loop l :=
      match l with
      | [] => ret []
      | a::l' =>
        b <- f a ;;
        bs <- loop l' ;;
        ret (b::bs)  
      end
  in loop l.

Definition map_monad_ {A}
  (f: A -> m unit) (l: list A): m unit :=
  map_monad f l;; ret tt.

End monad.
Arguments monad_fold_right {_ _ _ _}.
Arguments monad_app_fst {_ _ _ _ _}.
Arguments monad_app_snd {_ _ _ _ _}.
Arguments map_monad {_ _ _ _}.
Arguments map_monad_ {_ _ _}.

(* Arithmetic --------------------------------------------------------------- *)


Lemma pred_minus_S : forall m n,
  pred m - n = m - S n.
Proof.
  induction m; auto.
Qed.

(* Relations ---------------------------------------------------------------- *)

Inductive rtc {A} (R:A -> A -> Prop) : A -> A -> Prop :=
| rtc_refl : forall a, rtc R a a
| rtc_step : forall a b c, R a b -> rtc R b c -> rtc R a c.

Instance rtc_Transitive {A} {R} : Transitive (@rtc A R).
Proof.
  unfold Transitive; intros.
  induction H. auto. econstructor; eauto.
Qed.

Arguments rtc [_] _ _ _.

Notation "R ^*" := (rtc R) (at level 1, format "R ^*").


(* Lists -------------------------------------------------------------------- *)

Lemma Forall_map_impl {A B} : forall (P:A -> Prop) (Q:B -> Prop) (f:A -> B),
    (forall a, P a -> Q (f a)) ->
    forall l : list A, Forall P l -> Forall Q (map f l).
Proof.
  intros ? ? ? Himpl ? Hforall.
  rewrite Forall_forall in *. intros ? Hin.
  apply in_map_iff in Hin as [? [? ?]]; subst.
  apply Himpl. apply Hforall. assumption.
Qed.

Fixpoint map2 {A B C:Type} (f:A -> B -> C) (la:list A) (lb:list B) : list C :=
  match la, lb with
    | [], _ | _, [] => []
    | a::la', b::lb' => f a b :: map2 f la' lb'
  end.

Lemma Forall2_impl : forall {A B} (P Q : A -> B -> Prop) l1 l2
  (Himpl : forall a b, P a b -> Q a b), Forall2 P l1 l2 -> Forall2 Q l1 l2.
Proof. intros; induction H; auto. Qed.

Lemma Forall2_impl' : forall {A B} (P Q : A -> B -> Prop) l1 l2
  (Himpl : forall a b, In a l1 -> P a b -> Q a b), 
  Forall2 P l1 l2 -> Forall2 Q l1 l2.
Proof. 
  intros; induction H; auto.
  constructor.
  - apply Himpl; simpl; auto.
  - apply IHForall2. intros; apply Himpl; simpl; auto.
Qed.

Lemma Forall2_length : forall {A B} (P : A -> B -> Prop) l1 l2,
  Forall2 P l1 l2 -> length l1 = length l2.
Proof. intros; induction H; simpl; auto. Qed.


Inductive Forall3 (A B C : Type) (R : A -> B -> C -> Prop) 
  : list A -> list B -> list C -> Prop :=
  | Forall3_nil : Forall3 R [] [] []
  | Forall3_cons : forall x y z l m n,
                   R x y z -> Forall3 R l m n -> Forall3 R (x :: l) (y :: m) (z :: n).

Definition forall2b {A B} (f : A -> B ->bool) (l:list A) (m:list B) : bool :=
  let fix loop l m :=
  match l, m with
  | [], [] => true
  | a::l',b::m' => andb (f a b) (loop l' m')
  | _, _ => false
  end in loop l m.

Definition Nth {A:Type} (l:list A) (n:nat) (a:A) : Prop := nth_error l n = Some a.

Arguments Nth _ _ _ _ /. 

Lemma not_Nth_nil : forall X n (x:X),
  ~ Nth [] n x.
Proof.
  destruct n; discriminate. 
Qed.

Hint Resolve not_Nth_nil.

Lemma Nth_nth_default : forall X l n (a:X) d,
  Nth l n a ->
  nth_default d l n = a.
Proof.
  induction l; simpl; intros.
  destruct n; inversion H.
  unfold nth_default. rewrite H; auto.
Qed.

Lemma Nth_map : forall (A B:Type) (f:A -> B) l n a b
  (Hnth : Nth l n a)
  (Heq : b = f a),
  Nth (map f l) n b.
Proof.
  induction l; intros; subst.
  destruct n; inversion Hnth.
  destruct n. inversion Hnth. simpl; auto. 
  inversion Hnth; eapply IHl; eauto.
Qed.

Fixpoint Forall_dec {A} (P : A -> Prop) (p_dec:forall a, {P a} + {~ P a})
  (l:list A) : {Forall P l} + {~ Forall P l}.
  refine match l with
           | [] => left _
           | a::l' => match p_dec a, Forall_dec _ P p_dec l' with
                        | left Ha , left Hl' => left _
                        | _, _ => right _
                      end
         end; auto.
  - intro contra. inversion contra; subst. contradiction.
  - intro contra. inversion contra; subst. contradiction.
Defined.
Arguments Forall_dec {_ _} _ _.

Lemma Forall_Nth : forall (A:Type) l P (a:A) n,
  Forall P l ->
  Nth l n a ->
  P a.
Proof.
  intros. generalize dependent l.
  induction n; intros.
  inversion H; inversion H0; subst. discriminate.
  inversion H5; subst. inversion H; auto.
  destruct l. inversion H0.
  inversion H; eauto.
Qed.
  
Lemma Nth_Forall2_Nth : forall n (A B:Type) l1 l2 P (b:B),
  Nth l2 n b ->
  Forall2 P l1 l2 ->
  exists (a:A), (Nth l1 n a) /\ P a b.
Proof.
  induction n; intros.
  destruct l2. inversion H.
  inversion H0; subst.
  inversion H; subst.
  simpl; intuition eauto.
  inversion H0; subst. inversion H.
  simpl in *.
  ecase IHn; eauto.
Qed.

Lemma Forall_map_eq : forall A B (f g : A -> B) l
  (Hall : Forall (fun x => f x = g x) l),
  map f l = map g l.
Proof.
  induction l; auto; intro.
  inversion Hall; simpl.
  rewrite H1, IHl; auto.
Qed.

Fixpoint replace {A:Type} (l:list A) (n:nat) (a:A) : list A :=
  match n, l with
    | O, _::l' => a::l'
    | S n', a'::l' => a'::replace l' n' a
    | _, [] => []
  end.

Lemma replace_length : forall {A} l n (a : A),
  length (replace l n a) = length l.
Proof.
  induction l; simpl; intros.
  - destruct n; auto.
  - destruct n; simpl; auto.
Qed.

Lemma Nth_replace : forall {A} l n (a : A), n < length l ->
  Nth (replace l n a) n a.
Proof.
  induction l; simpl; intros.
  - inversion H.
  - destruct n; simpl; try constructor.
    unfold Nth; simpl; apply IHl; omega.
Qed.

Lemma nth_error_replace : forall {A} l n (a : A) n' (Hn : n < length l),
  nth_error (replace l n a) n' = if beq_nat n n' then Some a
                                 else nth_error l n'.
Proof.
  induction l; intros; try (solve [inversion Hn]); simpl in *.
  destruct n; destruct n'; auto; simpl.
  apply IHl; omega.
Qed.

Lemma replace_over : forall {A} l n (a : A) (Hnlt : ~n < length l),
  replace l n a = l.
Proof.
  induction l; intros; destruct n; simpl in *; auto; try omega.
  rewrite IHl; auto; omega.
Qed.


(* replicate ---------------------------------------------------------------- *)

Fixpoint replicate {A} (a:A) (n:nat) : list A :=
  match n with
  | O => nil
  | S n' => a :: replicate a n'
  end.

Lemma replicate_length : forall {A} n (a : A), length (replicate a n) = n.
Proof. induction n; simpl; auto. Qed.

Lemma replicate_Nth : forall {A} n (a : A) n' (Hlt : n' < n),
  Nth (replicate a n) n' a.
Proof.
  induction n; simpl; intros; [inversion Hlt|].
  destruct n'; auto.
  simpl; apply IHn; omega.
Qed.


(* Intervals ---------------------------------------------------------------- *)

Fixpoint interval n m := 
  match m with
  | O => []
  | S j => if le_lt_dec n j then interval n j ++ [j] else []
  end.

Lemma Forall_app : forall {A} P (l l': list A),
  Forall P (l ++ l') <-> Forall P l /\ Forall P l'.
Proof.
  induction l; simpl; intros.
  - split; auto; intros [? ?]; auto.
  - split; [intro H | intros [H ?]]; inversion H; subst.
    + rewrite IHl in *; destruct H3; auto.
    + constructor; auto; rewrite IHl; auto.
Qed.


Lemma interval_lt : forall m n, Forall (fun x => x < m) (interval n m).
Proof.
  induction m; simpl; auto; intros.
  destruct (le_lt_dec n m); auto.
  rewrite Forall_app; split; auto.
  eapply Forall_impl; eauto; auto.
Qed.

Lemma interval_ge : forall m n, Forall (fun x => x >= n) (interval n m).
Proof.
  induction m; simpl; auto; intros.
  destruct (le_lt_dec n m); auto.
  rewrite Forall_app; split; auto.
Qed.

Lemma interval_nil : forall n, interval n n = [].
Proof.
  intro; destruct n; auto; unfold interval.
  destruct (le_lt_dec (S n) n); auto; omega.
Qed.

Lemma interval_alt : forall m n, interval n m = 
  if lt_dec n m then n :: interval (S n) m else [].
Proof.
  induction m; auto; intro.
  unfold interval at 1; fold interval.
  destruct (le_lt_dec n m); destruct (lt_dec n (S m)); auto; try omega.
  rewrite IHm.
  destruct (lt_dec n m).
  - unfold interval at 2; fold interval.
    destruct (le_lt_dec (S n) m); auto; omega.
  - rewrite Lt.le_lt_or_eq_iff in *; destruct l; [contradiction | subst].
    rewrite interval_nil; auto.
Qed.

Lemma interval_length : forall m n, length (interval n m) = m - n.
Proof.
  induction m; auto; intro; simpl.
  destruct (le_lt_dec n m).
  - rewrite app_length, IHm; simpl.
    destruct n; omega.
  - destruct n; simpl; omega.
Qed.        

Lemma nth_error_nil : forall A n, nth_error ([] : list A) n = None.
Proof.
  induction n; auto.
Qed.

Lemma nth_error_In : forall {A} l n (a : A), nth_error l n = Some a -> In a l.
Proof.
  induction l; intros; destruct n; simpl in *; inversion H; eauto.      
Qed.

Lemma in_nth_error : forall A (x : A) l, In x l ->
  exists n, nth_error l n = Some x.
Proof.
  induction l; simpl; intros.
  - inversion H.
  - destruct H.
    + exists 0; subst; auto.
    + specialize (IHl H); destruct IHl as (n & ?); exists (S n); auto.
Qed.

Lemma nth_error_in : forall {A} (l : list A) n a,
  nth_error l n = Some a -> n < length l.
Proof.
  induction l; intros; destruct n; simpl in *; inversion H; subst.
  - omega.
  - specialize (IHl _ _ H); omega.
Qed.

Lemma nth_error_succeeds : forall {A} (l : list A) n, n < length l ->
  exists a, nth_error l n = Some a.
Proof.
  induction l; simpl; intros.
  - inversion H.
  - destruct n; simpl; eauto.
    apply IHl; omega.
Qed.

Fixpoint distinct {A} (l : list A) :=
  match l with
  | [] => True
  | a :: rest => ~In a rest /\ distinct rest
  end.



Lemma distinct_inj : forall {A} l i j (a : A) (Hdistinct : distinct l)
  (Hi : Nth l i a) (Hj : Nth l j a), i = j.
Proof.
  induction l; simpl; intros; unfold Nth in *; destruct i; simpl in *;
  inversion Hi; subst; destruct j; simpl in *; inversion Hj; subst;
  destruct Hdistinct as [Hin ?]; eauto.
  - contradiction Hin; eapply nth_error_In; eauto.
  - contradiction Hin; eapply nth_error_In; eauto.
Qed.

Lemma distinct_snoc : forall {A} l (a : A) (Hdistinct : distinct l)
  (Hin : ~In a l), distinct (l ++ [a]).
Proof.
  induction l; simpl; intros; auto.
  destruct Hdistinct; split; eauto; intro Hin'.
  rewrite in_app_iff in *; simpl in *; destruct Hin' as [? | [? | ?]];
    auto.
Qed.      

Lemma interval_distinct : forall m n, distinct (interval n m).
Proof.
  induction m; simpl; intros; auto.
  destruct (le_lt_dec n m); simpl; auto.
  apply distinct_snoc; auto.
  generalize (interval_lt m n); intro Hlt.
  intro Hin; rewrite Forall_forall in Hlt; specialize (Hlt _ Hin); omega.
Qed.


Lemma Nth_app1 : forall {A} l n (a : A) (Hnth : Nth l n a) l', 
  Nth (l ++ l') n a.
Proof.
  induction l; simpl; intros; destruct n; unfold Nth in *; simpl in *;
    inversion Hnth; subst; auto.
  erewrite IHl; eauto.
Qed.

Lemma Nth_app2 : forall {A} l n (a : A) (Hnth : Nth l n a) l',
  Nth (l' ++ l) (n + length l') a.
Proof.
  induction l'; simpl; intros.
  - rewrite <- plus_n_O; auto.
  - rewrite <- plus_n_Sm; unfold Nth; simpl; auto.
Qed.

Lemma Nth_app : forall {A} (l l' : list A) n a (Hnth : Nth (l ++ l') n a),
  if lt_dec n (length l) then Nth l n a else Nth l' (n - length l) a.
Proof.
  induction l; simpl; intros.
  - rewrite <- minus_n_O; auto.
  - destruct n; simpl in *; auto.
    specialize (IHl _ _ _ Hnth); destruct (lt_dec n (length l));
      destruct (lt_dec (S n) (S (length l))); auto; omega.
Qed.

Lemma interval_Nth : forall m n i (Hlt : i < m - n),
  Nth (interval n m) i (i + n).
Proof.
  induction m; simpl; intros.
  - inversion Hlt.
  - destruct (lt_dec i (m - n)).
    + specialize (IHm _ _ l).
      destruct (le_lt_dec n m); try omega.
      apply Nth_app1; auto.
    + destruct (le_lt_dec n m).
      * generalize (@Nth_app2 _ [m] 0); unfold Nth; simpl; intro.
        specialize (H _ eq_refl (interval n m)).
        rewrite interval_length in H.
        assert (i = m - n) as Hi by (destruct n; omega).
        rewrite Hi; assert (m - n + n = m) as Hm by omega; rewrite Hm; auto.
      * destruct n; omega.
Qed.

    
Lemma Forall2_forall : forall {A B} (P : A -> B -> Prop) al bl,
  Forall2 P al bl <-> (length al = length bl /\ 
                       forall i a b, Nth al i a -> Nth bl i b -> P a b).
Proof.
  induction al; simpl; intros.
  - split; [intro H; inversion H; subst | intros [H ?]].
    + split; auto; intros ? ? ? Hnth ?; destruct i; simpl in Hnth; 
      inversion Hnth.
    + destruct bl; inversion H; auto.
  - destruct bl; simpl; [split; [intro H | intros [H ?]]; inversion H|].
    split; [intro H | intros [H ?]]; inversion H; subst.
    + rewrite IHal in *; destruct H5; split; auto; intros i a1 b1 Ha1 Hb1.
      destruct i; simpl in *; eauto.
      inversion Ha1; inversion Hb1; subst; auto.
    + constructor.
      * specialize (H0 0); simpl in *; eauto.
      * rewrite IHal; split; auto; intros.
        specialize (H0 (S i)); simpl in H0; auto.
Qed.  

Opaque minus.
Lemma interval_shift : forall j i k, k <= i -> interval i j =
  map (fun x => x + k) (interval (i - k) (j - k)).
Proof.
  induction j; simpl; auto; intros.
  destruct (Compare_dec.le_lt_dec i j).
  - erewrite IHj; eauto.
    rewrite <- Minus.minus_Sn_m; simpl; [|omega].
    destruct (Compare_dec.le_lt_dec (i - k) (j - k)); [|omega].
    rewrite map_app; simpl.
    rewrite Nat.sub_add; auto; omega.
  - destruct (Compare_dec.le_lt_dec k j).
    + rewrite <- Minus.minus_Sn_m; simpl; try omega.
      destruct (Compare_dec.le_lt_dec (i - k) (j - k)); auto; try omega.
    + assert (S j - k = 0) as Heq by omega; rewrite Heq; auto.
Qed.
Transparent minus.

Corollary interval_S : forall j i, interval (S i) (S j) =
  map S (interval i j).
Proof.
  intros.
  rewrite interval_shift with (k := 1); [simpl | omega].
  repeat rewrite Nat.sub_0_r.
  apply map_ext; intro; omega.
Qed.



Lemma flat_map_map : forall A B C (f : B -> list C) (g : A -> B) l,
  flat_map f (map g l) = flat_map (fun x => f (g x)) l.
Proof.
  induction l; auto; simpl.
  rewrite IHl; auto.
Qed.

Lemma flat_map_ext : forall A B (f g : A -> list B),
  (forall a, f a = g a) -> forall l, flat_map f l = flat_map g l.
Proof.
  induction l; auto; simpl.
  rewrite H, IHl; auto.
Qed.

Lemma interval_in_iff : forall i j k, In k (interval i j) <-> i <= k < j.
Proof.
  intros; induction j; simpl; [omega|].
  destruct (Compare_dec.le_lt_dec i j); simpl; [|omega].
  rewrite in_app_iff, IHj; simpl; omega.
Qed.


Lemma app_nth_error1: forall (A : Type) (l l' : list A) (n : nat),
  n < length l -> nth_error (l ++ l') n = nth_error l n.
Proof.
  induction l; simpl; intros.
  inversion H.
  destruct n eqn:Heqn; auto.
  eapply IHl; omega.
Qed.

Lemma app_nth_error2 : forall (A : Type) (l l' : list A) (n : nat),
    length l <= n -> nth_error (l ++ l') n = nth_error l' (n - length l).
Proof.
  induction l; simpl; intros.
  auto with arith.
  destruct n eqn:Heqn.
  inversion H.
  simpl.
  eapply IHl; auto with arith.
Qed.

Lemma nth_error_nth : forall A l n (d:A),
      n < length l ->
      nth_error l n = Some (nth n l d).
Proof.
  induction l.
  inversion 1. simpl. intros.
  destruct n eqn:Heqn.
  auto. simpl. eapply IHl. omega.
Qed.

Section REMOVE.

Variables (A:Type) (dec:forall (x y : A), {x = y} + {x <> y}).

Lemma remove_not_In : forall l x y,
  In x l ->
  x <> y ->
  In x (remove dec y l).
Proof.
  induction l; intros.
  - inversion H.
  - inversion H; subst.
    + simpl. destruct (dec y x). contradict H0; auto. left; auto.
    + simpl. destruct (dec y a); subst; auto.
      right. apply IHl; auto.
Qed.
  
Lemma remove_length_le : forall l x,
  length (remove dec x l) <= length l.
Proof.
  induction l; intros; auto.
  simpl. destruct (dec x a); simpl; auto.
  specialize (IHl x). omega.
Qed.

Lemma remove_length : forall l x,
  In x l ->
  length (remove dec x l) < length l.
Proof.
  induction l; intros.
  - inversion H.
  - inversion H. 
    + subst. simpl. destruct (dec x x) as [_ | contra].
      unfold Peano.lt. eapply le_n_S. apply remove_length_le.
      contradict contra; auto.
    + simpl. specialize (IHl x H0). 
      destruct (dec x a); subst; simpl; omega.
Qed.

End REMOVE.



(* util *)
Lemma rev_nil_rev : forall A (l:list A),
  [] = rev l ->
  l = [].
Proof.
  intros. destruct l; auto.
  simpl in H. destruct (rev l); simpl in H; inversion H.
Qed.

Lemma nth_map_inv : forall A B (f:A -> B) l b n,
  nth_error (map f l) n = Some b ->
  exists a, nth_error l n = Some a /\ f a = b.
Proof.
  induction l; simpl; intros.
  - destruct n; inversion H.
  - destruct n; inversion H; subst.
    eexists; intuition eauto.
    ecase IHl as [? [? ?]]; eauto. 
Qed.


Fixpoint trim {A} (lo:list (option A)) : list A :=
  match lo with
  | [] | None::_ => []
  | Some a::lo' => a::trim lo'
  end.

(* alternate definition of nth to appease termination checker *)
Definition nth_f {A B} (d:B) (f:A->B) (n:nat) (l:list A) : B :=
  let fix loop n l {struct l} :=
      match n, l with
      | _, [] => d
      | O, a::l' => f a
      | S n', _::l' => loop n' l'
      end
  in loop n l.

Lemma nth_f_nth_error : forall A B (d:B) (f:A->B) l n,
  nth_f d f n l = match nth_error l n with
                 | None => d
                 | Some a => f a
                 end.
Proof.
  induction l; intros; destruct n; simpl; auto.
Qed.    


(* to appease termination checker *)
Definition assoc_f {A B C} (a_dec:forall a b:A, {a = b} + {a <> b})
           (d:C) (f:B -> C) (a:A) (l:list (A * B)) : C :=
  let fix rec l :=
      match l with
      | [] => d
      | (a',b)::l' => if a_dec a a' then f b else rec l'
      end in
  rec l.

Fixpoint assoc {A B} (a_dec:forall a b:A, {a = b} + {a <> b})
           (a:A) (l:list (A * B)) : option B :=
  match l with
  | [] => None
  | (a',b)::l' => if a_dec a a' then Some b else assoc a_dec a l'
  end.
  
Lemma assoc_f__assoc : forall A B C l a_dec d (f:B->C) (a:A),
  assoc_f a_dec d f a l =
  match assoc a_dec a l with
  | None => d
  | Some b => f b
  end.
Proof.
  induction l; intros.
  - auto.
  - simpl. destruct a. destruct (a_dec a0 a).
    auto.
    apply IHl.
Qed.

Lemma assoc_hd : forall A B (a:A) (b:B) l a_dec,
  assoc a_dec a ((a,b)::l) = Some b.
Proof.
  intros A B a b l a_dec.
  simpl. destruct (a_dec a a); auto.
  - contradiction n. reflexivity.
Qed.


Lemma assoc_tl : forall A B (a c:A) (b:B) l a_dec
    (Hneq : a <> c),
    assoc a_dec a ((c,b)::l) =
    assoc a_dec a l.
Proof.
  destruct l; intros; simpl in *.
  - destruct (a_dec a c). contradiction Hneq. reflexivity.
  - destruct p.
    destruct (a_dec a c). contradiction Hneq.
    reflexivity.
Qed.

Lemma assoc_cons_inv :
  forall A B (a c:A) (b d:B) l a_dec
    (Hl: assoc a_dec a ((c,b)::l) = Some d),
    (a = c /\ b = d) \/ (a <> c /\ assoc a_dec a l = Some d).
Proof.
  intros A B a c b d l a_dec Hl.
  simpl in Hl.
  destruct (a_dec a c).
  left. inversion Hl. tauto.
  right. tauto.
Qed.    
                         

Lemma assoc_In_snd : forall A B (l:list (A * B)) eq_dec a b,
  assoc eq_dec a l = Some b ->
  In b (map (@snd _ _) l).
Proof.
  induction l; intros; simpl in *.
  - inversion H.
  - destruct a. destruct (eq_dec _ _).
    + inversion_clear H; subst. auto.
    + right. eauto.
Qed.

Lemma assoc_In : forall A B (l:list (A * B)) eq_dec a b,
  assoc eq_dec a l = Some b ->
  In (a,b) l.
Proof.
  induction l; intros; simpl in *.
  - inversion H.
  - destruct a. destruct (eq_dec _ _).
    + inversion_clear H; subst. auto.
    + right. eauto.
Qed.

Lemma assoc_succeeds : forall {A B} (a_dec : forall a b : A, {a = b} + {a <> b})
  a l, In a (map (fst(B := B)) l) -> exists x, assoc a_dec a l = Some x.
Proof.
  induction l; simpl; intros.
  - contradiction.
  - destruct a0; simpl in *.
    destruct (a_dec a a0); eauto.
    apply IHl; destruct H; auto.
    contradiction n; auto.
Qed.

(*
Theorem assoc_map :
  forall A B C eq_dec (x : A) (f : B -> C) l,
    assoc eq_dec x (map (fun p => (fst p, f (snd p))) l) =
    'v <- assoc eq_dec x l; Some (f v).
Proof.
  intros; induction l; eauto.
  simpl. destruct a; simpl. rewrite IHl.
  destruct (eq_dec x a); simpl; eauto.
Qed.
*)


Lemma map_nth_error_none :
  forall A B  (l : list A) (f : A -> B) (n : nat),
  nth_error l n = None -> nth_error (map f l) n = None.
Proof.
  induction l; simpl; intros.
  - destruct n; auto.
  - destruct n. inversion H.
    simpl. apply IHl; auto.
Qed.  

Lemma nth_error_out:
  forall A (l : list A) (n : nat),
  nth_error l n = None -> length l <= n.
Proof.
  induction l; simpl; intros.
  - omega.
  - destruct n. inversion H. simpl in H. apply IHl in H. omega.
Qed.

Lemma map_ext_in : forall A B (f g : A -> B) l,
  (forall a, In a l -> f a = g a) -> 
  map f l = map g l.
Proof.
  induction l; auto. intros Heq.
  simpl. f_equal. apply Heq. simpl; auto. 
  apply IHl. intros ? Hin. apply Heq. simpl; auto.
Qed.


Ltac destruct_Forall_cons :=
  match goal with
    | H : Forall _ (_::_) |- _ => inversion H; subst; clear H
  end.
Hint Extern 2 => destruct_Forall_cons : inversions.

Definition snoc {A} (a:A) (l:list A) : list A :=
  l ++ [a].

Lemma snoc_nonnil : forall A l (a : A), snoc a l <> [].
Proof.
  unfold snoc; repeat intro.
  generalize (app_eq_nil _ _ H); intros (? & X); inversion X.
Qed.


Definition map_option {A B} (f:A -> option B) (l:list A) : option (list B) :=
  let fix loop l :=
      match l with
      | [] => Some []
      | a::l' =>
        match f a, loop l' with
        | Some b, Some bl => Some (b::bl)
        | _, _ => None
        end
      end
  in loop l.

Lemma map_option_map : forall A B C (f:A -> option B) (g:C -> A) (l:list C),
    map_option f (map g l) = map_option (fun x => f (g x)) l.
Proof.
  intros A B C f g l.
  induction l; simpl.
  - reflexivity.
  - destruct (f (g a)).
    +  rewrite IHl. reflexivity.
    + reflexivity.
Qed.      

Lemma map_option_nth : forall A B (f : A -> option B) l l',
  map_option f l = Some l' ->
  forall i x', nth_error l' i = Some x' <-> exists x, nth_error l i = Some x /\
    f x = Some x'.
Proof.
  induction l; simpl; intros.
  - inversion H; split.
    + rewrite nth_error_nil; discriminate.
    + intros (? & ? & ?); rewrite nth_error_nil in *; discriminate.
  - destruct (f a) eqn: Ha; [|discriminate].
    destruct (map_option f l) eqn: Hl'; [|discriminate].
    inversion H; subst.
    specialize (IHl _ eq_refl).
    destruct i; simpl; auto.
    split.
    + intro Hx; inversion Hx; subst; eauto.
    + intros (? & Hx & ?); inversion Hx; subst.
      rewrite Ha in *; auto.
Qed.

Lemma map_option_length : forall A B (f : A -> option B) l l',
  map_option f l = Some l' -> length l' = length l.
Proof.
  induction l; simpl; intros.
  - inversion H; auto.
  - destruct (f a); [|discriminate].
    destruct (map_option f l) eqn: Hl'; [|discriminate].
    inversion H; subst.
    simpl; rewrite IHl; auto.
Qed.

(*
Definition map_option_snd {A B C} (f : B -> option C) (p:A * B) : option (A * C) :=
  let '(x,y) := p in
  'z <- f y;
    Some (x,z).


*)

Fixpoint find_map {A B} (f : A -> option B) (l : list A) : option B :=
  match l with
  | [] => None
  | x::xs => match (f x) with
            | None => find_map f xs
            | Some ans => Some ans
            end
  end.


Definition opt_compose {A B C} (g:B -> C) (f:A -> option B) : A -> option C :=
  fun a => option_map g (f a).

Fixpoint option_iter {A} (f:A -> option A) (a:A) (n:nat) : option A :=
  match n with
  | 0 => Some a
  | S n' => match f a with
            | Some a' => option_iter f a' n'
            | None => None
            end
  end.

Arguments option_map {_ _} _ _.

Lemma option_map_id : forall A (a : option A), option_map id a = a.
Proof.
  unfold option_map; destruct a; auto.
Qed.

Lemma option_map_ext : forall A B (f g:A->B),
  (forall a, f a = g a) ->
  forall oa, option_map f oa = option_map g oa.
Proof.
  intros. destruct oa. simpl. rewrite H; auto. auto.
Qed.

Lemma option_map_some_inv {A B} : forall (o:option A) (f : A -> B) (b:B),
  option_map f o = Some b ->
  exists a, o = Some a /\ f a = b.
Proof.
  destruct o; simpl; intros; inversion H; eauto.
Qed.

Definition option_prop {A} (P: A -> Prop) (a:option A) :=
  match a with
    | None => True
    | Some a' => P a'
  end.

Definition option_bind {A B} (m:option A) (f:A -> option B) : option B :=
  match m with
  | Some a => f a
  | None => None
  end.

Definition option_bind2 {A B C} (m: option (A * B)) (f: A -> B -> option C) : option C :=
  match m with
  | Some (a, b) => f a b
  | None => None
  end.

Module OptionNotations.

  Notation "'do' x <- m ; f" := (option_bind m (fun x => f)) 
    (at level 200, x ident, m at level 100, f at level 200).

  Notation "'do' x , y <- m ; f" := (option_bind2 m (fun x y => f))
    (at level 200, x ident, y ident, m at level 100, f at level 200).

End OptionNotations.

Tactic Notation "not_var" constr(t) :=
  try (is_var t; fail 1 "not_var").

Create HintDb inversions.
Tactic Notation "iauto" := auto 10 with inversions.
Tactic Notation "ieauto" := eauto 10 with inversions.

Definition map_prod {A B C D} (p:A * B) (f:A -> C) (g:B -> D) : (C * D) :=
  (f (fst p), g (snd p)).

Definition flip := @Basics.flip.
Definition comp := @Basics.compose.

Notation "g `o` f" := (Basics.compose g f) 
  (at level 40, left associativity).

Lemma map_prod_distr_comp : forall A B C D E F
  (p:A * B) (f1:A -> C) (f2:B -> D) (g1:C -> E) (g2:D -> F),
  map_prod (map_prod p f1 f2) g1 g2 =
  map_prod p (g1 `o` f1) (g2 `o` f2).
Proof.
  unfold map_prod, Basics.compose. auto.
Qed.

Definition map_snd {A B C} (f:B -> C) : list (A * B) -> list (A * C) :=
  map (fun ab : A * B => let (a, b) := ab in (a, f b)).

Import OptionNotations.

Lemma option_bind_assoc {A B C} : forall (o:option A) (p:A -> option B) (q:B -> option C),
   (do y <- (do x <- o; p x); q y) = (do x <- o; do y <- p x; q y).
Proof.
  intros. destruct o; auto.
Qed.

Lemma option_bind_some_inv {A B} : forall (o:option A) (p:A -> option B) (b:B),
  (do x <- o; p x) = Some b ->
  exists a, o = Some a /\ p a = Some b.
Proof.
  intros. destruct o. eexists. eauto. inversion H.
Qed.

Lemma option_bind_None : forall A B (m : option A),
  (do x <- m; (None(A := B))) = None.
Proof.
  destruct m; auto.
Qed.

Lemma option_bind_some : forall A (m : option A),
  (do x <- m; Some x) = m.
Proof.
  destruct m; auto.
Qed.

Tactic Notation "inv_bind" hyp(H) :=
  repeat rewrite option_bind_assoc in H;
    match type of H with
    | option_bind ?o ?p = Some ?b => 
      let hy := fresh H in
      destruct o eqn:hy; [|discriminate]; simpl in H
    end.

