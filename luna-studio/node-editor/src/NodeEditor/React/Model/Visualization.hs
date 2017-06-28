{-# LANGUAGE DeriveAnyClass #-}
module NodeEditor.React.Model.Visualization
    ( module NodeEditor.React.Model.Visualization
    , module X
    ) where

import           Common.Prelude
import           Data.Map                  (Map)
import qualified Data.Map                  as Map
import           LunaStudio.Data.NodeValue as X (VisualizationId, VisualizationValue (..), Visualizer, VisualizerName, VisualizerPath)


data VisualizationMode = Default
                       | Focused
                       | Preview
                       | FullScreen
                       deriving (Eq, Generic, NFData, Show)

instance Default VisualizationMode where def = Default

data VisualizationStatus = Ready
                         | Outdated
                         deriving (Eq, Generic, NFData, Show)


data RunningVisualization = RunningVisualization { _visualizationId   :: VisualizationId
                                                 , _visualizationMode :: VisualizationMode
                                                 , _runningVisualizer :: Visualizer
                                                 } deriving (Eq, Generic, NFData, Show)

data IdleVisualization = IdleVisualization { _visualizationStatus :: VisualizationStatus
                                           , _idleVisualizer      :: Visualizer
                                           } deriving (Eq, Generic, NFData, Show)

data NodeVisualizations = NodeVisualizations { _visualizations     :: Map VisualizationId RunningVisualization
                                             , _idleVisualizations :: [IdleVisualization]
                                             , _visualizers        :: Map VisualizerName VisualizerPath
                                             } deriving (Eq, Generic, NFData, Show)

makePrisms ''VisualizationStatus
makePrisms ''VisualizationMode
makeLenses ''RunningVisualization
makeLenses ''IdleVisualization
makeLenses ''NodeVisualizations

instance Default NodeVisualizations where def = NodeVisualizations def def def

toIdleVisualization :: VisualizationStatus -> RunningVisualization -> IdleVisualization
toIdleVisualization vs = IdleVisualization vs . view runningVisualizer

stopVisualizations :: NodeVisualizations -> NodeVisualizations
stopVisualizations nodeVis = nodeVis & visualizations     .~ def
                                     & idleVisualizations .~ (nodeVis ^. idleVisualizations) ++ (map (toIdleVisualization Ready) . Map.elems $ nodeVis ^. visualizations)
