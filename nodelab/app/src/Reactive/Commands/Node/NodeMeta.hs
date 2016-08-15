module Reactive.Commands.Node.NodeMeta
    ( updateNodesMeta
    ) where

import           Utils.PreludePlus
import           Utils.Vector

import           Empire.API.Data.Node         (NodeId)
import qualified Empire.API.Data.Node         as Node
import           Empire.API.Data.NodeMeta     (NodeMeta (..))
import qualified Empire.API.Data.NodeMeta     as NodeMeta

import           Reactive.Commands.Command    (Command)
import           Reactive.Commands.Graph      (nodeIdToWidgetId, updateConnectionsForNodes)
import qualified Reactive.Commands.UIRegistry as UICmd
import           Reactive.State.Global        (inRegistry)
import qualified Reactive.State.Global        as Global
import qualified Reactive.State.Graph         as Graph

updateNodeMeta' :: NodeId -> NodeMeta -> Command Global.State ()
updateNodeMeta' nodeId meta = do
    Global.graph . Graph.nodesMap . ix nodeId . Node.nodeMeta .= meta
    widgetId <- nodeIdToWidgetId nodeId
    inRegistry $ do
        withJust widgetId $ \widgetId -> do
            UICmd.move   widgetId $ fromTuple $  meta ^. NodeMeta.position


updateNodeMeta :: NodeId -> NodeMeta -> Command Global.State ()
updateNodeMeta nodeId meta = do
    updateNodeMeta' nodeId meta
    updateConnectionsForNodes [nodeId]

updateNodesMeta :: [(NodeId, NodeMeta)] -> Command Global.State ()
updateNodesMeta updates = do
    mapM (uncurry updateNodeMeta') updates
    updateConnectionsForNodes $ fst <$> updates
