---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RankNTypes      #-}
{-# LANGUAGE TemplateHaskell #-}

module Flowbox.Bus.RPC.HandlerMap (
    module X,
    Callback,
    CallbackWithCid,
    HandlerMap,
    HandlerMapWithCid,
    topics,
    topicsWithCid,
    lookupAndCall,
    lookupAndCallWithCid,
) where

import           Control.Monad.Trans.State
import           Data.Map                  as X
import qualified Data.Map                  as Map

import           Flowbox.Bus.Data.Message                 (CorrelationID, Message)
import qualified Flowbox.Bus.Data.Message                 as Message
import           Flowbox.Bus.Data.Topic                   (Topic)
import           Flowbox.Bus.RPC.RPC                      (RPC)
import           Flowbox.Prelude                          hiding (error)
import           Flowbox.System.Log.Logger
import qualified Flowbox.Text.ProtocolBuffers as Proto



logger :: LoggerIO
logger = getLoggerIO $moduleName


type Callback s m = (Proto.Serializable args, Proto.Serializable result)
                  => (Topic -> Topic) -> (args -> RPC s m ([result], [Message])) -> StateT s m [Message]


type HandlerMap s m = Callback s m -> Map Topic (StateT s m [Message])


type CallbackWithCid s m = (Proto.Serializable args, Proto.Serializable result)
                  => (Topic -> Topic) -> (CorrelationID -> args -> RPC s m ([result], [Message])) -> StateT s m [Message]


type HandlerMapWithCid s m = CallbackWithCid s m -> Map Topic (StateT s m [Message])

topics :: HandlerMap s m -> [Topic]
topics handlerMap = Map.keys $ handlerMap undefined


topicsWithCid :: HandlerMapWithCid s m -> [Topic]
topicsWithCid handlerMap = Map.keys $ handlerMap undefined

lookupAndCall :: MonadIO m => HandlerMap s m -> Callback s m -> Topic -> StateT s m [Message]
lookupAndCall handlerMap callback topic = case Map.lookup topic $ handlerMap callback of
    Just action -> action
    Nothing     -> do let errMsg = "Unknown topic: " ++ show topic
                      logger error errMsg
                      return $ Message.mkError topic errMsg

lookupAndCallWithCid :: MonadIO m => HandlerMapWithCid s m -> CallbackWithCid s m -> Topic -> StateT s m [Message]
lookupAndCallWithCid handlerMap callback topic = case Map.lookup topic $ handlerMap callback of
    Just action -> action
    Nothing     -> do let errMsg = "Unknown topic: " ++ show topic
                      logger error errMsg
                      return $ Message.mkError topic errMsg