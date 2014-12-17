{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}


-- *------------------------------------------------
-- * Specification of the generic HM(X)
-- * type inference system in Haskell
-- *
-- * This instance deals with Ohori style records
-- *------------------------------------------------



module Main where


import qualified Luna.Parser.Parser as Parser

import qualified Luna.ASTNew.Decl       as Decl
import qualified Luna.ASTNew.Enum       as Enum
import qualified Luna.ASTNew.Label      as Label
import qualified Luna.ASTNew.Module     as Module
import qualified Luna.ASTNew.Name       as Name
import qualified Luna.ASTNew.Unit       as Unit



import           Luna.Data.Namespace               (Namespace (Namespace))
import           Luna.Data.Source                  (Code (Code), Medium (String), Source (Source))
import qualified Luna.Pass                         as Pass
import qualified Luna.Pass2.Analysis.Struct        as AA
import qualified Luna.Pass2.Transform.Parse.Stage1 as Stage1
import qualified Luna.Pass2.Transform.Parse.Stage2 as Stage2
import           Text.Show.Pretty                  (ppShow)


import qualified Luna.ASTNew.Traversals       as AST
import           Luna.ASTNew.Decl             (LDecl)
import qualified Luna.Parser.State            as ParserState
import           Luna.Pass                    (PassMonad, PassCtx, Pass(Pass))
import           Luna.ASTNew.Enum             (Enumerated, IDTag(IDTag))
import           Luna.ASTNew.Expr             (LExpr, Expr)
import           Luna.ASTNew.Module           (Module(Module), LModule)
import           Data.Monoid                  (Monoid, mempty)
import           Control.Monad.State          (put, get, modify)
import           Luna.ASTNew.NameBase         (nameBase)
import qualified Luna.ASTNew.Pat              as Pat
import qualified Luna.ASTNew.Arg              as Arg
import Data.Text.Lazy (unpack)
import qualified Luna.Pass2.Analysis.Struct as SA
import qualified Luna.Pass2.Transform.Hash                 as Hash
import qualified Luna.Pass2.Target.HS.HASTGen              as HASTGen
import qualified Luna.Pass2.Target.HS.HSC                  as HSC
import qualified Luna.Pass2.Transform.SSA                  as SSA
import qualified Luna.Pass2.Transform.Desugar.ImplicitSelf as ImplSelf

import Control.Applicative
import Control.Monad
import Control.Monad.Trans.Either

import Control.Lens hiding (without)
import Data.List    (intercalate,intersperse)




data StageTypechecker = StageTypechecker

type StageTypecheckerState = [String]

type StageTypecheckerPass             m       = PassMonad StageTypecheckerState m
type StageTypecheckerCtx              lab m a = (Enumerated lab, StageTypecheckerTraversal m a)
type StageTypecheckerTraversal        m   a   = (PassCtx m, AST.Traversal        StageTypechecker (StageTypecheckerPass m) a a)
type StageTypecheckerDefaultTraversal m   a   = (PassCtx m, AST.DefaultTraversal StageTypechecker (StageTypecheckerPass m) a a)


traverseM :: (StageTypecheckerTraversal m a) => a -> StageTypecheckerPass m a
traverseM = AST.traverseM StageTypechecker

defaultTraverseM :: (StageTypecheckerDefaultTraversal m a) => a -> StageTypecheckerPass m a
defaultTraverseM = AST.defaultTraverseM StageTypechecker


tcpass :: (Monoid s, StageTypecheckerDefaultTraversal m a) => Pass s (a -> StageTypecheckerPass m StageTypecheckerState)
tcpass = Pass "Typechecker"
              "Performs typechecking"
              mempty
              tcUnit

instance (StageTypecheckerCtx lab m a) => AST.Traversal StageTypechecker (StageTypecheckerPass m) (LModule lab a) (LModule lab a) where
  traverseM _ = tcMod

instance (StageTypecheckerCtx lab m a) => AST.Traversal StageTypechecker (StageTypecheckerPass m) (LDecl lab a) (LDecl lab a) where
  traverseM _ = tcDecl


