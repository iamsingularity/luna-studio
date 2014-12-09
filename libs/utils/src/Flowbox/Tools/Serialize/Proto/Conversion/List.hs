---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------
{-# LANGUAGE MultiParamTypeClasses #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Flowbox.Tools.Serialize.Proto.Conversion.List where

import qualified Data.Foldable as Foldable
import           Data.Sequence (Seq)
import qualified Data.Sequence as Sequence

import Flowbox.Prelude
import Flowbox.Tools.Conversion.Proto



instance Convert a b => Convert [a] (Seq b) where
    encode = Sequence.fromList . map encode
    decode = mapM decode . Foldable.toList


instance ConvertPure a b => ConvertPure [a] (Seq b) where
    encodeP = Sequence.fromList . map encodeP
    decodeP = map decodeP . Foldable.toList
