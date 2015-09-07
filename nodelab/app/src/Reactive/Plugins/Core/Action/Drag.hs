module Reactive.Plugins.Core.Action.Drag where

import           Utils.PreludePlus
import           Utils.Vector
import           Utils.Angle

import qualified JS.Bindings    as UI
import qualified JS.NodeGraph   as UI

import           Object.Object
import           Object.Node
import           Object.UITypes

import           Event.Keyboard hiding      ( Event )
import qualified Event.Keyboard as Keyboard
import           Event.Mouse    hiding      ( Event, WithObjects )
import qualified Event.Mouse    as Mouse
import           Event.Event
import           Event.WithObjects

import           Reactive.Plugins.Core.Action.Action
import           Reactive.Plugins.Core.Action.State.Drag
import qualified Reactive.Plugins.Core.Action.State.Graph     as Graph
import qualified Reactive.Plugins.Core.Action.State.Selection as Selection
import qualified Reactive.Plugins.Core.Action.State.Camera    as Camera
import qualified Reactive.Plugins.Core.Action.State.Global    as Global
import           Reactive.Plugins.Core.Action.State.UnderCursor


data ActionType = StartDrag
                | Moving
                | Dragging
                | StopDrag
                deriving (Eq, Show)

data Action = DragAction { _actionType :: ActionType
                         , _actionPos  :: Vector2 Int
                         }
              deriving (Eq, Show)


makeLenses ''Action


instance PrettyPrinter ActionType where
    display = show

instance PrettyPrinter Action where
    display (DragAction tpe point) = "dA(" <> display tpe <> " " <> display point <> ")"


toAction :: Event Node -> UnderCursor -> Maybe Action
toAction (Mouse (Mouse.Event tpe pos button keyMods _)) underCursor = case button of
    LeftButton         -> case tpe of
        Mouse.Pressed  -> if dragAllowed then case keyMods of
                                             (KeyMods False False False False) -> Just (DragAction StartDrag pos)
                                             _                                 -> Nothing
                                         else Nothing
        Mouse.Released -> Just (DragAction StopDrag pos)
        Mouse.Moved    -> Just (DragAction Moving   pos)
        _              -> Nothing
    _                  -> Nothing
    where dragAllowed   = not . null $ underCursor ^. nodesUnderCursor
toAction _ _ = Nothing

moveNodes :: Double -> Vector2 Int -> NodeCollection -> NodeCollection
moveNodes factor delta = fmap $ \node -> if node ^. selected then node & nodePos +~ deltaWs else node where
    deltaWs = deltaToWs factor delta

deltaToWs :: Double -> Vector2 Int -> Vector2 Double
deltaToWs factor delta = (/ factor) . fromIntegral <$> delta

instance ActionStateUpdater Action where
    execSt newActionCandidate oldState = case newAction of
        Just action -> ActionUI newAction newState
        Nothing     -> ActionUI  NoAction newState
        where
        oldDrag                          = oldState ^. Global.drag . history
        oldGraph                         = oldState ^. Global.graph
        oldNodes                         = Graph.getNodes oldGraph
        newGraph                         = Graph.updateNodes newNodes oldGraph
        camFactor                        = oldState ^. Global.camera . Camera.camera . Camera.factor
        emptySelection                   = null oldNodes
        newState                         = oldState & Global.iteration       +~ 1
                                                    & Global.drag  . history .~ newDrag
                                                    & Global.graph           .~ newGraph
        newAction                        = case newActionCandidate of
            DragAction Moving pt        -> case oldDrag of
                Nothing                 -> Nothing
                _                       -> Just $ DragAction Dragging pt
            _                           -> Just newActionCandidate
        newNodes                         = case newActionCandidate of
            DragAction tpe point        -> case tpe of
                StopDrag                -> case oldDrag of
                    Just oldDragState   -> moveNodes camFactor deltaSum oldNodes
                        where prevPos    = oldDragState ^. dragCurrentPos
                              startPos   = oldDragState ^. dragStartPos
                              delta      = point - prevPos
                              deltaSum   = point - startPos
                    Nothing             -> oldNodes
                _                       -> oldNodes
        newDrag                          = case newActionCandidate of
            DragAction tpe point        -> case tpe of
                StartDrag               -> Just $ DragHistory point point point
                Moving                  -> if emptySelection then Nothing else case oldDrag of
                    Just oldDragState   -> Just $ DragHistory startPos prevPos point
                        where startPos   = oldDragState ^. dragStartPos
                              prevPos    = oldDragState ^. dragCurrentPos
                    Nothing             -> Nothing
                StopDrag                -> Nothing


