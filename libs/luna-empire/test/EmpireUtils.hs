{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE TypeApplications  #-}

module EmpireUtils (module EmpireUtils, module X) where

import Empire.Empire as X (runEmpire)
import SpecUtils     as X

import Empire.Prelude

import qualified Empire.Commands.Graph as Graph (getNodes)
import qualified Empire.Data.Library   as Library (body, path)

import Data.Reflection               (Given (..), give)
import Empire.Commands.Library       (listLibraries, withLibrary)
import Empire.Data.Graph             (ClsGraph, CommandState (..), userState)
import Empire.Empire                 (CommunicationEnv (..), Empire, Env,
                                      InterpreterEnv (..))
import LunaStudio.Data.Breadcrumb    (Breadcrumb (Breadcrumb))
import LunaStudio.Data.GraphLocation (GraphLocation (GraphLocation))
import LunaStudio.Data.Node          (NodeId, nodeId)
import Test.Hspec                    (Expectation)


runEmp'
    :: CommunicationEnv
    -> CommandState Env
    -> ClsGraph
    -> (Given GraphLocation => Empire a)
    -> IO (a, CommandState Env)
runEmp' env st newGraph act = runEmpire env st $ do
    lib <- head <$> listLibraries
    let path = lib ^. Library.path
    withLibrary path $ userState . Library.body .= newGraph
    let toLoc = GraphLocation path
    give (toLoc $ Breadcrumb []) act

graphIDs :: GraphLocation -> Empire [NodeId]
graphIDs loc = do
    nodes <- Graph.getNodes loc
    let ids = fmap (^. nodeId) nodes
    return ids

extractGraph :: CommandState InterpreterEnv -> ClsGraph
extractGraph = _clsGraph . view userState

withResult :: a -> (a -> IO b) -> IO b
withResult res act = act res

top :: Given GraphLocation => GraphLocation
top = given

emptyGraphLocation :: GraphLocation
emptyGraphLocation = GraphLocation "" $ Breadcrumb []

--[TODO]: This function exists for backwards compatibility, meant to be removed soon
specifyCodeChange :: Text -> Text -> (GraphLocation -> Empire a) -> CommunicationEnv -> Expectation
specifyCodeChange initialCode expectedCode action env =
    testCase initialCode expectedCode action env