tcDecl :: (StageTypecheckerCtx lab m a) => LDecl lab a -> StageTypecheckerPass m (LDecl lab a)
tcDecl all@(Label.Label lab decl) = do
    case decl of
      fun@Decl.Data{}                         -> modify ("Data"                         :)
      fun@Decl.Function{} -> modify ("Function" :)
      -- fun@Decl.Function{ Decl._fname = fname, Decl._inputs = inputs }
                                              -- -> do let args = map mapArg inputs
                                              --      modify (("Function " ++ nameBase fname ++ " " ++ intercalate " " args):)
      fun@Decl.Import{}                       -> modify ("Import"                       :)
      fun@Decl.TypeAlias{}                    -> modify ("TypeAlias"                    :)
      fun@Decl.TypeWrapper{}                  -> modify ("TypeWrapper"                  :)
      fun@Decl.Native{}                       -> modify ("Native"                       :)
    defaultTraverseM all
  where
    --mapArg :: Arg.Arg lab a -> String
    mapArg Arg.Arg{Arg._pat = (Label.Label _ (Pat.Var {Pat._vname = (Name.VName vname)}))}  = show vname
    mapArg _                                                                                = "?"

tcMod :: (StageTypecheckerCtx lab m a) => LModule lab a -> StageTypecheckerPass m (LModule lab a)
tcMod mod = modify ("456":) *> defaultTraverseM mod

tcUnit :: (StageTypecheckerDefaultTraversal m a) => a -> StageTypecheckerPass m StageTypecheckerState
tcUnit ast = do
  modify ("123123":)
  defaultTraverseM ast
  get






printer :: (Show a) => String -> a -> IO ()
printer x y = printer_aux x (show y)

printer_aux :: String -> String -> IO ()
printer_aux x y = do  f_print [Bold,White] "\n--------------------------------------------------------------------------------"
                      putStr "> "
                      f_print [Yellow] x
                      f_print [Bold,White] "--------------------------------------------------------------------------------\n"
                      putStrLn y

section :: IO () -> IO ()
section sec = do  sec
                  f_print [Bold, White] "\n\n################################################################################\n\n"


typecheck :: TypecheckerResult
typecheck = Done


data TypecheckerResult = Done
                       | Partial
                       | Fail


--test_foo :: String
--test_foo = unlines  [ "def foo a b:"
--                    , "  a + b"
--                    , ""
--                    , "def + x y:"
--                    , "  x"
--                    , ""
--                    , "def bar:"
--                    , "  foo 456 456"
--                    ]

main :: IO ()
main = do f_print [Bold,Green] "MAIN"
          f_print [Cyan] "Reading `src/Maintest.luna`"
          maintest_luna <- do tmp <- readFile "src/Maintest.luna"
                              tmp `seq` return tmp
          f_print [Cyan] "Passes"
          let src = Source "Maintest_luna" (String maintest_luna)

          result <- runEitherT $ do
            (ast1, astinfo1) <- Pass.run1_ Stage1.pass src
            sa1              <- Pass.run1_ SA.pass ast1
            (ast2, astinfo2) <- Pass.run3_ Stage2.pass (Namespace [] sa1) astinfo1 ast1
            (ast3, astinfo3) <- Pass.run2_ ImplSelf.pass astinfo2 ast2
            constraints      <- Pass.run1_ tcpass ast3
            sa2              <- Pass.run1_ SA.pass ast3
            ast4             <- Pass.run1_ Hash.pass ast3
            ast5             <- Pass.run1_ SSA.pass ast4
            hast             <- Pass.run1_ HASTGen.pass ast5
            hsc              <- Pass.run1_ HSC.pass hast
            return  ( (ast1, astinfo1)
                    , sa1
                    , (ast2, astinfo2)
                    , (ast3, astinfo3)
                    , constraints
                    , sa2
                    , ast4
                    , ast5
                    , hast
                    , hsc
                    )

          case result of
            Left _                      -> f_print [Red, Bold] "some error, sorry"
            Right ( (ast1, astinfo1), sa1, (ast2, astinfo2), (ast3, astinfo3), constraints, sa2, ast4, ast5, hast, hsc ) -> do
              section $ do
                printer_aux " 1.1. ast1"        $ ppShow $ ast1
                printer_aux " 1.2. astinfo1"    $ ppShow $ astinfo1
                printer_aux " 2.   sa1"         $ ppShow $ sa1
                printer_aux " 3.1. ast2"        $ ppShow $ ast2
                printer_aux " 3.2. astinfo2"    $ ppShow $ astinfo2
                printer_aux " 4.1. ast3"        $ ppShow $ ast3
                printer_aux " 4.2. astinfo3"    $ ppShow $ astinfo3
                printer_aux " 5.   constraints" $ ppShow $ constraints
                printer_aux " 6.   sa2"         $ ppShow $ sa2
                printer_aux " 7.   ast4"        $ ppShow $ ast4
                printer_aux " 8.   ast5"        $ ppShow $ ast5
                printer_aux " 9.   hast"        $ ppShow $ hast
                printer_aux "10.   hsc"         $ unpack $ hsc



