---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------

module Luna.Distribution.Config where

import           Data.Monoid
import qualified Distribution.Client.Config   as CabalConf
import           Distribution.Client.Sandbox  as Sandbox
import           Distribution.Client.Setup    (GlobalFlags)
import qualified Distribution.Client.Setup    as Setup
import           Distribution.Simple.Compiler (PackageDB (GlobalPackageDB, SpecificPackageDB))
import           Distribution.Simple.Setup    (Flag (Flag))
import           Distribution.Verbosity       as Verbosity

import           Flowbox.Config.Config (Config)
import qualified Flowbox.Config.Config as Config
import           Flowbox.Prelude


localPkgDB :: Config -> PackageDB
localPkgDB = SpecificPackageDB . Config.pkgDb . Config.local

globalPkgDB :: Config -> PackageDB
globalPkgDB = SpecificPackageDB . Config.pkgDb . Config.global

localPkgStack :: Config -> [PackageDB]
localPkgStack cfg = [ GlobalPackageDB
                    , localPkgDB  cfg
                    , globalPkgDB cfg
                    ]

globalPkgStack :: Config -> [PackageDB]
globalPkgStack cfg = [ GlobalPackageDB
                     , globalPkgDB cfg
                     , localPkgDB  cfg
                     ]

defaultGlobalFlags :: Config -> GlobalFlags
defaultGlobalFlags cfg = mempty { Setup.globalConfigFile = Flag $ (Config.cabal . Config.config) cfg }


readCabalCfg :: Config -> IO CabalConf.SavedConfig
readCabalCfg cfg = do
    let globalFlags = defaultGlobalFlags cfg
    (_, cabalCfg) <- Sandbox.loadConfigOrSandboxConfig Verbosity.normal globalFlags mempty
    return cabalCfg