instance ActionUIUpdater Action where
    updateUI (WithState action state) = case action of
        DragAction tpe pt            -> case tpe of
            StartDrag                -> return ()
            Moving                   -> return ()
            Dragging                 -> dragNodesUI deltaWs selNodes
                                     >> displayConnections nodes connections
            StopDrag                 -> moveNodesUI selNodes
                                     >> displayConnections nodes connections
            where
                nodes                 = Graph.getNodes       $ state ^. Global.graph
                connections           = Graph.getConnections $ state ^. Global.graph
                selNodeIds            = state ^. Global.selection . Selection.nodeIds
                selNodes              = filter (\node -> node ^. nodeId `elem` selNodeIds) nodes
                factor                = state ^. Global.camera . Camera.camera . Camera.factor
                deltaWs               = case state ^. Global.drag . history of
                    Just dragState   -> deltaToWs factor delta where
                        delta         = dragState ^. dragCurrentPos - dragState ^. dragStartPos
                    Nothing          -> Vector2 0.0 0.0




dragNodesUI :: Vector2 Double -> NodeCollection -> IO ()
dragNodesUI delta nodes = mapM_ (UI.dragNode delta) nodes

moveNodesUI :: NodeCollection -> IO ()
moveNodesUI nodes = mapM_ UI.moveNode nodes
                  -- >> performGC



displayConnections :: NodeCollection -> Graph.ConnectionsCollections -> IO ()
displayConnections nodes connections = mapM_ (displayConnectionLine nodes) $ zip [0..] connections

-- TODO: Extract to a module
getNodePos :: NodeCollection -> NodeId -> Vector2 Double
getNodePos nodes findNodeId = case find (\node -> (node ^. nodeId) == findNodeId) nodes of
    Just node -> node ^. nodePos
    Nothing   -> error $ "Node " <> show findNodeId <> " not found"

displayConnectionLine :: NodeCollection -> (Int, (PortRef, PortRef)) -> IO ()
displayConnectionLine nodes (lineId, (srcPortRef, dstPortRef)) = do
    let srcWs@(Vector2 xSrcN ySrcN) = getNodePos nodes $ getNodeIdFromPortRef srcPortRef
        dstWs@(Vector2 xDstN yDstN) = getNodePos nodes $ getNodeIdFromPortRef dstPortRef
        outerPos             = portOuterBorder + distFromPort
        angleSrc             = calcAngle dstWs srcWs
        angleDst             = calcAngle srcWs dstWs
        ySrc                 = ySrcN + outerPos * sin angleSrc
        xSrc                 = xSrcN + outerPos * cos angleSrc
        yDst                 = yDstN + outerPos * sin angleDst
        xDst                 = xDstN + outerPos * cos angleDst
        -- (Vector2 vx vy)      = srcWs - ndWs
        -- draw                 = vx * vx + vy * vy > portOuterBorderSquared
    setAnglePortRef angleSrc srcPortRef
    setAnglePortRef angleDst dstPortRef
    print $ "lineId " <> show lineId <> " " <> show xSrc <> " " <> show ySrc <> "->" <> show xDst <> " " <> show yDst
    UI.displayConnection lineId xSrc ySrc xDst yDst
    print "done!"


setAnglePortRef :: Angle -> PortRef -> IO ()
setAnglePortRef refAngle portRef = setAngle (portRef ^. refPortType) refNodeId (portRef ^. refPortId) refAngle where
    refNodeId = portRef ^. refPortNode . nodeId

setAngle :: PortType -> NodeId -> PortId -> Angle -> IO ()
setAngle  InputPort = UI.setInputPortAngle
setAngle OutputPort = UI.setOutputPortAngle
