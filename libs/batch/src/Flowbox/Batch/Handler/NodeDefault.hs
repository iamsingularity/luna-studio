---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------

module Flowbox.Batch.Handler.NodeDefault (
    nodeDefaults,
    setNodeDefault,
    removeNodeDefault,
) where

import           Flowbox.Batch.Batch                         (Batch)
import           Flowbox.Batch.Handler.Common                (astOp, noresult, readonly)
import qualified Flowbox.Batch.Project.Project               as Project
import           Flowbox.Luna.Data.AST.Crumb.Crumb           (Breadcrumbs)
import           Flowbox.Luna.Data.Graph.Default.DefaultsMap (DefaultsMap)
import qualified Flowbox.Luna.Data.Graph.Default.DefaultsMap as DefaultsMap
import           Flowbox.Luna.Data.Graph.Default.Value       (Value)
import qualified Flowbox.Luna.Data.Graph.Node                as Node
import           Flowbox.Luna.Data.Graph.Port                (InPort)
import qualified Flowbox.Luna.Lib.Library                    as Library
import           Flowbox.Prelude



nodeDefaults :: Node.ID -> Breadcrumbs -> Library.ID -> Project.ID -> Batch -> IO DefaultsMap
nodeDefaults nodeID _ libID projectID  = readonly . astOp libID projectID (\_ ast propertyMap ->
    return ((ast, propertyMap), DefaultsMap.getDefaultsMap nodeID propertyMap))


setNodeDefault :: InPort -> Value
               -> Node.ID -> Breadcrumbs -> Library.ID -> Project.ID -> Batch -> IO Batch
setNodeDefault dstPort value nodeID _ libID projectID = noresult . astOp libID projectID (\_ ast propertyMap ->
    return ((ast, DefaultsMap.addDefault dstPort value nodeID propertyMap), ()))


removeNodeDefault :: InPort
                  -> Node.ID -> Breadcrumbs -> Library.ID -> Project.ID -> Batch -> IO Batch
removeNodeDefault dstPort nodeID _ libID projectID = noresult . astOp libID projectID (\_ ast propertyMap ->
    return ((ast, DefaultsMap.removeDefault dstPort nodeID propertyMap), ()))
