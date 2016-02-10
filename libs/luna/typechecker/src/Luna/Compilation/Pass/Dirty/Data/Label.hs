module Luna.Compilation.Pass.Dirty.Data.Label where

import           Luna.Compilation.Pass.Dirty.Data.CallPointPath (CallPointPath)

import           Data.Construction
import           Luna.Syntax.Model.Layer
import           Prologue hiding (Getter, Setter)

import           Data.Prop
import           Luna.Evaluation.Model           (Draft)
import qualified Luna.Syntax.Model.Network.Term as Term
import           Luna.Syntax.Model.Network.Class (Network)

import           Luna.Evaluation.Runtime         (Static)
import           Luna.Syntax.AST.Term            (Term)


data DirtyVal = DirtyVal
        { _location :: CallPointPath
        , _required :: Bool
        , _dirty    :: Bool
        , _userNode :: Bool
        } deriving Show


makeLenses ''DirtyVal

instance Default DirtyVal where
    def = DirtyVal def False False False


data Dirty = Dirty deriving (Show, Eq, Ord)
type instance LayerData layout Dirty t = DirtyVal
instance Monad m => Creator    m (Layer layout Dirty a) where create = return $ Layer def
instance Monad m => Destructor m (Layer layout Dirty t) where destruct _ = return ()


type instance Prop Dirty (Term (Network '[Type, Succs, Markable, Meta ()]) Draft Static) = DirtyVal

instance Getter Dirty (Term (Network '[Type, Succs, Markable, Meta ()]) Draft Static) where
    getter _ _ = undefined

instance Setter Dirty (Cover (Term.Draft Static '[Type, Succs, Markable, Meta ()])) where
    setter _ _ _ = undefined

