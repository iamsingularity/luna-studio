---------------------------------------------------------------------------
-- Copyright (C) Flowbox, Inc - All Rights Reserved
-- Unauthorized copying of this file, via any medium is strictly prohibited
-- Proprietary and confidential
-- Flowbox Team <contact@flowbox.io>, 2014
---------------------------------------------------------------------------

module Flowbox.AWS.S3.Directory where

import qualified Data.String.Utils as String
import           Data.Text         (Text)
import qualified Data.Text         as Text

import qualified Flowbox.AWS.S3.File     as File
import           Flowbox.AWS.S3.S3       (S3)
import qualified Flowbox.AWS.S3.S3       as S3
import           Flowbox.Prelude
import qualified Flowbox.System.FilePath as FilePath



directoryPrefix :: FilePath -> Maybe Text
directoryPrefix filePath = case filePath of
    "." -> Nothing
    p   -> if last p == '/'
        then Just $ Text.pack p
        else Just $ Text.pack (p ++ "/")


getContents :: FilePath -> S3 [FilePath]
getContents filePath = S3.withBucket $ \bucket -> do
    let prefix = directoryPrefix filePath
    rsp <- S3.query $ (S3.getBucket bucket) { S3.gbPrefix = prefix, S3.gbDelimiter = Just $ Text.pack "/" }
    return $ map Text.unpack $ (S3.gbrCommonPrefixes rsp) ++ (map S3.objectKey $ S3.gbrContents rsp)


getContentsRecurisively :: FilePath -> S3 [FilePath]
getContentsRecurisively filePath = S3.withBucket $ \bucket -> do
    let prefix = directoryPrefix filePath
    rsp <- S3.query $ (S3.getBucket bucket) { S3.gbPrefix = prefix }
    return $ map (Text.unpack . S3.objectKey) $ S3.gbrContents rsp


create :: FilePath -> S3 ()
create filePath = let normFilePath = FilePath.normalise' filePath
    in File.touch (normFilePath ++ "/")


exists :: FilePath -> S3 Bool
exists filePath = S3.withBucket $ \bucket -> do
    rsp <- S3.query $ (S3.getBucket bucket) { S3.gbPrefix = Just $ Text.pack filePath }
    let contents = S3.gbrContents rsp
        matching = filter ((==) (Text.pack filePath)) $ map S3.objectKey contents
    return $ length matching > 0


rename :: FilePath -> FilePath -> S3 ()
rename srcFilePath dstFilePath = do
    let normDstFilePath = (FilePath.normalise' dstFilePath) ++ "/"
    contents <- getContentsRecurisively srcFilePath
    let renames = zip contents $ map (String.replace srcFilePath normDstFilePath) contents
    mapM_ (uncurry File.rename) renames


remove :: FilePath -> S3 ()
remove filePath = do
    contents <- getContentsRecurisively filePath
    File.removeMany contents

--removeRecursive :: FilePath -> S3 ()