data PrintAttrs = Black
                | Red
                | Green
                | Yellow
                | Blue
                | Magenta
                | Cyan
                | White
                | Bold

attrtonum :: PrintAttrs -> Int
attrtonum Black   = 30
attrtonum Red     = 31
attrtonum Green   = 32
attrtonum Yellow  = 33
attrtonum Blue    = 34
attrtonum Magenta = 35
attrtonum Cyan    = 36
attrtonum White   = 37
attrtonum Bold    = 1

f_print :: [PrintAttrs] -> String -> IO ()
f_print fs x = do let fmt = intercalate ";" (map (show.attrtonum) fs)
                  putStr $ "\x1b[" ++ fmt ++ "m"
                  putStr x
                  putStrLn "\x1b[0m"




-- *------------------------------------------------
-- * Category: DATA DECLARATIONS
-- *------------------------------------------------




-- The type language

type TVar       = Int
type Var        = Int
type Fieldlabel = Var
type Field      = (Fieldlabel, Type)
data Type       = TV TVar
                | Type `Fun` Type
                | Record [Field]
                    deriving (Show,Eq)


-- Note, record fields are sorted wrt field label


-- The constraint language

data Predicate  = TRUE
                | Type `Subsume` Type
                | Reckind Type Fieldlabel Type
                    deriving (Show,Eq)

data Constraint = C [Predicate]
                | Proj [TVar] [Predicate]
                     deriving Show


-- FILL IN: extend type and constraint language


-- Type schemes

data TypeScheme = Mono Type
                | Poly [TVar] Constraint Type
                     deriving Show

-- Substitutions and type environments

type Subst      = [(TVar, Type)]

type Typo       = [(Var,TypeScheme)]

-- The term language

--data Term       = Id Var | Abs Var Term | App Term Term
--                | Let Var Term Term
--                     deriving Show

-- The error monad

data E a        = Suc a | Err String
                     deriving Show

-- The type inference monad - a typing problem consists of a three tuple

data TP a = TP ( (TVar, Subst, Constraint) ->
                 E (TVar, Subst, Constraint, a))


-- *----------------------------------------
-- * Category: CLASS DECLARATIONS
-- *----------------------------------------


class TypesAndConstraints c where
 apply :: Subst -> c -> TP c
 tv    :: c -> [TVar]

-- apply -- applies a substitution to either a type or constraint
-- tv -- computes the free type variables

-- *-----------------------------------------
-- * Category: INSTANCE DECLARATIONS
-- *-----------------------------------------


