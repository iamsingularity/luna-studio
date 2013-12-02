---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2013
---------------------------------------------------------------------------

module Flowbox.Batch.Handler.Library (
    libraries,

    libraryByID,
    createLibrary,
    loadLibrary,
    unloadLibrary,
    storeLibrary,
    buildLibrary,
    runLibrary,
) where

import qualified Data.Maybe                                 as Maybe
import           Data.Version                                 (Version(Version))

import           Flowbox.Prelude                              
import qualified Flowbox.Batch.Batch                        as Batch
import           Flowbox.Batch.Batch                          (Batch)
import           Flowbox.Batch.Handler.Common                 (noresult, readonly, readonly', libManagerOp, libManagerOp', libraryOp, libraryOp')
import qualified Flowbox.Batch.Project.Project              as Project
import qualified Flowbox.Batch.Project.ProjectManager       as ProjectManager
import qualified Flowbox.Luna.Lib.LibManager                as LibManager
import qualified Flowbox.Luna.Lib.Library                   as Library
import           Flowbox.Luna.Lib.Library                     (Library)
import qualified Flowbox.Luna.Tools.Serialize.Proto.Library as LibSerialization
import qualified Flowbox.Luna.Passes.Build.Build            as Build
import qualified Flowbox.Luna.Passes.Build.BuildConfig      as BuildConfig
import           Flowbox.Luna.Passes.Build.BuildConfig        (BuildConfig(BuildConfig))
import qualified Flowbox.Luna.Passes.Build.Diagnostics      as Diagnostics
import qualified Flowbox.Luna.Passes.General.Luna.Luna      as Luna
import           Flowbox.System.Log.Logger                    
import qualified Flowbox.System.Platform                    as Platform
import qualified Flowbox.System.Process                     as Process
import qualified Flowbox.System.UniPath                     as UniPath
import           Flowbox.System.UniPath                       (UniPath)



loggerIO :: LoggerIO
loggerIO = getLoggerIO "Flowbox.Batch.Handler.Library"


libraries :: Project.ID -> Batch -> Either String [(Library.ID, Library)]
libraries projectID = readonly . libManagerOp projectID (\_ libManager -> 
    let r = LibManager.labNodes libManager 
    in Right (libManager, r))


libraryByID :: Library.ID -> Project.ID -> Batch -> Either String Library
libraryByID libID projectID = readonly . libraryOp libID projectID (\_ library -> do
    return (library, library))


createLibrary :: String -> UniPath -> Project.ID -> Batch -> Either String (Batch, (Library.ID, Library))
createLibrary name path projectID = libManagerOp projectID (\_ libManager -> do
    let library                = Library.make name path [name]
        (newLibManager, libID) = LibManager.insNewNode library libManager
    return (newLibManager, (libID, library)))


loadLibrary :: UniPath -> Project.ID -> Batch -> IO (Batch, (Library.ID, Library))
loadLibrary path projectID = libManagerOp' projectID (\_ libManager -> do
    r <- LibManager.loadLibrary path libManager
    return r)


unloadLibrary :: Library.ID -> Project.ID -> Batch -> Either String Batch
unloadLibrary libID projectID = noresult . libManagerOp projectID (\_ libManager -> 
    let newLibManager = LibManager.delNode libID libManager
    in Right (newLibManager, ()))


storeLibrary :: Library.ID -> Project.ID -> Batch -> IO ()
storeLibrary libID projectID = readonly' . libraryOp' libID projectID (\_ library -> do
    LibSerialization.storeLibrary library
    return (library, ()))


-- TODO [PM] : More remote arguments needed
buildLibrary :: Library.ID -> Project.ID -> Batch -> IO ()
buildLibrary libID projectID = readonly' . libraryOp' libID projectID (\batch library -> do
    loggerIO critical "Not implemented - buildLibrary"
    --let projManager = Batch.projectManager batch
    --    (Just proj) = ProjectManager.lab projManager projectID
    --    projectPath = Project.path proj

    --    defManger   = Library.defs library
    --    rootDefID   = Library.rootDefID
    --    rootDef     = Maybe.fromJust $ DefManager.lab defManger rootDefID
       
    --    name        = Library.name library
    --    version     = Version [1][]      -- TODO [PM] : hardcoded version
    --    cfg         = Batch.config batch
    --    diag        = Diagnostics.none   -- TODO [PM] : hardcoded diagnostics
    --    outputPath  = UniPath.append name projectPath 
    --    libs        = []                 -- TODO [PM] : hardcoded libs
    --    ghcFlags    = ["-O2"]            -- TODO [PM] : hardcoded ghc flags
    --    cabalFlags  = []                 -- TODO [PM] : hardcoded cabal flags
        
    --    buildType   = BuildConfig.Executable outputPath -- TODO [PM] : hardoded executable type
    --    bldCfg      = BuildConfig name version libs ghcFlags cabalFlags buildType cfg diag

    --Luna.runIO $ do ast <- Build.parseGraph diag defManger (rootDefID, rootDef)
    --                Build.run bldCfg ast
    return (library, ()))
    

-- TODO [PM] : Needs architecture change
runLibrary ::  Library.ID -> Project.ID -> Batch -> IO String
runLibrary libID projectID = readonly' . libraryOp' libID projectID (\batch library -> do
    let projManager = Batch.projectManager batch
        (Just proj) = ProjectManager.lab projManager projectID
        projectPath = Project.path proj

        name = Library.name library
        command = Platform.dependent ("./" ++ name) (name ++ ".exe") ("./" ++ name)
        noStandardInput = ""
        noArguments     = [] --TODO [PM] : reimplement all this method to support real programs
    loggerIO debug $ "Running command '" ++ command ++ "'"
    (errorCode, stdOut, stdErr) <- Process.readProcessWithExitCode (Just projectPath) command noArguments noStandardInput
    let exitMsg = "Program exited with " ++ (show errorCode) ++ " code"
    loggerIO debug exitMsg
    return (library, stdOut ++ stdErr ++ "\n" ++ "Program exited with " ++ (show errorCode) ++ " code"))
