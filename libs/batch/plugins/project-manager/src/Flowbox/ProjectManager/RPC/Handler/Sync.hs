---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE TemplateHaskell #-}
module Flowbox.ProjectManager.RPC.Handler.Sync where

import qualified Flowbox.Batch.Handler.Common                                   as Batch
import           Flowbox.Bus.RPC.RPC                                            (RPC)
import           Flowbox.Data.Convert
import           Flowbox.Prelude                                                hiding (Context)
import           Flowbox.ProjectManager.Context                                 (Context)
import           Flowbox.System.Log.Logger
import qualified Generated.Proto.ProjectManager.ProjectManager.Sync.Get.Request as SyncGet
import qualified Generated.Proto.ProjectManager.ProjectManager.Sync.Get.Status  as SyncGet



logger :: LoggerIO
logger = getLoggerIO $moduleName

------ public api -------------------------------------------------

syncGet :: SyncGet.Request -> RPC Context IO SyncGet.Status
syncGet request = do
    projectManager <- Batch.getProjectManager
    updateNo       <- Batch.getUpdateNo
    return $ SyncGet.Status request (encodeP $ show projectManager) updateNo