instance TypesAndConstraints Predicate where
  apply s TRUE              = return TRUE
  apply s (t1 `Subsume` t2) = do t1' <- apply s t1
                                 t2' <- apply s t2
                                 return (t1' `Subsume` t2')
  apply s (Reckind t l t')  = do t1 <- apply s t
                                 t1' <- apply s t'
                                 return (Reckind t1 l t1')
  tv TRUE                   = []
  tv (t1 `Subsume` t2)      = (tv t1) ++ (tv t2)
  tv (Reckind t l t')       = (tv t) ++ (tv t')

instance TypesAndConstraints c => TypesAndConstraints [c] where
  apply s  = mapM (apply s)
  tv  a    = foldl f [] a where
                       f z x = z ++ (tv x)

instance TypesAndConstraints Constraint where
     apply s (C p)            = do p' <- apply s p
                                   return (C p')
     apply s (Proj tvl p)      = do p' <- apply s p
                                    return (Proj tvl p')
     tv (C p)                 = tv p
     tv (Proj tvl p)           = without (tv p)  tvl


instance TypesAndConstraints Type where
  apply s (TV tvl)           = case lookup tvl s of
                                  Just t  -> return t
                                  Nothing -> return (TV tvl)
  apply s (t1 `Fun` t2)     = do t1' <- apply s t1
                                 t2' <- apply s t2
                                 return (t1' `Fun` t2')
  apply s (Record [])        = return (Record [])
  apply s (Record ((l,t):f)) = do f' <- apply s (Record f)
                                  case f' of
                                    Record f'' -> do t' <- apply s t
                                                     return (Record ((l,t'):f''))
                                    _          -> report_error "apply:uncompatible types" (Record [])
  tv (TV tvl)                = [tvl]
  tv (t1 `Fun` t2)          = (tv t1) ++ (tv t2)
  tv (Record [])            = []
  tv (Record ((l,t):f))     = (tv t) ++ (tv (Record f))


instance TypesAndConstraints TypeScheme where
  apply s (Poly tvl c t)     = do c' <- apply s c
                                  t' <- apply s t
                                  return (Poly tvl c' t')
  apply s (Mono t)          = do t' <- apply s t
                                 return (Mono t')
  tv (Poly tvl c t)          = without ((tv t) ++ (tv c)) tvl
  tv (Mono t)               = tv t


-- FILL IN: instance declarations in case of extended type and
--          constraint language


-- *--------------------------------------------------
-- * Category: MONAD DECLARATIONS
-- *--------------------------------------------------


unTP (TP a) = a


instance Monad TP where
 m >>= k = TP ( \ (n,s,c) ->
                     case unTP (m) (n,s,c) of
                       Suc (n',s',c',x) -> unTP (k x) (n',s',c')
                       Err s            -> Err s )
 return x = TP ( \ (n,s,c) -> return (n,s,c,x) )


instance Monad E where
 m >>= k = case m of
           Suc a -> k a
           Err s -> Err s
 return x = Suc x


report_error :: String -> a -> TP a
report_error msg x =  TP ( \ (n,s,c) -> Err msg)


-- *---------------------------------------
-- * Category: INITIALIZATIONS
-- *---------------------------------------


null_subst :: Subst
null_subst = []

init_typo :: Typo

-- FILL IN: initial type environment

true_cons :: Constraint
true_cons = C [TRUE]

init_tvar :: TVar
init_tvar = 0

new_tvar :: TVar -> TVar
new_tvar n = n + 1



-- *--------------------------------------
-- * Category: Core type inferencer
-- *--------------------------------------


-- primitives for lists

without :: [TVar] -> [TVar] -> [TVar]
without [] a    = []
without (x:a) b = if elem x b then without a b
                  else x:(without a b)



-- primitives for dealing with constraints

add_cons :: Constraint -> Constraint -> Constraint
add_cons (C p1) (C p2)               = C (p1 ++ p2)
add_cons (C p1) (Proj tv p2)         = Proj tv (p1 ++ p2)
add_cons (Proj tv p1) (C p2)         = Proj tv (p1 ++ p2)
add_cons (Proj tv1 p1) (Proj tv2 p2) = Proj (tv1 ++ tv2) (p1 ++ p2)


projection :: Constraint -> [TVar] -> Constraint

-- FILL IN: definition of projection on constraints.
--          Projection might vary depending on different
--          kinds of constraint systems. A standard
--          definition can be found below.

--          projection (C p) tvl         = Proj tvl p
--          projection (Proj tv1 p) tv2 = Proj (tv1 ++ tv2) p


-- lifted functions


tv_typo :: Typo -> [TVar]
tv_typo env = foldl f [] env where
          f z (v,ts) = z ++ (tv ts)

add_constraint :: Constraint -> TP ()
add_constraint c1 =
     TP (\ (n,s,c) -> return (n,s,add_cons c c1,()))



-- handling of type variables and type environments

newtvar :: TP TVar
newtvar = TP (\ (n,s,c) -> return (new_tvar n,s,c,n) )

insert :: Typo -> (Var, TypeScheme) -> Typo
insert a (x,t) = (x,t):a

mylookup :: Typo -> Var -> E TypeScheme
mylookup [] y =
    Err "undeclared variable"
mylookup ((x,t):xs) y =
      if x == y then return t
      else mylookup xs y



-- instantiation and generalization



rename :: TP Subst -> TVar -> TP Subst
rename s x = do newtv <- newtvar
                s' <- s
                return ((x, TV newtv):s')

inst :: Typo -> Var -> TP Type
inst env x =
   case mylookup env x of
     Suc ts -> case ts of
                Mono t        -> return t
                Poly tvl c t  -> do s' <- foldl rename (return null_subst) tvl
                                    c' <- apply s' c
                                    t' <- apply s' t
                                    add_constraint c'
                                    return t'
     Err _  -> do ntv <- newtvar
                  report_error "undeclared variable" (TV ntv)






gen :: Typo -> Type -> TP TypeScheme
gen env t =
 TP ( \ (n,s,c) -> return (n,s, projection c (fv t c env), Poly (fv t c env) c t) )
                      where fv t1 c1 env1 = without ((tv t1) ++ (tv c1)) (tv_typo env1)



-- constraint solver



cs :: (Subst, Constraint) -> TP (Subst, Constraint)


-- that's what you need to supply


-- incorporating the constraint solver into monad TP

normalize :: Type -> TP Type
normalize a = do s <- get_subst
                 c <- get_cons
                 (s',c') <- cs (s,c)
                 t <- apply s' a
                 return_result s' c' t



get_subst :: TP Subst
get_subst = TP ( \ (n,s,c) -> return (n,s,c,s))

get_cons :: TP Constraint
get_cons = TP ( \ (n,s,c) -> return (n,s,c,c))

return_result :: Subst -> Constraint -> Type -> TP Type
return_result s c t = TP ( \ (n,s',c') -> return (n,s,c,t))


---- type inference

--tp :: (Typo, Term) -> TP Type
--tp (env, Id x) =  do a <- inst env x
--                     normalize a
----
--tp (env, Abs x e) = do a <- newtvar
--                       b <- tp (insert env (x, Mono (TV a)), e)
--                       normalize ((TV a) `Fun` b)

--tp (env, App e e') = do a <- newtvar
--                        t <- tp (env, e)
--                        t' <- tp (env, e')
--                        add_constraint (C [t `Subsume` (t' `Fun` TV a)])
--                        normalize (TV a)


--tp (env, Let x e e') = do a <- tp (env, e)
--                          b <- gen env a
--                          tp ((insert env (x, b)), e')

---- top-level program

--infer :: Term -> E (TVar, Subst, Constraint, Type)
--infer e = unTP (tp (init_typo, e)) (init_tvar, null_subst, true_cons)
----



-- *------------------------------------------
-- * Category: Record instance
-- *------------------------------------------



init_typo = []

-- Invariant: all constraints are true, hence projection is always trivial

projection _ _ = true_cons



cs (s, C c) =
 do (r,e) <- extract_predicates c
    (s,r') <- closure (s,r,e)
    b <- check_consistency r'
    if b then do c' <- apply s (C c)
                 c'' <- simplify c'
                 return (s, c'')
     else report_error "inconsistent constraint" (null_subst, C [TRUE])


-- divide predicates into record predicates and equality predicates

extract_predicates :: [Predicate] -> TP ([Predicate],[Predicate])
extract_predicates [] = return ([],[])
extract_predicates (TRUE:p) = extract_predicates p
extract_predicates ((t `Subsume` t'):p) =
       do (r,e) <- extract_predicates p
          return (r, (t `Subsume` t'):e)
extract_predicates ((Reckind t l t'):p) =
       do (r,e) <- extract_predicates p
          return ((Reckind t l t'):r, e)



closure ::  (Subst,[Predicate],[Predicate]) -> TP (Subst,[Predicate])
closure (s, r, e) =
   do s' <- do_unify(s,e)
      c <- apply s' (C r)
      case c of
        C p1 -> do  e1 <- extract1 p1
                    e2 <- extract2 p1
                    p2 <- simplify_predicate (e1 ++ e2)
                    if p2 == [] then return (s',p1)
                     else closure (s', p1, p2)
        _    -> report_error "closure:uncompatible constraint" (null_subst, [])


-- create subsumptions based on a label type of a particular record

extract1 :: [Predicate] -> TP [Predicate]
extract1 [] = return []
extract1 ((Reckind (Record f) l t):p) =
    do e <- get_extract1 f l t
       e' <- extract1 p
       return (e:e')
extract1 (_:p) = extract1 p

get_extract1 [] _ _          = report_error "extract1:field label not found -> inconsistent constraint" ((TV 0) `Subsume` (TV 0))
get_extract1 ((l,t):f) l' t' = if l == l' then return (t `Subsume` t')
                               else get_extract1 f l' t'

-- Create subsumptions for each label based on all constraints for a particular label and record. All equations for a particular label in a record must be satisfied

extract2 :: [Predicate] -> TP [Predicate]
extract2 [] = return []
extract2 ((Reckind t l t'):p) =
    do e <- extract2 p
       e' <- get_extract2 p t l t'
       return (e ++ e')
extract2 (_:p) = extract2 p

get_extract2 [] _ _ _ = return []
get_extract2 ((Reckind a l a'):p) t l' t' = if (l == l') && (a == t)
                then do e <- get_extract2 p t l' t'
                        return ((a' `Subsume` t'):e)
                else get_extract2 p t l' t'
get_extract2 (_:p) t l t'                 = get_extract2 p t l t'



check_consistency :: [Predicate] -> TP Bool
check_consistency [] = return True
check_consistency ((Reckind (Record f) l t'):p) = check_consistency p
check_consistency ((Reckind (TV a) l t'): p) = check_consistency p
check_consistency ((Reckind _ l t'):p) = return False
check_consistency (_:p) = check_consistency p



-- simplification of constraints

simplify :: Constraint -> TP Constraint
simplify (C p) = do p' <- simplify_predicate p
                    return (C p')


-- simplification of predicates

simplify_predicate :: [Predicate] -> TP [Predicate]
simplify_predicate [] = return []
simplify_predicate ((t `Subsume` t'):p) =
        do if t == t' then simplify_predicate p
            else do p' <- simplify_predicate p
                    return ((t `Subsume` t'):p')
simplify_predicate ((Reckind (Record f) l t'):p) =
       simplify_predicate p
simplify_predicate (x:p) =
       do p' <- simplify_predicate p
          if elem x p' then return p'
           else return (x:p')


-- assumption, there are only equ predicates

do_unify :: (Subst, [Predicate]) -> TP Subst
do_unify (s, []) = return s
do_unify (s, ((t `Subsume` t'):p)) =
   do s' <- unify(s,t,t')
      do_unify (s',p)
do_unify (s, (_:p)) = report_error "do_unify: predicate list not in normal form" null_subst



unify :: (Subst, Type, Type) -> TP Subst
unify (s, TV x, TV y) =
   if x == y then return s
   else do t <- apply s (TV x)
           return ((y, t):s)
unify (s, TV x, t) =
            do t'' <- apply s t
               if elem x (tv t'') then report_error "occurs check fails" null_subst
                else return ((x, t''):s)
unify (s, t, TV x) = unify (s, TV x, t)
unify (s, t1 `Fun` t1', t2 `Fun` t2') = do s' <- unify (s, t1, t2)
                                           unify (s', t1', t2')
unify (s, Record f, Record f') = g (s,f,f') where
          g (s, [], []) = return s
          g (s, (l,t):f, (l',t'):f') =
                        if l == l'
                        then do s' <- unify(s,t,t')
                                g(s',f,f')
                        else report_error "not matching record" null_subst
unify (s, _, _)  = report_error "unify:uncompatible type" null_subst




-- test cases

--test = infer (App (Abs 1 (Id 1)) (Abs 2 (Id 2)))

--test1 = infer (Abs 1 (Abs 2 (Id 1)))

--test2 = infer (Abs 1 (Id 1))

--test3 = infer (Abs 1 (App (Id 1) (Id 1)))

--test4 = infer (Let 1 (Abs 2 (Id 2)) (App (Id 1) (Abs 3 (Id 3))))

--test5 = infer (Let 1 (Abs 2 (Id 2)) (Id 1))

--test6 = infer (Let 1 (Abs 2 (Id 2)) (App (Id 1) (Id 1)))

--test7 = unTP (tp ([(1, Poly [0] (C []) ((TV 0) `Fun` (TV 0)))], App (Id 1) (Id 1))) (init_tvar, null_subst, true_cons)


--rec1 = unTP (tp ([(100, Mono (Record [(200, TV 300),(201, TV 301)])),
--            (101, Poly [302,303] ( C [Reckind (TV 302) 201 (TV 303)]) ((TV 302) `Fun` (TV 303)))],
--           App (Id 101) (Id 100)))
--           (init_tvar, null_subst, true_cons)


rec2 = cs(null_subst, ( C [(Reckind (TV 100) 200 ((TV 300) `Fun` (TV 300))),
                  (Reckind (TV 100) 200 (TV 301))]))

rec3 = cs(null_subst, (C  [(Reckind (TV 100) 200 ((TV 300) `Fun` (TV 301))),
                  (Reckind (TV 100) 200 ((TV 302) `Fun` (TV 302)))]))




