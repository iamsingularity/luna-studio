---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Flowbox Team <contact@flowbox.io>, 2014
-- Proprietary and confidential
-- Unauthorized copying of this file, via any medium is strictly prohibited
---------------------------------------------------------------------------
{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE TemplateHaskell #-}

module Luna.Interpreter.Session.Cache.Value where

import           Control.Exception.Base (throw)
import           Control.Monad          (foldM)
import qualified Control.Monad.Catch    as Catch
import qualified Control.Monad.Ghc      as MGHC
import qualified Data.Map               as Map
import qualified Data.MultiSet          as MultiSet

import           Flowbox.Control.Error
import qualified Flowbox.Data.Error                           as ValueError
import qualified Flowbox.Data.Serialization                   as Serialization
import           Flowbox.Prelude
import           Flowbox.Source.Location                      (loc)
import           Flowbox.System.Log.Logger                    as L
import           Generated.Proto.Data.Value                   (Value)
import           Generated.Proto.Mode.Mode                    (Mode)
import           Generated.Proto.Mode.ModeValue               (ModeValue (ModeValue))
import qualified Luna.Graph.Flags                             as Flags
import qualified Luna.Interpreter.Session.Cache.Cache         as Cache
import           Luna.Interpreter.Session.Cache.Info          (CompValueMap)
import qualified Luna.Interpreter.Session.Cache.Info          as CacheInfo
import qualified Luna.Interpreter.Session.Cache.Status        as Status
import           Luna.Interpreter.Session.Data.AbortException (AbortException (AbortException))
import qualified Luna.Interpreter.Session.Data.CallPoint      as CallPoint
import           Luna.Interpreter.Session.Data.CallPointPath  (CallPointPath)
import           Luna.Interpreter.Session.Data.VarName        (VarName)
import qualified Luna.Interpreter.Session.Data.VarName        as VarName
import qualified Luna.Interpreter.Session.Env                 as Env
import qualified Luna.Interpreter.Session.Error               as Error
import qualified Luna.Interpreter.Session.Hint.Eval           as HEval
import           Luna.Interpreter.Session.Session             (Session)



logger :: LoggerIO
logger = getLoggerIO $(moduleName)


getIfReady :: CallPointPath -> Session mm [ModeValue]
getIfReady callPointPath = do
    varName   <- foldedReRoute callPointPath
    cacheInfo <- Cache.getCacheInfo callPointPath
    let status = cacheInfo ^. CacheInfo.status
    assertE (status == Status.Ready) $ Error.CacheError $(loc) $ concat ["Object ", show callPointPath, " is not computed yet."]
    get varName callPointPath


data Status = Ready
            | Modified
            | NonCacheable
            | NotInCache
            | Unknown
            deriving (Show, Eq)


getWithStatus :: CallPointPath -> Session mm (Status, [ModeValue])
getWithStatus callPointPath = do
    varName <- foldedReRoute callPointPath
    Env.cachedLookup callPointPath >>= \case
        Nothing        -> return (NotInCache, [])
        Just cacheInfo -> do
            allReady <- Env.getAllReady
            let returnBytes status = do
                    value <- get varName callPointPath
                    return (status, value)
                returnNothing status = return (status, [])

            case (cacheInfo ^. CacheInfo.status, allReady) of
                (Status.Ready,        True ) -> returnBytes   Ready
                (Status.Ready,        False) -> returnBytes   Unknown
                (Status.Modified,     _    ) -> returnBytes   Modified
                (Status.Affected,     _    ) -> returnBytes   Modified
                (Status.NonCacheable, _    ) -> returnNothing NonCacheable


reportIfVisible :: CallPointPath -> Session mm ()
reportIfVisible callPointPath = do
    Env.whenVisible callPointPath $
        foldedReRoute callPointPath >>= report callPointPath


report :: CallPointPath -> VarName -> Session mm ()
report callPointPath varName = do
    resultCB  <- Env.getResultCallBack
    projectID <- Env.getProjectID
    results   <- get varName callPointPath
    safeLiftIO' (Error.CallbackError $(loc)) $
        resultCB projectID callPointPath results


get :: VarName -> CallPointPath -> Session mm [ModeValue]
get varName callPointPath = do
    modes <- Env.getSerializationModes callPointPath
    if MultiSet.null modes
        then logger debug "No serialization modes set" >> return []
        else do
            cinfo <- Env.cachedLookup callPointPath <??&> Error.OtherError $(loc) "Internal error"
            let distinctModes = MultiSet.distinctElems modes
                valCache = cinfo ^. CacheInfo.values
            (modValues, valCache') <- foldM (computeLookupValue varName) ([], valCache) distinctModes
            Env.cachedInsert callPointPath $ CacheInfo.values .~ valCache' $ cinfo
            return modValues


computeLookupValue :: VarName -> ([ModeValue], CompValueMap) -> Mode -> Session mm ([ModeValue], CompValueMap)
computeLookupValue varName (modValues, compValMap) mode = do
    logger trace $ "Cached values count: " ++ show (Map.size compValMap)
    case Map.lookup (varName, mode) compValMap of
        Nothing -> do logger debug "Computing value"
                      val <- computeValue varName mode
                      let newMap = if null $ varName ^. VarName.hash
                            then compValMap
                            else Map.insert (varName, mode) val compValMap
                      return (ModeValue mode (Just val):modValues, compValMap) --newMap) --FIXME[PM] : temporarily disabled
        justVal -> do logger debug "Cached value"
                      return (ModeValue mode justVal:modValues, compValMap)


computeValue :: VarName -> Mode -> Session mm Value
computeValue varName mode = lift2 $ flip Catch.catch excHandler $ do
    logger trace toValueExpr
    action <- HEval.interpret'' toValueExpr "Mode -> IO (Maybe SValue)"
    liftIO $ action mode <??&.> "Internal error"
    where
        toValueExpr = "computeValue " ++ VarName.toString varName

        excHandler :: Catch.SomeException -> MGHC.Ghc Value
        excHandler exc = case Catch.fromException exc of
            Just AbortException -> throw AbortException
            Nothing -> do
                logger L.error $ show exc
                liftIO (Serialization.toValue (ValueError.Error $ show exc) def) <??&.> "Internal error"



foldedReRoute :: CallPointPath -> Session mm VarName
foldedReRoute callPointPath = do
    let callPointLast = last callPointPath
        callPointInit = init callPointPath
    mfoldTop <- Flags.getFoldTop <$> Env.getFlags callPointLast
    let newCallPointPath = case mfoldTop of
            Nothing     -> callPointPath
            Just nodeID -> callPointInit
                        ++ [callPointLast & CallPoint.nodeID .~ nodeID]
    cacheInfo <- Cache.getCacheInfo newCallPointPath
    return $ cacheInfo ^. CacheInfo.recentVarName
